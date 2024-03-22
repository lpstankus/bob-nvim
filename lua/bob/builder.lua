---@class bob.Builder
---@field cmd string               # required, no default
---@field parser bob.ParserOpts    # required, no default
---@field name string              # defaults to builder key
---@field cwd string               # defaults to `vim.fn.getcwd()`
---@field stream "stdout"|"stderr" # defaults to `stdout`
---@field _namespace integer       # private...

---@class bob.Builder
local Builder = {}
local M = { __index = Builder }

---@class bob.Parser
---@field on_chunk fun(chunk: string)
---@field on_done fun(publish: fun(diagnostics: vim.Diagnostic[]), linter_cwd: string)

---@class bob.ParserOpts
---@field pattern string
---@field groups string[]
---@field error_map table<string, integer>

---@return bob.Parser
function Builder:build_parser()
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
      local output = table.concat(parser.chunks)
      local diagnostics = parse_fn(output)
      publish_fn(diagnostics)
    end)
  end

  return parser --[[@as bob.Parser]]
end

return M
