local uv = vim.loop
local M = {}

---@type boolean
M.initialized = false

---@type table<string, bob.Builder>
M.builders = {}

---@type table<string, string[]>
M.builder_by_ft = {}

---@type bob.Proc[]
local running_procs = {}

---@class bob.Config
---@field builders table<string, bob.Builder>
---@field builder_by_ft table<string, string[]>

---@param cfg bob.Config
function M.setup(cfg)
  assert(vim.diagnostic, "bob-nvim requires neovim 0.6.0+")
  M.builders = {}
  for name, builder in pairs(cfg.builders) do
    assert(builder.cmd, "builder `" .. name .. "` must provide field `cmd`:\n" .. vim.inspect(builder))
    assert(builder.parser, "builder `" .. name .. "` must provide field `parser`:\n" .. vim.inspect(builder))
    assert(builder.parser.pattern, "builder `" .. name .. "` must provide field `parser.pattern`:\n" .. vim.inspect(builder))
    assert(builder.parser.groups, "builder `" .. name .. "` must provide field `parser.groups`:\n" .. vim.inspect(builder))
    assert(builder.parser.error_map, "builder `" .. name .. "` must provide field `parser.error_map`:\n" .. vim.inspect(builder))

    builder.name = name
    if not builder.cwd then builder.cwd = vim.fn.getcwd() end
    if not builder.stream then builder.stream = "stdout" end
    builder._namespace = vim.api.nvim_create_namespace("bob." .. builder.name)

    M.builders[name] = setmetatable(builder, require("bob.builder"))
  end
  M.builder_by_ft = cfg.builder_by_ft
  M.initialized = true
end

---@class bob.BuildOptions
---@field publish_method "diagnostic"|"quickfix"
---@field force_open boolean

function M.build()
  assert(M.initialized, "must setup bob-nvim before trying to build stuff")

  local ft = vim.bo.filetype
  local names = M.builder_by_ft[ft]

  if not names then
    local dedup_builders = {}
    local filetypes = vim.split(ft, ".", { plain = true })
    for _, nft in pairs(filetypes) do
      local builders = M.builder_by_ft[nft]
      if builders then
        for _, builder in ipairs(builders) do
          dedup_builders[builder] = true
        end
      end
    end
    names = vim.tbl_keys(dedup_builders) ---@as string[]
  end

  for _, name in pairs(names) do
    local builder = M.builders[name]
    assert(builder, "builder with name '" .. name .. "' not available")

    local proc = running_procs[builder.name]
    if proc then proc:cancel() end

    running_procs[builder.name] = nil
    local build_proc = M.spawn_builder(builder)
    if build_proc then
      running_procs[builder.name] = build_proc
    else
      vim.notify("failed to spawn " .. builder.name, vim.log.levels.WARN)
    end
  end
end

---@param tbl table
---@param first integer?
---@param last integer?
function table.slice(tbl, first, last)
  local sliced = {}
  for i = first or 1, last or #tbl, 1 do sliced[#sliced+1] = tbl[i] end
  return sliced
end

---@param builder bob.Builder
---@return bob.Proc?
function M.spawn_builder(builder)
  assert(builder, "lint must be called with a builder")

  local stdin = assert(uv.new_pipe(false), "Must be able to create pipe")
  local stdout = assert(uv.new_pipe(false), "Must be able to create pipe")
  local stderr = assert(uv.new_pipe(false), "Must be able to create pipe")

  local cmds = vim.split(builder.cmd, " ", {trimempty = true})

  local proc_opts = {
    args = table.slice(cmds, 2, nil),
    cwd = builder.cwd,
    detached = true,
    stdio = { stdin, stdout, stderr },
  }

  local handle
  local pid_or_err

  handle, pid_or_err = uv.spawn(
    cmds[1],
    proc_opts,
    function(code)
      if handle and not handle:is_closing() then
        local proc = running_procs[builder.name] or {}
        if handle == proc.handle then running_procs[builder.name] = nil end
        handle:close()
      end
      if code ~= 0 then
        vim.schedule(function()
          vim.notify("builder command '" .. cmds[1] .. "' exited with code: " .. code, vim.log.levels.INFO)
        end)
      end
    end
  )

  if not handle then
    stdout:close()
    stderr:close()
    stdin:close()
    vim.notify("error running " .. cmds[1] .. ": " .. pid_or_err, vim.log.levels.ERROR)
    return nil
  end

  local proc = setmetatable({
      builder = builder,
      cancelled = false,
      handle = handle,
      stdout = stdout,
      stderr = stderr,
    }, require("bob.proc")
  )
  proc:read_output()

  return proc
end

return M
