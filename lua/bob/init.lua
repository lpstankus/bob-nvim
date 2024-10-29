---@class Bob
local M = {}

---@type boolean
local initialized = false

---@type bob.Storage
local storage = require("bob.storage")

local linters = {}  ---@type table<string, bob.Linter>
local builders = {} ---@type table<string, bob.Builder>

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
  assert(initialized, "Bob: must initialize bob with `require('bob').setup()` before trying to lint")
  storage:replace_builder(vim.fn.getcwd(), cmd_name)
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

function M.build(opts)
  assert(initialized, "Bob: must initialize bob with `require('bob').setup()` before trying to build")

  local name = storage:retrieve_builder(vim.fn.getcwd())
  assert(name ~= "", "Bob: no builder set for workspace")
  local builder = builders[name]
  assert(builder, "Bob: builder with name `" .. name .. "` not available")

  local launch_params = {
    open_win = opts.open_win or true,
    force_new = opts.force_new or false,
  }

  builder:build(launch_params)
end

function M.kill_builder()
  assert(initialized, "Bob: must initialize bob with `require('bob').setup()` before trying to build")

  local name = storage:retrieve_builder(vim.fn.getcwd())
  assert(name ~= "", "Bob: no builder set for workspace")
  local builder = builders[name]
  assert(builder, "Bob: builder with name `" .. name .. "` not available")

  builder:kill()
end

function M.toggle_window()
  assert(initialized, "Bob: must initialize bob with `require('bob').setup()` before trying to build")

  local name = storage:retrieve_builder(vim.fn.getcwd())
  assert(name ~= "", "Bob: no builder set for workspace")
  local builder = builders[name]
  assert(builder, "Bob: builder with name `" .. name .. "` not available")

  builder:toggle_window()
end

return M
