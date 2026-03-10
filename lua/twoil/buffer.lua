local backend = require("twoil.backend")
local render = require("twoil.render")

local M = {}

local STATE = {
  buf = nil,
  snapshot = {},
}

local BUFFER_NAME = "twoil://tasks"
local HIGHLIGHT_NAMESPACE = vim.api.nvim_create_namespace("twoil-highlights")
local current_snapshot
local HIGHLIGHT_AUGROUP = vim.api.nvim_create_augroup("twoil-highlights", { clear = true })

local function get_hl(name)
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
  return ok and hl or {}
end

local function rgb_parts(color)
  local red = math.floor(color / 0x10000) % 0x100
  local green = math.floor(color / 0x100) % 0x100
  local blue = color % 0x100
  return red, green, blue
end

local function rgb_color(red, green, blue)
  return string.format("#%02x%02x%02x", red, green, blue)
end

local function blend(base, target, amount)
  local base_red, base_green, base_blue = rgb_parts(base)
  local target_red, target_green, target_blue = rgb_parts(target)

  local function mix(base_channel, target_channel)
    return math.floor((base_channel * (1 - amount)) + (target_channel * amount) + 0.5)
  end

  return rgb_color(
    mix(base_red, target_red),
    mix(base_green, target_green),
    mix(base_blue, target_blue)
  )
end

local function luminance(color)
  local red, green, blue = rgb_parts(color)
  return (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
end

local function define_highlights()
  local normal = get_hl("Normal")
  local title = get_hl("Title")
  local identifier = get_hl("Identifier")
  local special = get_hl("Special")
  local ok_hl = get_hl("DiagnosticOk")
  local comment = get_hl("Comment")
  local line_nr = get_hl("LineNr")

  local background = normal.bg or get_hl("NormalNC").bg or get_hl("NormalFloat").bg
  if not background then
    background = vim.o.background == "light" and 0xFFFFFF or 0x111111
  end

  local foreground = normal.fg or (luminance(background) > 127 and 0x1F2937 or 0xE5E7EB)
  local comment_fg = comment.fg or blend(background, foreground, 0.45)
  local readonly_fg = line_nr.fg or blend(background, foreground, 0.35)
  local pending_fg = identifier.fg or foreground
  local waiting_fg = special.fg or blend(background, foreground, 0.8)
  local done_fg = ok_hl.fg or blend(background, foreground, 0.75)
  local header_fg = title.fg or foreground
  local target = luminance(background) > 127 and 0x000000 or 0xFFFFFF
  local odd_bg = blend(background, target, luminance(background) > 127 and 0.035 or 0.06)
  local even_bg = blend(background, target, luminance(background) > 127 and 0.07 or 0.1)
  local header_bg = blend(background, target, luminance(background) > 127 and 0.1 or 0.16)

  local function define_row_set(suffix, bg)
    vim.api.nvim_set_hl(0, "TWOilPending" .. suffix, { fg = pending_fg, bg = bg })
    vim.api.nvim_set_hl(0, "TWOilWaiting" .. suffix, { fg = waiting_fg, bg = bg })
    vim.api.nvim_set_hl(0, "TWOilDone" .. suffix, { fg = done_fg, bg = bg })
    vim.api.nvim_set_hl(0, "TWOilNewRow" .. suffix, { fg = comment_fg, bg = bg, italic = true })
    vim.api.nvim_set_hl(0, "TWOilReadonly" .. suffix, { fg = readonly_fg, bg = bg })
    vim.api.nvim_set_hl(0, "TWOilPlaceholder" .. suffix, { fg = comment_fg, bg = bg, italic = true })
  end

  vim.api.nvim_set_hl(0, "TWOilHeader", { fg = header_fg, bg = header_bg, bold = true })
  define_row_set("Odd", odd_bg)
  define_row_set("Even", even_bg)
end

define_highlights()

vim.api.nvim_create_autocmd("ColorScheme", {
  group = HIGHLIGHT_AUGROUP,
  callback = define_highlights,
})

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "TWOil" })
end

local function reset_modified(bufnr)
  vim.api.nvim_set_option_value("modified", false, { buf = bufnr })
end

local function set_buffer_lines(bufnr, lines)
  vim.api.nvim_set_option_value("modifiable", true, { buf = bufnr })
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  reset_modified(bufnr)
end

local function add_highlight(bufnr, group, line, start_col, end_col)
  vim.api.nvim_buf_add_highlight(bufnr, HIGHLIGHT_NAMESPACE, group, line, start_col, end_col)
end

local function add_row_fill(bufnr, line, line_text, target_width, group)
  local line_width = vim.fn.strdisplaywidth(line_text)
  local fill_width = target_width - line_width
  if fill_width <= 0 then
    return
  end

  vim.api.nvim_buf_set_extmark(bufnr, HIGHLIGHT_NAMESPACE, line, #line_text, {
    virt_text = { { string.rep(" ", fill_width), group } },
    virt_text_pos = "inline",
    hl_mode = "combine",
  })
end

local function configure_window(bufnr, layout)
  local winid = vim.fn.bufwinid(bufnr)
  if winid == -1 then
    return
  end

  vim.api.nvim_set_option_value("wrap", false, { win = winid })
  vim.api.nvim_set_option_value("linebreak", false, { win = winid })
  vim.api.nvim_set_option_value("breakindent", false, { win = winid })
  vim.api.nvim_set_option_value("number", false, { win = winid })
  vim.api.nvim_set_option_value("relativenumber", false, { win = winid })
  vim.api.nvim_set_option_value("signcolumn", "no", { win = winid })
  vim.api.nvim_set_option_value("foldcolumn", "0", { win = winid })
  vim.api.nvim_set_option_value("showbreak", "", { win = winid })
end

local function apply_highlights(bufnr)
  local snapshot = current_snapshot(bufnr)
  if not snapshot or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  vim.api.nvim_buf_clear_namespace(bufnr, HIGHLIGHT_NAMESPACE, 0, -1)

  if #lines == 0 then
    return
  end

  local max_row_width = 0
  for _, line_text in ipairs(lines) do
    max_row_width = math.max(max_row_width, vim.fn.strdisplaywidth(line_text))
  end

  add_highlight(bufnr, "TWOilHeader", 0, 0, -1)
  add_row_fill(bufnr, 0, lines[1], max_row_width, "TWOilHeader")

  local continuation_group = "TWOilPendingOdd"
  local parity_suffix = "Odd"
  local stripe_index = 0
  for line_index = 2, #lines do
    local row = render.parse_row(lines[line_index], snapshot.layout)
    local line = line_index - 1

    if row.kind == "existing" then
      stripe_index = stripe_index + 1
      parity_suffix = stripe_index % 2 == 1 and "Odd" or "Even"

      local row_group = "TWOilPending" .. parity_suffix
      if row.status == "waiting" then
        row_group = "TWOilWaiting" .. parity_suffix
      end
      if row.status == "done" then
        row_group = "TWOilDone" .. parity_suffix
      end

      continuation_group = row_group
      add_highlight(bufnr, "TWOilReadonly" .. parity_suffix, line, 0, row.id_col_end)
      add_highlight(bufnr, row_group, line, 0, -1)
      add_row_fill(bufnr, line, lines[line_index], max_row_width, row_group)

      if row.project_raw == render.PLACEHOLDER then
        add_highlight(bufnr, "TWOilPlaceholder" .. parity_suffix, line, row.project_col_start, row.project_col_end)
      end
    elseif row.kind == "new" then
      stripe_index = stripe_index + 1
      parity_suffix = stripe_index % 2 == 1 and "Odd" or "Even"
      continuation_group = "TWOilNewRow" .. parity_suffix
      add_highlight(bufnr, continuation_group, line, 0, -1)
      add_highlight(bufnr, "TWOilReadonly" .. parity_suffix, line, 0, row.id_col_end)
      add_row_fill(bufnr, line, lines[line_index], max_row_width, continuation_group)

      if row.project_raw == render.PLACEHOLDER then
        add_highlight(bufnr, "TWOilPlaceholder" .. parity_suffix, line, row.project_col_start, row.project_col_end)
      end

      if row.description_raw == render.PLACEHOLDER then
        add_highlight(bufnr, "TWOilPlaceholder" .. parity_suffix, line, row.description_col_start, -1)
      end
    elseif row.kind == "continuation" then
      add_highlight(bufnr, continuation_group, line, 0, -1)
      add_highlight(bufnr, "TWOilReadonly" .. parity_suffix, line, 0, row.id_col_end)
      add_row_fill(bufnr, line, lines[line_index], max_row_width, continuation_group)
    end
  end
end

local function remember_snapshot(bufnr, tasks, layout)
  STATE.buf = bufnr
  STATE.snapshot[bufnr] = {
    tasks = tasks,
    layout = layout,
    filters = STATE.snapshot[bufnr] and STATE.snapshot[bufnr].filters or {},
  }
end

function current_snapshot(bufnr)
  return STATE.snapshot[bufnr]
end

local function clear_snapshot(bufnr)
  STATE.snapshot[bufnr] = nil
  if STATE.buf == bufnr then
    STATE.buf = nil
  end
end

local function create_buffer()
  local bufnr = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_option_value("buftype", "acwrite", { buf = bufnr })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = bufnr })
  vim.api.nvim_set_option_value("swapfile", false, { buf = bufnr })
  vim.api.nvim_set_option_value("filetype", "twoil", { buf = bufnr })
  vim.api.nvim_buf_set_name(bufnr, BUFFER_NAME)

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = bufnr,
    callback = function(args)
      require("twoil.buffer").sync(args.buf)
    end,
  })

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = bufnr,
    callback = function(args)
      clear_snapshot(args.buf)
    end,
  })

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    buffer = bufnr,
    callback = function(args)
      require("twoil.buffer").refresh_highlights(args.buf)
    end,
  })

  return bufnr
end

local function ensure_buffer()
  if STATE.buf and vim.api.nvim_buf_is_valid(STATE.buf) then
    return STATE.buf
  end

  return create_buffer()
end

local function render_into_buffer(bufnr, tasks)
  local winid = vim.fn.bufwinid(bufnr)
  local window_width = winid ~= -1 and vim.api.nvim_win_get_width(winid) or 80
  local layout = render.build_layout(tasks, window_width)
  local lines = render.render(tasks, layout)

  remember_snapshot(bufnr, tasks, layout)
  set_buffer_lines(bufnr, lines)
  configure_window(bufnr, layout)
  apply_highlights(bufnr)
end

function M.refresh(bufnr, filters)
  local snapshot = current_snapshot(bufnr)
  local active_filters = filters or (snapshot and snapshot.filters) or {}

  backend.fetch_tasks(active_filters, function(tasks, err)
    if err then
      notify(err, vim.log.levels.ERROR)
      return
    end

    if not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end

    render_into_buffer(bufnr, tasks)
    STATE.snapshot[bufnr].filters = vim.deepcopy(active_filters)
    notify("Loaded " .. tostring(#tasks) .. " tasks")
  end)
end

function M.open(filters)
  if not backend.is_available() then
    notify("`task` executable not found in PATH", vim.log.levels.ERROR)
    return
  end

  local bufnr = ensure_buffer()
  vim.api.nvim_set_current_buf(bufnr)
  M.refresh(bufnr, filters or {})
end

function M.refresh_highlights(bufnr)
  apply_highlights(bufnr)
end

function M.sync(bufnr)
  local snapshot = current_snapshot(bufnr)
  if not snapshot then
    notify("No TWOil task state found for this buffer", vim.log.levels.ERROR)
    return
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local changes, err = render.diff(lines, snapshot)
  if err then
    notify(err, vim.log.levels.ERROR)
    return
  end

  backend.apply_changes(changes, function(apply_err)
    if apply_err then
      notify(apply_err, vim.log.levels.ERROR)
      return
    end

    if #changes == 0 then
      reset_modified(bufnr)
      notify("No changes to sync")
      return
    end

    M.refresh(bufnr, snapshot.filters)
    notify("Synced " .. tostring(#changes) .. " change(s)")
  end)
end

return M
