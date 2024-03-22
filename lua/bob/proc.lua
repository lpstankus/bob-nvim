---@class bob.Proc
---@field builder bob.Builder
---@field handle uv.uv_process_t
---@field stdout uv.uv_pipe_t
---@field stderr uv.uv_pipe_t

---@class bob.Proc
local Proc = {}
local M = { __index = Proc }

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

function Proc:cancel()
  self.cancelled = true
  local handle = self.handle
  if not handle or handle:is_closing() then return end

  handle:kill('sigint')
  vim.wait(1000, function() return (handle:is_closing()) end)
  if not handle:is_closing() then handle:kill('sigkill') end
end

function Proc:read_output()
  local builder_proc = self
  local publish_fn = function(diagnostics) builder_proc:publish(diagnostics) end
  local parser = self.builder:build_parser()

  vim.diagnostic.reset(self.builder._namespace)

  local cwd = self.builder.cwd
  local stream = self.builder.stream
  if stream == "stdout" then
    self.stdout:read_start(read_stream(cwd, parser, publish_fn))
  elseif stream == "stderr" then
    self.stderr:read_start(read_stream(cwd, parser, publish_fn))
  else
    error('invalid `stream` setting: ' .. stream .. 'for builder ' .. self.builder.name)
  end
end

function Proc:publish(diagnostics)
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
      vim.diagnostic.set(self.builder._namespace, bufnr, buf_diagnostics)
    end
  end

  self.stdout:shutdown()
  self.stdout:close()
  self.stderr:shutdown()
  self.stderr:close()
end

return M
