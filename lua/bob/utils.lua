local M = {}

---@param tbl   table
---@param first integer?
---@param last  integer?
function M.slice(tbl, first, last)
  local sliced = {}
  for i = first or 1, last or #tbl, 1 do sliced[#sliced+1] = tbl[i] end
  return sliced
end

return M
