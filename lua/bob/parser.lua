---@class bob.Parser
---@field parse    fun(input: string): vim.Diagnostic[]
---@field on_chunk fun(chunk: string)
---@field on_done  fun(publish: fun(diagnostics: vim.Diagnostic[]), linter_cwd: string)

local M = {}

---@return bob.Parser | nil
function M.create_parser(opts)
  if not opts then
    return nil
  end

  -- luacheck: ignore 631
  assert(opts.pattern,   "Bob: parser must provide field `parser.pattern`:\n"   .. vim.inspect(opts))
  assert(opts.error_map, "Bob: parser must provide field `parser.error_map`:\n" .. vim.inspect(opts))
  assert(opts.groups,    "Bob: parser must provide field `parser.groups`:\n"    .. vim.inspect(opts))

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

  parser.on_chunk = function(chunk)
    table.insert(parser.chunks, chunk)
  end

  parser.on_done = function(publish_fn)
    vim.schedule(function()
      local output = table.concat(parser.chunks)
      local diagnostics = parse_fn(output)
      publish_fn(diagnostics)
      parser.chunks = {}
    end)
  end

  parser.parse = function(str)
    return parse_fn(str)
  end

  return parser --[[@as bob.Parser]]
end

return M
