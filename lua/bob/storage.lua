---@alias bob.CmdsMap table<string, table<"builder"|"linters", any>>

---@class bob.Storage
---@field ok           boolean
---@field cmds_by_path bob.CmdsMap
local Storage = {}

local Path = require("plenary.path")
local storage_path = vim.fn.stdpath("data") .. "/bob.json"

local function write_data(data)
  Path:new(storage_path):write(vim.json.encode(data), "w")
end

---@return bob.CmdsMap
local function read_data()
  local path = Path:new(storage_path)
  local exists = path:exists()

  if not exists then write_data({}) end

  local out_data = path:read()
  if not out_data or out_data == "" then
    write_data({})
    out_data = path:read()
  end

  return vim.json.decode(out_data)
end

---@param path string
function Storage:touch_path(path)
  if not self.cmds_by_path then self.cmds_by_path = {} end
  if not self.cmds_by_path[path] then self.cmds_by_path[path] = { builder = "", linters = {} } end
end

function Storage:load()
  local ok, data = pcall(read_data)
  self.ok = ok
  self.cmds_by_path = data
end

function Storage:save()
  local ok, stored_data = pcall(read_data)
  assert(ok, "Bob: unable to save storage, error reading storage file")
  for k, v in pairs(self.cmds_by_path) do stored_data[k] = v end
  assert(pcall(write_data, stored_data), "Bob: failed to write storage to file")
end

---@param path string
---@return string
function Storage:retrieve_builder(path)
  assert(self.ok, "Bob: cannot retrieve builder, storage failed to load correctly")
  self:touch_path(path)
  return self.cmds_by_path[path].builder
end

---@param path string
---@return string[]
function Storage:retrieve_linters(path)
  assert(self.ok, "Bob: cannot retrieve linters, storage failed to load correctly")
  self:touch_path(path)
  return self.cmds_by_path[path].linters
end

---@param path string
---@param cmd  string
function Storage:replace_builder(path, cmd)
  assert(self.ok, "Bob: cannot replace builder, storage failed to load correctly")
  self:touch_path(path)
  self.cmds_by_path[path].builder = cmd
end

---@param path string
---@param cmd  string[]
function Storage:replace_linters(path, cmd)
  assert(self.ok, "Bob: cannot replace linters, storage failed to load correctly")
  self:touch_path(path)
  self.cmds_by_path[path].linters = cmd
end

---@param path string
---@param cmd  string
function Storage:append_linter(path, cmd)
  assert(self.ok, "Bob: cannot insert linter, storage failed to load correctly")
  self:touch_path(path)
  table.insert(self.cmds_by_path[path].linters, cmd)
end

return Storage
