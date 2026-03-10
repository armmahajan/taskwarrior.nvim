local M = {}

function M.open(filters)
  require("taskwarrior.buffer")
  require("taskwarrior.buffer").open(filters or {})
end

require("taskwarrior.buffer")

return M
