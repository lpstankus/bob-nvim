---@class bob.Builder
---@field name string        # defaults to command key in the commands table
---@field cmd string         # required, no default
---@field parser bob.Parser? # defaults to nil
---@field namespace integer  # private...
local Builder = {}
local M = { __index = Builder }

local bob_group

local builder_buf = nil
local builder_win = nil
local builder_alive = false

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

function Builder:build(opts)
  if opts.force_new then self:kill() end

  if builder_alive then
    self:toggle_window()
    return
  end

  builder_buf = vim.api.nvim_create_buf(true, true)
  if builder_buf == 0 then
    builder_buf = nil
    vim.notify("Bob: failed to spawn new buffer")
    return
  end

  self:toggle_window()
  vim.api.nvim_feedkeys("G", "n", false)
  vim.cmd("terminal " .. self.cmd)

  builder_alive = true
  if not opts.open_win then self:toggle_window() end
  vim.notify("Bob: spawned builder `" .. self.name .. "`")

  -- create/clear augroup
  bob_group = vim.api.nvim_create_augroup("__InternalBobGroup", { clear = true })

  vim.api.nvim_create_autocmd(
    { "TermEnter" },
    {
      group = bob_group,
      buffer = builder_buf,
      callback = function(_) vim.cmd("stopinsert") end
    }
  )

  vim.api.nvim_create_autocmd(
    { "TextChanged" },
    {
      group = bob_group,
      buffer = builder_buf,
      callback = function()
        if not builder_alive or not builder_win or not builder_buf then return end

        local cursor_row = vim.api.nvim_win_get_cursor(builder_win)[1]
        local line_count = vim.api.nvim_buf_line_count(builder_buf)

        local not_in_win = builder_win ~= vim.api.nvim_get_current_win()
        local cursor_near_bottom = line_count - cursor_row <= 5

        if not_in_win or cursor_near_bottom then vim.api.nvim_feedkeys("G", "n", false) end
      end
    }
  )

  vim.api.nvim_create_autocmd(
    { "BufDelete", "QuitPre" },
    {
      group = bob_group,
      buffer = builder_buf,
      callback = function(_)
        -- TODO: read output of terminal, publish diagnostics if there are any...

        self:kill()
        vim.notify("Bob: finished execution of `" .. self.name .. "`")

        builder_buf = nil
        builder_win = nil
      end
    }
  )
end

function Builder:kill()
  if builder_alive then
    builder_alive = false
    if builder_win then
      vim.api.nvim_win_close(builder_win, false)
      builder_win = nil
    end
    if builder_buf then
      vim.cmd("bdelete! " .. builder_buf)
      builder_buf = nil
    end
  end
end

function Builder:toggle_window()
  if not builder_buf then
    vim.notify("Bob: no builder process to show")
    return
  end

  if builder_win and vim.api.nvim_win_is_valid(builder_win) then
    vim.api.nvim_win_close(builder_win, false)
    builder_win = nil
    return
  end

  local tot_width  = vim.o.columns - 2
  local tot_height = vim.o.lines - 4

  local fraction = 0.8
  local win_width  = math.floor(tot_width * fraction)
  local win_height = math.floor(tot_height * fraction)

  local off_width = math.floor((tot_width - win_width) / 2)
  local off_height = math.floor((tot_height - win_height) / 2) + 1

  builder_win = vim.api.nvim_open_win(
    builder_buf,
    true,
    {
      title = { { "┤ bob: " .. self.name .. " ├", "Normal" } },
      relative = 'editor', border = "single", style = "minimal",
      width = win_width, height = win_height, col = off_width, row = off_height,
    }
  )
end

return M
