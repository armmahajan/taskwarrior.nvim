local M = {}

M.PLACEHOLDER = "·"
M.NEW_ROW_MARKER = "+"
M.CONTINUATION_MARKER = "↳"
M.MIN_DESCRIPTION_WIDTH = 12
M.RIGHT_PADDING = 4

local EDITABLE_STATUSES = {
  done = true,
  pending = true,
  waiting = true,
}

local function trim(value)
  return vim.trim(value or "")
end

local function pad(value, width)
  return string.format("%-" .. width .. "s", value)
end

local function wrap_text(text, width)
  if text == "" then
    return { "" }
  end

  local chunks = {}
  local current = {}
  local current_length = 0

  for word in text:gmatch("%S+") do
    local word_length = #word

    if word_length > width then
      if #current > 0 then
        chunks[#chunks + 1] = table.concat(current, " ")
        current = {}
        current_length = 0
      end

      local start_index = 1
      while start_index <= word_length do
        chunks[#chunks + 1] = word:sub(start_index, start_index + width - 1)
        start_index = start_index + width
      end
    elseif current_length == 0 then
      current[1] = word
      current_length = word_length
    elseif current_length + 1 + word_length <= width then
      current[#current + 1] = word
      current_length = current_length + 1 + word_length
    else
      chunks[#chunks + 1] = table.concat(current, " ")
      current = { word }
      current_length = word_length
    end
  end

  if #current > 0 then
    chunks[#chunks + 1] = table.concat(current, " ")
  end

  return #chunks > 0 and chunks or { "" }
end

local function display_project(project)
  if project and project ~= "" then
    return project
  end

  return M.PLACEHOLDER
end

local function display_description(description)
  if description and description ~= "" then
    return description
  end

  return M.PLACEHOLDER
end

local function normalize_project(value)
  local text = trim(value)
  if text == "" or text == M.PLACEHOLDER then
    return nil
  end

  return text
end

local function normalize_description(value)
  local text = trim(value)
  if text == "" or text == M.PLACEHOLDER then
    return ""
  end

  return text
end

function M.build_layout(tasks, window_width)
  local id_width = #("ID")
  local status_width = #("Status")
  local project_width = #("Project")

  for _, task in ipairs(tasks) do
    id_width = math.max(id_width, #(tostring(task.id or "")))
    status_width = math.max(status_width, #(task.status or ""))
    project_width = math.max(project_width, #(display_project(task.project)))
  end

  id_width = math.max(id_width, #(M.NEW_ROW_MARKER), #(M.CONTINUATION_MARKER))
  status_width = math.max(status_width, #("pending"))
  project_width = math.max(project_width, 12)

  local layout = {
    id_width = id_width,
    status_width = status_width,
    project_width = project_width,
  }

  local description_width = (window_width or 80) - M.description_column(layout) - M.RIGHT_PADDING
  layout.description_width = math.max(M.MIN_DESCRIPTION_WIDTH, description_width)

  return layout
end

function M.description_column(layout)
  return layout.id_width + 2 + layout.status_width + 2 + layout.project_width + 2
end

function M.header_line(layout)
  return table.concat({
    pad("ID", layout.id_width),
    "  ",
    pad("Status", layout.status_width),
    "  ",
    pad("Project", layout.project_width),
    "  ",
    "Description",
  })
end

function M.render_task_lines(task, layout)
  local description_chunks = wrap_text(display_description(task.description), layout.description_width)
  local lines = {
    table.concat({
      pad(tostring(task.id or ""), layout.id_width),
      "  ",
      pad(task.status or "", layout.status_width),
      "  ",
      pad(display_project(task.project), layout.project_width),
      "  ",
      description_chunks[1],
    }),
  }

  for index = 2, #description_chunks do
    lines[#lines + 1] = table.concat({
      pad(M.CONTINUATION_MARKER, layout.id_width),
      "  ",
      pad("", layout.status_width),
      "  ",
      pad("", layout.project_width),
      "  ",
      description_chunks[index],
    })
  end

  return lines
end

function M.render_new_row_lines(layout)
  return {
    table.concat({
      pad(M.NEW_ROW_MARKER, layout.id_width),
      "  ",
      pad("pending", layout.status_width),
      "  ",
      pad(M.PLACEHOLDER, layout.project_width),
      "  ",
      M.PLACEHOLDER,
    }),
  }
end

function M.render(tasks, layout)
  local lines = { M.header_line(layout) }

  for _, task in ipairs(tasks) do
    vim.list_extend(lines, M.render_task_lines(task, layout))
  end

  vim.list_extend(lines, M.render_new_row_lines(layout))
  return lines
end

function M.parse_row(line, layout)
  local id_end = layout.id_width
  local status_start = id_end + 3
  local status_end = status_start + layout.status_width - 1
  local project_start = status_end + 3
  local project_end = project_start + layout.project_width - 1
  local description_start = project_end + 3

  local id = trim(line:sub(1, id_end))
  local status = trim(line:sub(status_start, status_end))
  local project_raw = trim(line:sub(project_start, project_end))
  local description_raw = trim(line:sub(description_start))

  local row = {
    raw = line,
    id = id,
    status = status,
    project_raw = project_raw,
    description_raw = description_raw,
    project = normalize_project(project_raw),
    description = normalize_description(description_raw),
    id_col_end = id_end,
    status_col_start = status_start - 1,
    status_col_end = status_end,
    project_col_start = project_start - 1,
    project_col_end = project_end,
    description_col_start = description_start - 1,
  }

  local trimmed = trim(line)
  if trimmed == "" then
    row.kind = "blank"
    return row
  end

  if tonumber(id) ~= nil then
    row.kind = "existing"
    return row
  end

  if id == M.CONTINUATION_MARKER then
    row.kind = "continuation"
    return row
  end

  if id == M.NEW_ROW_MARKER then
    row.kind = "new"
    return row
  end

  row.kind = "invalid"
  return row
end

local function validate_existing_row(row, line_number)
  if not EDITABLE_STATUSES[row.status] then
    return "row " .. line_number .. ": unsupported status `" .. row.status .. "`"
  end

  if row.description == "" then
    return "row " .. line_number .. ": description cannot be blank; delete the row to delete the task"
  end

  return nil
end

local function validate_new_row(row, line_number)
  local has_project = row.project ~= nil
  local has_description = row.description ~= ""
  local has_status = row.status ~= "" and row.status ~= "pending"

  if not has_project and not has_description and not has_status then
    return "empty"
  end

  if row.status == "" then
    row.status = "pending"
  end

  if not EDITABLE_STATUSES[row.status] then
    return "row " .. line_number .. ": unsupported status `" .. row.status .. "`"
  end

  if row.status ~= "pending" then
    return "row " .. line_number .. ": new tasks must start with status `pending`"
  end

  if row.description == "" then
    return "row " .. line_number .. ": new tasks need a description"
  end

  return nil
end

function M.diff(lines, snapshot)
  if #lines == 0 then
    return nil, "the TWOil buffer cannot be empty"
  end

  local expected_header = M.header_line(snapshot.layout)
  if lines[1] ~= expected_header then
    return nil, "the header row is not editable"
  end

  local tasks_by_id = {}
  local seen_ids = {}
  local changes = {}

  for _, task in ipairs(snapshot.tasks) do
    tasks_by_id[tostring(task.id)] = task
  end

  local logical_rows = {}
  local current_row

  for line_number = 2, #lines do
    local row = M.parse_row(lines[line_number], snapshot.layout)
    row.line_number = line_number - 1

    if row.kind == "blank" then
      goto continue
    end

    if row.kind == "continuation" then
      if not current_row then
        return nil, "row " .. row.line_number .. ": continuation line must follow a task row"
      end

      current_row.description_parts[#current_row.description_parts + 1] = row.description
      goto continue
    end

    if row.kind == "invalid" then
      return nil, "row " .. row.line_number .. ": invalid ID column; use `+` for new rows"
    end

    row.description_parts = { row.description }
    logical_rows[#logical_rows + 1] = row
    current_row = row

    ::continue::
  end

  for _, row in ipairs(logical_rows) do
    row.description = trim(table.concat(row.description_parts, " "))

    if row.kind == "new" then
      local new_row_error = validate_new_row(row, row.line_number)
      if new_row_error == "empty" then
        goto continue_row
      end

      if new_row_error then
        return nil, new_row_error
      end

      changes[#changes + 1] = {
        kind = "add",
        status = row.status,
        project = row.project,
        description = row.description,
      }

      goto continue_row
    end

    local task = tasks_by_id[row.id]
    if not task then
      return nil, "row " .. row.line_number .. ": unknown task ID `" .. row.id .. "`"
    end

    seen_ids[row.id] = true

    local existing_error = validate_existing_row(row, row.line_number)
    if existing_error then
      return nil, existing_error
    end

    local original_project = task.project ~= "" and task.project or nil
    local has_status_change = row.status ~= task.status
    local has_project_change = row.project ~= original_project
    local has_description_change = row.description ~= task.description

    if has_status_change and row.status == "done" then
      changes[#changes + 1] = {
        kind = "done",
        id = task.id,
        uuid = task.uuid,
      }

      if has_project_change or has_description_change then
        local arguments = {}

        if has_project_change then
          arguments[#arguments + 1] = "project:" .. (row.project or "")
        end

        if has_description_change then
          arguments[#arguments + 1] = "description:" .. row.description
        end

        changes[#changes + 1] = {
          kind = "modify",
          id = task.id,
          uuid = task.uuid,
          arguments = arguments,
        }
      end
    elseif has_status_change or has_project_change or has_description_change then
      local arguments = {}

      if has_status_change then
        arguments[#arguments + 1] = "status:" .. row.status
      end

      if has_project_change then
        arguments[#arguments + 1] = "project:" .. (row.project or "")
      end

      if has_description_change then
        arguments[#arguments + 1] = "description:" .. row.description
      end

      changes[#changes + 1] = {
        kind = "modify",
        id = task.id,
        uuid = task.uuid,
        arguments = arguments,
      }
    end

    ::continue_row::
  end

  for _, task in ipairs(snapshot.tasks) do
    if not seen_ids[tostring(task.id)] then
      changes[#changes + 1] = {
        kind = "delete",
        id = task.id,
        uuid = task.uuid,
      }
    end
  end

  return changes, nil
end

return M
