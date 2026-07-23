-- Headless mini.test spec for lua/statusline.lua.
-- Run all specs with: just test

local expect = require('mini.test').expect
local statusline = require 'statusline'

describe('statusline', function()
  describe('footer render', function()
    it('keeps the position info right-aligned', function()
      local line = statusline.render()
      expect.equality(true, line:find('%l:%c', 1, true) ~= nil)
      expect.equality(true, line:find('%=', 1, true) ~= nil)
    end)

    it('no longer shows the file path (moved to the header)', function()
      expect.equality(nil, statusline.render():find('%f', 1, true))
    end)

    it('exposes a click label per action icon', function()
      local line = statusline.render()
      for _, handler in ipairs { 'click_explorer', 'click_terminal', 'click_finder', 'click_github' } do
        local label = "%@v:lua.require'statusline'." .. handler .. '@'
        expect.equality(true, line:find(label, 1, true) ~= nil)
        expect.equality(true, line:find(label .. '.-%%X') ~= nil)
      end
    end)
  end)

  describe('header render', function()
    it('centers the file path and flags', function()
      local line = statusline.render_header()
      expect.equality('%=', line:sub(1, 2))
      expect.equality('%=', line:sub(-2))
      expect.equality(true, line:find('%f', 1, true) ~= nil)
      expect.equality(true, line:find('%r%h%w', 1, true) ~= nil)
    end)

    it('shows a dirty dot only for modified buffers', function()
      local modified = vim.bo.modified
      vim.bo.modified = true
      expect.equality(true, statusline.render_header():find('•', 1, true) ~= nil)
      vim.bo.modified = false
      expect.equality(nil, statusline.render_header():find('•', 1, true))
      vim.bo.modified = modified
    end)
  end)

  describe('git section', function()
    local function stub_git(status)
      package.loaded['git-status'] = {
        get = function()
          return status
        end,
      }
    end

    after_each(function()
      package.loaded['git-status'] = nil
    end)

    it('is empty outside a git repository', function()
      stub_git(nil)
      expect.equality(true, statusline.render():find('%=', 1, true) ~= nil)
    end)

    it('shows the branch name as a lazygit click label', function()
      stub_git { branch = 'main', upstream = true, ahead = 0, behind = 0, dirty = false }
      local line = statusline.render()
      local inner = line:match 'click_branch@(.-)%%X'
      expect.equality(true, inner ~= nil and inner:find('main', 1, true) ~= nil)
    end)

    it('shows a dirty indicator when there are uncommitted changes', function()
      stub_git { branch = 'main', upstream = true, ahead = 0, behind = 0, dirty = true }
      local line = statusline.render()
      expect.equality(true, line:find('•', 1, true) ~= nil)
    end)

    it('shows only the branch icon when the branch name is unknown (netrw)', function()
      stub_git { branch = nil, upstream = true, ahead = 0, behind = 0, dirty = false }
      local line = statusline.render()
      expect.equality(true, line:find('click_branch@', 1, true) ~= nil)
      expect.equality(nil, line:find('click_branch@.-main', 1, true))
    end)

    it('shows a push arrow when ahead', function()
      stub_git { branch = 'main', upstream = true, ahead = 2, behind = 0, dirty = false }
      local line = statusline.render()
      expect.equality(true, line:find('click_push@', 1, true) ~= nil)
      expect.equality(true, line:find('2', 1, true) ~= nil)
    end)

    it('shows a pull arrow when behind', function()
      stub_git { branch = 'main', upstream = true, ahead = 0, behind = 3, dirty = false }
      expect.equality(true, statusline.render():find('click_pull@', 1, true) ~= nil)
    end)

    it('merges both arrows into one rebase+push button when diverged', function()
      stub_git { branch = 'main', upstream = true, ahead = 2, behind = 3, dirty = false }
      local line = statusline.render()
      expect.equality(true, line:find('click_pull_rebase_push@', 1, true) ~= nil)
      expect.equality(nil, line:find('click_push@', 1, true))
      expect.equality(nil, line:find('click_pull@', 1, true))
    end)

    it('shows no arrows without an upstream', function()
      stub_git { branch = 'main', upstream = false, ahead = 0, behind = 0, dirty = false }
      local line = statusline.render()
      expect.equality(nil, line:find('click_push@', 1, true))
      expect.equality(nil, line:find('click_pull@', 1, true))
    end)
  end)

  describe('click handlers', function()
    local calls
    local pickers

    local function picker_stub()
      return {
        close = function()
          table.insert(calls, 'close')
        end,
      }
    end

    local function left_click(handler)
      handler(0, 1, 'l', '')
    end

    before_each(function()
      calls = {}
      pickers = {}
      Snacks = {
        picker = {
          get = function()
            return pickers
          end,
          explorer = function()
            table.insert(calls, 'explorer')
          end,
        },
        lazygit = function()
          table.insert(calls, 'lazygit')
        end,
      }
      package.loaded['git-status'] = {
        push = function()
          table.insert(calls, 'push')
        end,
        pull = function()
          table.insert(calls, 'pull')
        end,
        pull_rebase_push = function()
          table.insert(calls, 'pull_rebase_push')
        end,
      }
      package.loaded['open-in-github'] = {
        open_in_github = function()
          table.insert(calls, 'github')
        end,
      }
    end)

    after_each(function()
      Snacks = nil
      package.loaded['git-status'] = nil
      package.loaded['open-in-github'] = nil
    end)

    it('opens the explorer when it is closed', function()
      left_click(statusline.click_explorer)
      expect.equality({ 'explorer' }, calls)
    end)

    it('closes the explorer when it is open', function()
      pickers = { picker_stub(), picker_stub() }
      left_click(statusline.click_explorer)
      expect.equality({ 'close', 'close' }, calls)
    end)

    it('toggles the terminal', function()
      local orig_cmd = vim.cmd
      vim.cmd = function(c)
        table.insert(calls, c)
      end
      left_click(statusline.click_terminal)
      vim.cmd = orig_cmd
      expect.equality({ 'ToggleTerm' }, calls)
    end)

    it('opens lazygit when clicking the branch', function()
      left_click(statusline.click_branch)
      expect.equality({ 'lazygit' }, calls)
    end)

    it('schedules startinsert after lazygit (click processing resets the mode)', function()
      local scheduled
      local orig_schedule = vim.schedule
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.schedule = function(fn)
        scheduled = fn
      end
      left_click(statusline.click_branch)
      vim.schedule = orig_schedule
      expect.equality('function', type(scheduled))
    end)

    it('runs push / pull / rebase+push on the git arrows', function()
      left_click(statusline.click_push)
      left_click(statusline.click_pull)
      left_click(statusline.click_pull_rebase_push)
      expect.equality({ 'push', 'pull', 'pull_rebase_push' }, calls)
    end)

    it('reveals the current file in Finder', function()
      vim.api.nvim_buf_set_name(0, '/tmp/nvim-finder-test.lua')
      local cmd
      local orig_system = vim.system
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.system = function(c)
        cmd = c
      end
      left_click(statusline.click_finder)
      vim.system = orig_system
      expect.equality({ 'open', '-R', '/tmp/nvim-finder-test.lua' }, cmd)
    end)

    it('opens the current file in GitHub', function()
      left_click(statusline.click_github)
      expect.equality({ 'github' }, calls)
    end)

    it('ignores non-left clicks', function()
      statusline.click_explorer(0, 1, 'r', '')
      statusline.click_branch(0, 1, 'm', '')
      statusline.click_push(0, 1, 'r', '')
      expect.equality({}, calls)
    end)
  end)

  describe('disabled windows', function()
    local winid

    local function open_win(ft, buftype)
      local buf = vim.api.nvim_create_buf(false, true)
      vim.bo[buf].filetype = ft
      vim.bo[buf].buftype = buftype or ''
      winid = vim.api.nvim_open_win(buf, false, { split = 'right' })
      vim.g.statusline_winid = winid
    end

    after_each(function()
      vim.g.statusline_winid = nil
      if winid and vim.api.nvim_win_is_valid(winid) and #vim.api.nvim_list_wins() > 1 then
        vim.api.nvim_win_close(winid, true)
      end
      winid = nil
    end)

    it('renders blank footer and header for snacks explorer windows', function()
      local fts = { 'snacks_picker_list', 'snacks_picker_input', 'snacks_picker_preview', 'snacks_layout_box' }
      for _, ft in ipairs(fts) do
        open_win(ft)
        expect.equality('', statusline.render(), 'expected blank footer for ' .. ft)
        expect.equality('', statusline.render_header(), 'expected blank header for ' .. ft)
        vim.api.nvim_win_close(winid, true)
        winid = nil
      end
    end)

    it('renders blank footer and header for terminal buffers', function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      vim.fn.jobstart({ 'cat' }, { term = true })
      winid = vim.api.nvim_open_win(buf, false, { split = 'right' })
      vim.g.statusline_winid = winid
      expect.equality('', statusline.render())
      expect.equality('', statusline.render_header())
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it('renders blank header but normal footer for non-file buffers', function()
      open_win('', 'nofile')
      expect.equality('', statusline.render_header())
      expect.equality(true, statusline.render():find('%l:%c', 1, true) ~= nil)
    end)

    it('renders full footer and header for normal windows', function()
      open_win 'lua'
      expect.equality(true, statusline.render():find('%f', 1, true) == nil)
      expect.equality(true, statusline.render_header():find('%f', 1, true) ~= nil)
    end)
  end)
end)
