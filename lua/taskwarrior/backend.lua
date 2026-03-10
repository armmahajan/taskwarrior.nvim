local M = {}

local function system(args, callback)
  vim.system(args, { text = true }, function(result)
    vim.schedule(function()
      callback(result)
    end)
  end)
end

function M.is_available()
  return vim.fn.executable("task") == 1
end

function M.fetch_tasks(filters, callback)
  if not M.is_available() then
    callback(nil, "`task` executable not found in PATH")
    return
  end

  local args = { "task", "rc.confirmation=no" }
  vim.list_extend(args, filters or {})
  args[#args + 1] = "export"

  system(args, function(result)
    if result.code ~= 0 then
      local stderr = vim.trim(result.stderr or "")
      callback(nil, stderr ~= "" and stderr or "failed to fetch tasks from Taskwarrior")
      return
    end

    local ok, decoded = pcall(vim.json.decode, result.stdout or "[]")
    if not ok then
      callback(nil, "failed to decode Taskwarrior JSON output")
      return
    end

    table.sort(decoded, function(left, right)
      local left_id = left.id or math.huge
      local right_id = right.id or math.huge
      return left_id < right_id
    end)

    local tasks = {}
    for _, task in ipairs(decoded) do
      if task.status == "pending" or task.status == "waiting" then
        tasks[#tasks + 1] = {
          id = task.id,
          uuid = task.uuid,
          status = task.status,
          project = task.project,
          description = task.description or "",
        }
      end
    end

    callback(tasks, nil)
  end)
end

function M.apply_changes(changes, callback)
  if #changes == 0 then
    callback(nil)
    return
  end

  local index = 1

  local function step()
    local change = changes[index]
    if not change then
      callback(nil)
      return
    end

    local args
    if change.kind == "done" then
      args = { "task", "rc.confirmation=no", change.uuid, "done" }
    elseif change.kind == "delete" then
      args = { "task", "rc.confirmation=no", change.uuid, "delete" }
    elseif change.kind == "add" then
      args = { "task", "rc.confirmation=no", "add", change.description }
      if change.project then
        args[#args + 1] = "project:" .. change.project
      end
    elseif change.kind == "modify" then
      args = { "task", "rc.confirmation=no", change.uuid, "modify" }
      vim.list_extend(args, change.arguments)
    else
      callback("unsupported change kind: " .. tostring(change.kind))
      return
    end

    system(args, function(result)
      if result.code ~= 0 then
        local stderr = vim.trim(result.stderr or "")
        local stdout = vim.trim(result.stdout or "")
        local detail = stderr ~= "" and stderr or stdout
        callback(detail ~= "" and detail or ("Taskwarrior command failed for task " .. tostring(change.id)))
        return
      end

      index = index + 1
      step()
    end)
  end

  step()
end

return M
