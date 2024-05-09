---@class bob.LintProc
---@field command bob.Command
---@field handle  uv.uv_process_t
---@field stdout  uv.uv_pipe_t
---@field stderr  uv.uv_pipe_t
local LintProc = {}
local M = { __index = LintProc }

local function read_stream(cwd, parser, publish_fn)
  return function(err, chunk)
    assert(not err, err)
    if chunk then
      parser.on_chunk(chunk)
    else
      parser.on_done(publish_fn, cwd)
    end
  end
end

function LintProc:cancel()
  self.cancelled = true
  local handle = self.handle
  if not handle or handle:is_closing() then return end

  handle:kill('sigint')
  vim.wait(1000, function() return (handle:is_closing()) end)
  if not handle:is_closing() then handle:kill('sigkill') end
end

function LintProc:read_output()
  local publish_fn = function(diagnostics)
    vim.diagnostic.reset(self.command.namespace)

    if not self.cancelled then
      local to_publish = {}
      for _, diagnostic in ipairs(diagnostics) do
        local bufnr = vim.fn.bufnr(diagnostic.file)

        if bufnr <= 0 then
          vim.cmd("bad " .. diagnostic.file)
          bufnr = vim.fn.bufnr(diagnostic.file)
        end

        if bufnr > 0 then
          if not to_publish[bufnr] then to_publish[bufnr] = {} end
          table.insert(to_publish[bufnr], diagnostic)
        end
      end

      for bufnr, buf_diagnostics in pairs(to_publish) do
        vim.diagnostic.set(self.command.namespace, bufnr, buf_diagnostics)
      end
    end

    self.stdout:shutdown()
    self.stdout:close()
    self.stderr:shutdown()
    self.stderr:close()
  end

  local parser = self.command:create_parser()
  local stream = self.command.stream
  if stream == "stdout" then
    self.stdout:read_start(read_stream(self.command.cwd, parser, publish_fn))
  elseif stream == "stderr" then
    self.stderr:read_start(read_stream(self.command.cwd, parser, publish_fn))
  else
    error('Bob: invalid `stream` setting: ' .. stream .. 'for command ' .. self.command.name)
  end
end

return M
