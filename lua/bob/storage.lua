---@class bob.StorageBuilder
---@field name string
---@class bob.StorageCmds
---@field linters string[]
---@field builder bob.StorageBuilder

---@alias bob.StorageWorkspaces table<string, bob.StorageCmds>

---@class bob.StorageData
---@field version    string
---@field workspaces bob.StorageWorkspaces

---@class bob.Storage
---@field ok         boolean
---@field version    string
---@field workspaces bob.StorageWorkspaces
local Storage = {}

-- NOTE: Not a definite versioning definition, just a constant to identify old registries
local version = "0.1.0"

local Path = require("plenary.path")
local storage_path = vim.fn.stdpath("data") .. "/bob.json"

local function write_data(data)
  Path:new(storage_path):write(vim.json.encode(data), "w")
end

---@return bob.StorageData
local function clean_data()
  local path = Path:new(storage_path)
  local blank_data = { version = version, workspaces =  {} } ---@type bob.StorageData
  write_data(blank_data)
  local out_data = path:read()
  return vim.json.decode(out_data)
end

---@return bob.StorageData
local function read_data()
  local path = Path:new(storage_path)
  local exists = path:exists()

  if not exists then
    return clean_data()
  end

  local out_data = path:read()
  if not out_data or out_data == "" then
    return clean_data()
  end

  return vim.json.decode(out_data)
end

---@param path string
function Storage:touch_path(path)
  if not self.workspaces then
    self.workspaces = {}
  end
  if not self.workspaces[path] then
    self.workspaces[path] = { builder = { name = "" }, linters = {} }
  end
end

function Storage:load()
  local ok, data = pcall(read_data)
  if not ok or (version and version ~= data.version) then
    ok, data = pcall(clean_data)
  end
  self.ok = ok
  self.version = version
  self.workspaces = data.workspaces
end

function Storage:save()
  local ok, stored_data = pcall(read_data)
  assert(ok, "Bob: unable to save storage, error reading storage file")
  for k, v in pairs(self.workspaces) do stored_data.workspaces[k] = v end
  assert(pcall(write_data, stored_data), "Bob: failed to write storage to file")
end

---@param path string
---@return bob.StorageBuilder
function Storage:retrieve_builder(path)
  assert(self.ok, "Bob: cannot retrieve builder, storage failed to load correctly")
  self:touch_path(path)
  return self.workspaces[path].builder
end

---@param path string
---@return string[]
function Storage:retrieve_linters(path)
  assert(self.ok, "Bob: cannot retrieve linters, storage failed to load correctly")
  self:touch_path(path)
  return self.workspaces[path].linters
end

---@param path string
---@param name string
function Storage:replace_builder(path, name)
  assert(self.ok, "Bob: cannot replace builder, storage failed to load correctly")
  self:touch_path(path)
  self.workspaces[path].builder.name = name
end

---@param path string
---@param cmd  string[]
function Storage:replace_linters(path, cmd)
  assert(self.ok, "Bob: cannot replace linters, storage failed to load correctly")
  self:touch_path(path)
  self.workspaces[path].linters = cmd
end

---@param path string
---@param name string
function Storage:append_linter(path, name)
  assert(self.ok, "Bob: cannot insert linter, storage failed to load correctly")
  self:touch_path(path)
  table.insert(self.workspaces[path].linters, name)
end

return Storage
