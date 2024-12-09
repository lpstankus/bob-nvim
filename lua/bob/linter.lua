---@class bob.Linter
---@field name string              # defaults to command key in the commands table
---@field cmd string               # required, no default
---@field parser bob.Parser        # required, no default
---@field cwd string               # defaults to `vim.fn.getcwd()`
---@field stream "stdout"|"stderr" # defaults to `stdout`
--- private:
---@field _proc bob.LintProc?
---@field _namespace integer
local Linter = {}
local M = { __index = Linter }

function M.create_command(cmd)
  assert(cmd.cmd, "Bob: command `" .. cmd.name .. "` must provide field `cmd`:\n" .. vim.inspect(cmd))

  if not cmd.cwd then cmd.cwd = vim.fn.getcwd() end
  if not cmd.stream then cmd.stream = "stdout" end
  assert(cmd.stream == "stdout" or cmd.stream == "stderr", "Bob: command `" .. "` has unknown stream: `" .. cmd.stream .. "`")

  local parser = require("bob.parser").create_parser(cmd.parser)
  assert(parser, "Bob: linter must provide field `parser`:\n" .. vim.inspect(cmd))

  ---@type bob.Linter
  local linter = {
    name = cmd.name,
    cmd = cmd.cmd,
    parser = parser,
    cwd = cmd.cwd,
    stream = cmd.stream,
    _namespace = vim.api.nvim_create_namespace("bob.linter." .. cmd.name),
  }

  setmetatable(linter, M)

  return linter
end

local uv = vim.loop

---@return bob.LintProc?
function Linter:spawn_detached()
  local stdin  = assert(uv.new_pipe(false), "Bob: failed to create create new pipe")
  local stdout = assert(uv.new_pipe(false), "Bob: failed to create create new pipe")
  local stderr = assert(uv.new_pipe(false), "Bob: failed to create create new pipe")

  local cmds = vim.split(self.cmd, " ", {trimempty = true})

  local lintproc_opts = {
    args = require("bob.utils").slice(cmds, 2, nil),
    cwd = self.cwd,
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
        local lintproc = self._proc or {}
        if handle == lintproc.handle then self._proc = nil end
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
      linter = self,
      cancelled = false,
      handle = handle,
      stdout = stdout,
      stderr = stderr,
    }, require("bob.lintproc")
  )
  lintproc:read_output()

  return lintproc
end

function Linter:lint()
  if self._proc then self._proc:cancel() end
  self._proc = nil

  local ok, maybe_lintproc = pcall(self.spawn_detached, self)
  if not ok then
    vim.notify("Bob: failed to spawn " .. self.name .. ": " .. maybe_lintproc, vim.log.levels.WARN)
    return
  end

  self._proc = maybe_lintproc
end

return M
