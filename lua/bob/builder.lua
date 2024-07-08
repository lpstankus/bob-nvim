---@class bob.Builder
---@field name string        # defaults to command key in the commands table
---@field cmd string         # required, no default
---@field parser bob.Parser? # defaults to nil
---@field namespace integer  # private...
local Builder = {}
local M = { __index = Builder }

local bob_group = vim.api.nvim_create_augroup("Bob", {})

local builder_buf = nil
local builder_win = nil
local builder_blockinput = false

---@return bob.Builder
function M.create_builder(opts)
  assert(opts.cmd, "Bob: command `" .. opts.name .. "` must provide field `cmd`:\n" .. vim.inspect(opts))

  ---@type bob.Builder
  local builder = {
    name = opts.name,
    cmd = opts.cmd,
    parser = nil, -- TODO: create parser to fetch diagnostics from terminal output
    namespace = vim.api.nvim_create_namespace("bob.builder." .. opts.name),
  }
  setmetatable(builder, M)

  return builder
end

---@param open_win boolean
function Builder:build(open_win)
  if builder_buf then vim.cmd("bdelete! " .. builder_buf) end

  builder_buf = vim.api.nvim_create_buf(true, true)
  if builder_buf == 0 then
    builder_buf = nil
    vim.notify("Bob: failed to spawn new buffer")
    return
  end

  vim.cmd("split")
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, builder_buf)
  vim.cmd("terminal " .. self.cmd)
  vim.cmd("q")

  builder_blockinput = true

  vim.notify("Bob: spawned builder `" .. self.name .. "`")
  if open_win then self:toggle_window() end

  vim.api.nvim_create_autocmd(
    { "TermEnter" },
    {
      group = bob_group,
      buffer = builder_buf,
      callback = function(_)
        if builder_blockinput then vim.cmd("stopinsert") end
      end
    }
  )

  vim.api.nvim_create_autocmd(
    { "TermClose" },
    {
      group = bob_group,
      buffer = builder_buf,
      callback = function(_)
        builder_blockinput = false
        vim.notify("Bob: finished execution of `" .. self.name .. "`")
      end
    }
  )

  vim.api.nvim_create_autocmd(
    { "TermLeave" },
    {
      group = bob_group,
      buffer = builder_buf,
      callback = function(_)
        -- TODO: read output of terminal, publish diagnostics if there are any...
        builder_buf = nil
        builder_win = nil
      end
    }
  )
end

function Builder:toggle_window()
  if not builder_buf then
    vim.notify("Bob: no builder process to show")
    return
  end

  if builder_win then
    vim.api.nvim_win_close(builder_win, false)
    builder_win = nil
    return
  end

  local tot_width  = vim.o.columns
  local tot_height = vim.o.lines

  local fraction = 0.8
  local win_width  = math.floor(tot_width * fraction)
  local win_height = math.floor(tot_height * fraction)

  local off_width = math.floor((tot_width - win_width) / 2)
  local off_height = math.floor((tot_height - win_height) / 2)

  builder_win = vim.api.nvim_open_win(
    builder_buf,
    true,
    {
      relative = 'win', border = "single", style = "minimal",
      width = win_width, height = win_height, col = off_width, row = off_height,
    }
  )
end

return M
