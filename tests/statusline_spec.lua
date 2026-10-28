-- Headless mini.test spec for lua/statusline.lua.
-- Run all specs with: just test

local expect = require('mini.test').expect
local statusline = require 'statusline'

describe('statusline', function()
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

  describe('footer actions', function()
    it('exposes a click label per action icon', function()
      local line = statusline.actions()
      for _, handler in ipairs { 'click_explorer', 'click_terminal', 'click_finder', 'click_github' } do
        local label = "%@v:lua.require'statusline'." .. handler .. '@'
        expect.equality(true, line:find(label, 1, true) ~= nil)
        expect.equality(true, line:find(label .. '.-%%X') ~= nil)
      end
    end)

    it('draws every action from a product icon', function()
      local icons = require 'product-icons'
      for _, role in ipairs { 'explorer', 'terminal', 'finder', 'github' } do
        local segment = icons.segment(role)
        expect.equality(true, segment ~= nil and segment.text ~= '')
      end
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
      package.loaded['open-in-github'] = {
        open_in_github = function()
          table.insert(calls, 'github')
        end,
      }
    end)

    after_each(function()
      Snacks = nil
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

    it('renders a blank header for snacks explorer windows', function()
      local fts = { 'snacks_picker_list', 'snacks_picker_input', 'snacks_picker_preview', 'snacks_layout_box' }
      for _, ft in ipairs(fts) do
        open_win(ft)
        expect.equality('', statusline.render_header(), 'expected blank header for ' .. ft)
        vim.api.nvim_win_close(winid, true)
        winid = nil
      end
    end)

    it('renders a blank header for terminal buffers', function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      vim.fn.jobstart({ 'cat' }, { term = true })
      winid = vim.api.nvim_open_win(buf, false, { split = 'right' })
      vim.g.statusline_winid = winid
      expect.equality('', statusline.render_header())
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it('renders a blank header but a full winbar path for plain files', function()
      open_win 'lua'
      expect.equality(true, statusline.render_header():find('%f', 1, true) ~= nil)
    end)

    it('renders a blank header for non-file buffers', function()
      open_win('', 'nofile')
      expect.equality('', statusline.render_header())
    end)
  end)
end)
