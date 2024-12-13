---@class bob.Builder
---@field name                string      # defaults to command key in the commands table
---@field cmd                 string      # required, no default
---@field move_focus          boolean?    # defaults to false
---@field publish_diagnostics boolean?    # defaults to false
---@field parser              bob.Parser? # defaults to nil
-- private:
---@field _namespace  integer
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
    move_focus = opts.move_focus,
    publish_diagnostics = opts.publish_diagnostics,
    parser = require("bob.parser").create_parser(opts.parser),
    _namespace = vim.api.nvim_create_namespace("bob.builder." .. opts.name),
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

  vim.diagnostic.reset(self._namespace)

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
    { "TermClose" },
    {
      group = bob_group,
      buffer = builder_buf,
      callback = function()
        if not self.parser then return end

        local lines = vim.api.nvim_buf_get_lines(0, 0, vim.api.nvim_buf_line_count(0), false)
        local output = table.concat(lines, '\n')
        local diagnostics = self.parser.parse(output)
        if #diagnostics == 0 then return end

        local prep_buf = function(file)
          local bufnr = vim.fn.bufnr(file)
          if bufnr <= 0 then
            vim.cmd("bad " .. file)
            bufnr = vim.fn.bufnr(file)
          end
          return bufnr
        end

        if self.publish_diagnostics then
          local to_publish = {}
          for _, d in ipairs(diagnostics) do
            local bufnr = prep_buf(d["file"])
            if bufnr > 0 then
              if not to_publish[bufnr] then to_publish[bufnr] = {} end
              table.insert(to_publish[bufnr], d)
            end
          end

          for bufnr, buf_diagnostics in pairs(to_publish) do
            vim.diagnostic.set(self._namespace, bufnr, buf_diagnostics)
          end
        end

        if self.move_focus then
          local d = diagnostics[1]
          self:toggle_window()
          local bufnr = prep_buf(d["file"])
          if bufnr > 0 then
            vim.api.nvim_set_current_buf(bufnr)
            vim.api.nvim_win_set_cursor(0, { d.lnum + 1, d.col })
          end
        end
      end
    }
  )

  vim.api.nvim_create_autocmd(
    { "BufDelete", "QuitPre" },
    {
      group = bob_group,
      buffer = builder_buf,
      callback = function(_)
        self:kill()
        vim.diagnostic.reset(self._namespace)
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
