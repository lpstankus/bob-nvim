local M = {}

---@param tbl   table
---@param first integer?
---@param last  integer?
function M.slice(tbl, first, last)
  local sliced = {}
  for i = first or 1, last or #tbl, 1 do sliced[#sliced+1] = tbl[i] end
  return sliced
end

-- from: https://gist.github.com/tylerneylon/81333721109155b2d244#file-copy-lua-L30
function M.deepCopy(tbl, seen)
  -- Handle non-tables and previously-seen tables.
    if type(tbl) ~= 'table' then return tbl end
    if seen and seen[tbl] then return seen[tbl] end

    -- New table; mark it as seen and copy recursively.
    local s = seen or {}
    local res = {}
    s[tbl] = res
    for k, v in pairs(tbl) do res[M.deepCopy(k, s)] = M.deepCopy(v, s) end
    return setmetatable(res, getmetatable(tbl))
end

return M
