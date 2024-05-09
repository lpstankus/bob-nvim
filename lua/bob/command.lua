---@class bob.Command
---@field cmd string               # required, no default
---@field parser bob.ParserOpts    # required, no default
---@field name string              # defaults to command key in the commands table
---@field cwd string               # defaults to `vim.fn.getcwd()`
---@field stream "stdout"|"stderr" # defaults to `stdout`
---@field builderViz nil|"background"|"split" # defaults to `split` for builders and nil for linters
---@field namespace integer # private...
local Command = {}
local M = { __index = Command }

---@class bob.Parser
---@field on_chunk fun(chunk: string)
---@field on_done fun(publish: fun(diagnostics: vim.Diagnostic[]), linter_cwd: string)
---@class bob.ParserOpts
---@field pattern string
---@field groups string[]
---@field error_map table<string, integer>

---@return bob.Parser
function Command:create_parser()
  local opts = self.parser

  local parse_fn = function(output)
    local result = {}
    for _, line in ipairs(vim.fn.split(output or "", '\n')) do
      local diagnostic = vim.diagnostic.match(line, opts.pattern, opts.groups, opts.error_map)
      if diagnostic then
        table.insert(result, diagnostic)
      end
    end
    return result
  end

  local parser = {}
  parser.chunks = {}
  parser.on_chunk = function(chunk) table.insert(parser.chunks, chunk) end
  parser.on_done = function(publish_fn)
    vim.schedule(function()
      vim.notify(vim.inspect(parser.chunks))
      local output = table.concat(parser.chunks)
      local diagnostics = parse_fn(output)
      publish_fn(diagnostics)
    end)
  end

  return parser --[[@as bob.Parser]]
end

---@param cmd bob.Command
---@param type "builder"|"linter"
function M.create_command(cmd, type)
  -- luacheck: ignore 631
  assert(cmd.cmd,              "Bob: command `" .. cmd.name .. "` must provide field `cmd`:\n"              .. vim.inspect(cmd))
  assert(cmd.parser,           "Bob: command `" .. cmd.name .. "` must provide field `parser`:\n"           .. vim.inspect(cmd))
  assert(cmd.parser.pattern,   "Bob: command `" .. cmd.name .. "` must provide field `parser.pattern`:\n"   .. vim.inspect(cmd))
  assert(cmd.parser.error_map, "Bob: command `" .. cmd.name .. "` must provide field `parser.error_map`:\n" .. vim.inspect(cmd))
  assert(cmd.parser.groups,    "Bob: command `" .. cmd.name .. "` must provide field `parser.groups`:\n"    .. vim.inspect(cmd))

  if not cmd.stream then cmd.stream = "stdout" end
  if not cmd.cwd then cmd.cwd = vim.fn.getcwd() end
  if type == "builder" and not cmd.builderViz then cmd.builderViz = "split" end
  cmd.namespace = vim.api.nvim_create_namespace("bob." .. type .. "." .. cmd.name)

  return setmetatable(cmd, require("bob.command"))
end

return M
