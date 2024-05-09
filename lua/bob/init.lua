local uv = vim.loop
local bob_group = vim.api.nvim_create_augroup("Bob", {})

---@param tbl   table
---@param first integer?
---@param last  integer?
local function slice(tbl, first, last)
  local sliced = {}
  for i = first or 1, last or #tbl, 1 do sliced[#sliced+1] = tbl[i] end
  return sliced
end

---@class Bob
local M = {}

---@type boolean
local initialized = false

---@type bob.Storage
local storage = require("bob.storage")

local linters = {}  ---@type table<string, bob.Command>
local builders = {} ---@type table<string, bob.Command>

local running_lintprocs = {} ---@type bob.LintProc[]
local builder_buf = nil

---@param commands table<"builders"|"linters", table<string, bob.Command>>
function M.setup(commands)
  assert(vim.diagnostic, "Bob: neovim 0.6.0+ is required")

  linters = {}
  for name, linter in pairs(commands.linters) do
    if not linter.name then linter.name = name end
    linters[name] = require("bob.command").create_command(linter, "linter")
  end

  builders = {}
  for name, builder in pairs(commands.builders) do
    if not builder.name then builder.name = name end
    builders[name] = require("bob.command").create_command(builder, "builder")
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
function M.set_linter(cmd_names)
  assert(initialized, "Bob: must initialize bob with `require('bob').setup()` before trying to lint")
  storage:replace_linters(vim.fn.getcwd(), cmd_names)
  storage:save()
end

---@param cmd_name string
function M.set_builder(cmd_name)
  assert(initialized, "Bob: must initialize bob with `require('bob').setup()` before trying to lint")
  storage:replace_builder(vim.fn.getcwd(), cmd_name)
  storage:save()
end

---@param command bob.Command
---@return bob.LintProc?
local function spawn_detached(command)
  local stdin  = assert(uv.new_pipe(false), "Bob: failed to create create new pipe")
  local stdout = assert(uv.new_pipe(false), "Bob: failed to create create new pipe")
  local stderr = assert(uv.new_pipe(false), "Bob: failed to create create new pipe")

  local cmds = vim.split(command.cmd, " ", {trimempty = true})

  local lintproc_opts = {
    args = slice(cmds, 2, nil),
    cwd = command.cwd,
    detached = true,
    stdio = { stdin, stdout, stderr },
  }

  local handle
  local pid_or_err

  handle, pid_or_err = uv.spawn(
    cmds[1],
    lintproc_opts,
    function()
      if handle and not handle:is_closing() then
        local lintproc = running_lintprocs[command.name] or {}
        if handle == lintproc.handle then running_lintprocs[command.name] = nil end
        handle:close()
      end
    end
  )

  if not handle then
    stdout:close()
    stderr:close()
    stdin:close()
    vim.notify("Bob: error running " .. cmds[1] .. ": " .. pid_or_err, vim.log.levels.ERROR)
    return nil
  end

  local lintproc = setmetatable({
      command = command,
      cancelled = false,
      handle = handle,
      stdout = stdout,
      stderr = stderr,
    }, require("bob.lintproc")
  )
  lintproc:read_output()

  return lintproc
end

function M.lint()
  assert(initialized, "Bob: must initialize bob with `require('bob').setup()` before trying to lint")

  local linter_names = storage:retrieve_linters(vim.fn.getcwd())

  for _, name in pairs(linter_names) do
    local linter = linters[name]
    assert(linter, "Bob: linter with name `" .. name .. "` not available")

    local lintproc = running_lintprocs[linter.name]
    if lintproc then lintproc:cancel() end

    running_lintprocs[linter.name] = nil
    local ok, maybe_lintproc = pcall(spawn_detached, linter)
    if ok then
      running_lintprocs[linter.name] = maybe_lintproc
    else
      vim.notify("Bob: failed to spawn " .. linter.name, vim.log.levels.WARN)
    end
  end
end

function M.build()
  assert(initialized, "Bob: must initialize bob with `require('bob').setup()` before trying to build")

  local name = storage:retrieve_builder(vim.fn.getcwd())
  local builder = builders[name]
  assert(builder, "Bob: builder with name `" .. name .. "` not available")

  if builder_buf then vim.cmd("bdelete! " .. builder_buf) end

  builder_buf = vim.api.nvim_create_buf(true, true)
  if builder_buf == 0 then
    vim.notify("Bob: failed to spawn new buffer")
    return
  end

  if builder.builderViz == "split" then
    vim.cmd("split")
    local win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, builder_buf)
    vim.cmd("wincmd J")
    vim.api.nvim_win_set_height(win, 20)
    vim.cmd("terminal " .. builder.cmd)
    vim.cmd('startinsert')
  elseif builder.builderViz == "background" then
    local win = vim.api.nvim_get_current_win()
    local cur_buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_win_set_buf(win, builder_buf)
    vim.cmd("terminal " .. builder.cmd)
    vim.api.nvim_win_set_buf(win, cur_buf)
  else
    vim.notify("Bob: invalid builderViz setting: " .. builder.builderViz)
  end

  vim.api.nvim_create_autocmd(
    { "TermClose" },
    {
      group = bob_group, buffer = builder_buf,
      callback = function(_)
        -- TODO: read output of terminal, publish diagnostics if there are any...
      end
    }
  )

end

return M
