---@class Bob
local M = {}

---@type boolean
local initialized = false

---@type bob.Storage
local storage = require("bob.storage")

local linters = {}  ---@type table<string, bob.Linter>
local builders = {} ---@type table<string, bob.Builder>

local temp_builder = nil ---@type string | nil

function M.setup(commands)
  assert(vim.diagnostic, "Bob: neovim 0.6.0+ is required")

  linters = {}
  for name, linter in pairs(commands.linters) do
    if not linter.name then linter.name = name end
    linters[name] = require("bob.linter").create_command(linter)
  end

  builders = {}
  for name, builder in pairs(commands.builders) do
    if not builder.name then builder.name = name end
    builders[name] = require("bob.builder").create_builder(builder)
  end

  storage:load()

  initialized = true
end

---@param cmd_name string
function M.add_linter(cmd_name)
  assert(initialized, "Bob: must initialize bob with `require('bob').setup()` before trying to lint")
  storage:append_linter(vim.fn.getcwd(), cmd_name)
  storage:save()
end

---@param cmd_names string[]
function M.set_linters(cmd_names)
  assert(initialized, "Bob: must initialize bob with `require('bob').setup()` before trying to lint")
  if type(cmd_names) == "string" then cmd_names = { cmd_names } end
  storage:replace_linters(vim.fn.getcwd(), cmd_names)
  storage:save()
end

---@param cmd_name string
function M.set_builder(cmd_name)
  assert(initialized, "Bob: must initialize bob with `require('bob').setup()` before trying to set the builder")
  storage:replace_builder(vim.fn.getcwd(), cmd_name)
  storage:save()
end

---@param cmd_string string
---@param temp boolean
function M.set_builder_cmd(cmd_string, temp)
  assert(initialized, "Bob: must initialize bob with `require('bob').setup()` before trying to override the builder command")
  if temp then
    temp_builder = cmd_string
    return
  end
  storage:replace_builder_cmd(vim.fn.getcwd(), cmd_string)
  storage:save()
end

function M.reset_builder_cmd()
  assert(initialized, "Bob: must initialize bob with `require('bob').setup()` before trying to override the builder command")
  if temp_builder then
    temp_builder = nil
    return
  end
  storage:reset_builder_cmd(vim.fn.getcwd())
  storage:save()
end

function M.lint()
  assert(initialized, "Bob: must initialize bob with `require('bob').setup()` before trying to lint")

  local linter_names = storage:retrieve_linters(vim.fn.getcwd())
  for _, name in pairs(linter_names) do
    local linter = linters[name]
    assert(linter, "Bob: linter with name `" .. name .. "` not available")

    linter:lint()
  end
end

local function get_builder()
  local stor = storage:retrieve_builder(vim.fn.getcwd())
  assert(stor.name ~= "", "Bob: no builder set for workspace")

  local builder = require("bob.utils").deepCopy(builders[stor.name])
  assert(builder, "Bob: builder with name `" .. stor.name .. "` not available")

  if stor.cmd then
    builder.cmd = stor.cmd
  end

  if temp_builder ~= nil then
    builder.cmd = temp_builder
  end

  return builder
end

function M.build(opts)
  assert(initialized, "Bob: must initialize bob with `require('bob').setup()` before trying to build")
  local builder = get_builder()
  local launch_params = {
    open_win = opts.open_win or true,
    force_new = opts.force_new or false,
  }
  builder:build(launch_params)
end

function M.kill_builder()
  assert(initialized, "Bob: must initialize bob with `require('bob').setup()` before trying to build")
  local builder = get_builder()
  builder:kill()
end

function M.toggle_window()
  assert(initialized, "Bob: must initialize bob with `require('bob').setup()` before trying to build")
  local builder = get_builder()
  builder:toggle_window()
end

return M
