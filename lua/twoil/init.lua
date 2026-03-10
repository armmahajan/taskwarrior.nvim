local M = {}

function M.open(filters)
  require("twoil.buffer")
  require("twoil.buffer").open(filters or {})
end

require("twoil.buffer")

return M
