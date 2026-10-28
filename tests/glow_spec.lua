-- Headless mini.test spec for lua/glow.lua.
-- Run all specs with: just test

local expect = require('mini.test').expect
local glow = require 'glow'
local wave = require 'wave'

local function namespace()
  return vim.api.nvim_get_namespaces().wave
end

local function marks(buf)
  return vim.api.nvim_buf_get_extmarks(buf, namespace(), 0, -1, { details = true })
end

--[[ A scratch buffer holding `lines`, with the cursor on the first row. The
`undolevels` assignment closes the undo block the setup opened, so a test can
undo exactly what it just did. ]]
local function scratch(lines, filetype)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  vim.bo[buf].filetype = filetype or 'lua'
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.cmd 'let &undolevels = &undolevels'
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  return buf
end

local function lines(buf)
  return vim.api.nvim_buf_get_lines(buf or 0, 0, -1, false)
end

local function rows_used(buf)
  local used = {}
  for _, mark in ipairs(marks(buf)) do
    used[mark[2]] = true
  end

  local sorted = {}
  for row in pairs(used) do
    sorted[#sorted + 1] = row
  end
  table.sort(sorted)
  return sorted
end

--[[ Leftmost start and rightmost end of the extmarks painted on one row. ]]
local function span_on(buf, row)
  local from, to
  for _, mark in ipairs(marks(buf)) do
    if mark[2] == row then
      from = math.min(from or mark[3], mark[3])
      to = math.max(to or 0, mark[4].end_col)
    end
  end

  return from, to
end

describe('glow', function()
  before_each(function()
    glow.setup()
  end)

  --[[ Drop the maps again so this spec cannot leak its keymaps into the rest. ]]
  after_each(function()
    wave.stop()
    wave.set_enabled(true)
    for _, key in ipairs { 'p', 'P', 'gp', 'gP', 'u', 'n', 'N', '*', '#', 'gc', 'gcc' } do
      pcall(vim.keymap.del, 'n', key)
    end
  end)

  describe('paste', function()
    it('fades a short paste in and cleans up after itself', function()
      local buf = scratch { 'alpha', 'beta' }
      vim.fn.setreg('a', { 'one', 'two' }, 'V')

      vim.api.nvim_feedkeys('"ap', 'mx', false)

      expect.equality({ 'alpha', 'one', 'two', 'beta' }, lines(buf))
      expect.equality(true, #marks(buf) > 0)
      expect.equality({ 1, 2 }, rows_used(buf))

      vim.wait(800, function()
        return #marks(buf) == 0
      end, 20)
      expect.equality(0, #marks(buf))
    end)

    it('inserts an oversized paste without a transition', function()
      local buf = scratch { 'alpha' }
      local content = {}
      for index = 1, 300 do
        content[index] = 'line ' .. index
      end
      vim.fn.setreg('a', content, 'V')

      vim.api.nvim_feedkeys('"ap', 'mx', false)

      expect.equality(301, vim.api.nvim_buf_line_count(buf))
      expect.equality(0, #marks(buf))
    end)

    it('reports a refused put instead of raising', function()
      local buf = scratch { 'alpha' }
      vim.fn.setreg('a', 'one', 'v')
      vim.bo[buf].modifiable = false

      vim.api.nvim_feedkeys('"ap', 'mx', false)
      vim.bo[buf].modifiable = true

      expect.equality({ 'alpha' }, lines(buf))
      expect.equality(0, #marks(buf))
    end)

    it('still pastes with animations off', function()
      local buf = scratch { 'alpha' }
      vim.fn.setreg('a', 'one', 'v')

      wave.set_enabled(false)
      vim.api.nvim_feedkeys('"ap', 'mx', false)

      expect.equality({ 'aonelpha' }, lines(buf))
      expect.equality(0, #marks(buf))
    end)
  end)

  describe('undo and redo', function()
    it('restores the deleted lines and flashes where they came back', function()
      local buf = scratch { 'alpha', 'bravo', 'charlie', 'delta' }
      vim.cmd 'normal! 2dd'
      expect.equality({ 'charlie', 'delta' }, lines(buf))

      vim.api.nvim_feedkeys('u', 'mx', false)

      expect.equality({ 'alpha', 'bravo', 'charlie', 'delta' }, lines(buf))
      expect.equality(true, #marks(buf) > 0)
      expect.equality({ 0, 1 }, rows_used(buf))
    end)

    it('redoes the change and flashes where the text went', function()
      local buf = scratch { 'alpha', 'bravo', 'charlie' }
      vim.cmd 'normal! 2dd'
      vim.api.nvim_feedkeys('u', 'mx', false)
      wave.stop()

      vim.api.nvim_feedkeys('\18', 'mx', false)

      expect.equality({ 'charlie' }, lines(buf))
      expect.equality(true, #marks(buf) > 0)
    end)

    it('undoes once per count', function()
      local buf = scratch { 'alpha', 'bravo', 'charlie', 'delta' }
      vim.cmd 'normal! dd'
      vim.cmd 'let &undolevels = &undolevels'
      vim.cmd 'normal! dd'
      expect.equality({ 'charlie', 'delta' }, lines(buf))

      vim.api.nvim_feedkeys('2u', 'mx', false)

      expect.equality({ 'alpha', 'bravo', 'charlie', 'delta' }, lines(buf))
    end)

    it('reports a refused undo instead of raising', function()
      local buf = scratch { 'alpha', 'bravo' }
      vim.cmd 'normal! dd'
      wave.stop()
      local before = lines(buf)
      vim.bo[buf].modifiable = false

      vim.api.nvim_feedkeys('u', 'mx', false)
      vim.bo[buf].modifiable = true

      expect.equality(before, lines(buf))
      expect.equality(0, #marks(buf))
      expect.equality(true, vim.fn.execute('messages'):find('E21', 1, true) ~= nil)
    end)

    it('fades restored text in instead of flashing it', function()
      local buf = scratch { 'alpha', 'bravo', 'charlie' }
      vim.cmd 'normal! 2Gdd'

      vim.api.nvim_feedkeys('u', 'mx', false)

      expect.equality({ 'alpha', 'bravo', 'charlie' }, lines(buf))
      local band = vim.api.nvim_get_hl(0, { name = marks(buf)[1][4].hl_group })
      expect.equality(band.bg, band.fg)
    end)

    it('stays quiet at the end of the history', function()
      local buf = scratch { 'alpha', 'bravo' }
      vim.cmd 'silent undo 0'
      wave.stop()
      local before = lines(buf)

      vim.api.nvim_feedkeys('u', 'mx', false)

      expect.equality(before, lines(buf))
      expect.equality(0, #marks(buf))
    end)
  end)

  describe('expression register', function()
    it('puts the evaluated expression where the key would', function()
      local buf = scratch { 'one', 'two' }
      vim.fn.setreg('=', '1+1')

      glow.put_expression 'p'

      expect.equality({ 'o2ne', 'two' }, lines(buf))
    end)
  end)

  describe('yank', function()
    it('leaves deletes alone, they already show their own work', function()
      local buf = scratch { 'alpha', 'bravo', 'charlie' }

      vim.cmd 'normal! dd'

      expect.equality({ 'bravo', 'charlie' }, lines(buf))
      expect.equality(0, #marks(buf))
    end)

    it('flashes the yanked lines', function()
      local buf = scratch { 'alpha', 'bravo', 'charlie', 'delta' }

      vim.cmd 'normal! Vj"ay'

      expect.equality({ 0, 1 }, rows_used(buf))
      expect.equality(true, wave.is_running())
    end)

    it('leaves deletes alone, they already show their own work', function()
      local buf = scratch { 'alpha', 'bravo', 'charlie' }

      vim.cmd 'normal! dd'

      expect.equality({ 'bravo', 'charlie' }, lines(buf))
      expect.equality(0, #marks(buf))
    end)
  end)

  describe('search', function()
    it('flashes the match the cursor lands on', function()
      local buf = scratch { 'alpha foo beta', 'gamma foo delta' }
      vim.fn.setreg('/', 'foo')

      vim.api.nvim_feedkeys('n', 'mx', false)

      expect.equality(true, #marks(buf) > 0)
      expect.equality({ 0, 6, 9 }, { rows_used(buf)[1], span_on(buf, 0) })
    end)

    it('stays quiet when the search fails', function()
      local buf = scratch { 'alpha', 'bravo' }
      vim.fn.setreg('/', 'nothing-here')
      vim.api.nvim_win_set_cursor(0, { 1, 0 })

      vim.api.nvim_feedkeys('n', 'mx', false)

      expect.equality(0, #marks(buf))
      expect.equality(0, vim.api.nvim_win_get_cursor(0)[1] - 1)
    end)
  end)

  describe('comment', function()
    it('toggles the line and flashes it', function()
      local buf = scratch { 'alpha', 'bravo' }
      vim.bo[buf].commentstring = '-- %s'

      vim.api.nvim_feedkeys('gcc', 'mx', false)

      expect.equality({ '-- alpha', 'bravo' }, lines(buf))
      expect.equality({ 0 }, rows_used(buf))
    end)

    it('follows a visual selection', function()
      local buf = scratch { 'alpha', 'bravo', 'charlie' }
      vim.bo[buf].commentstring = '-- %s'

      vim.api.nvim_feedkeys('Vjgc', 'mx', false)

      expect.equality({ '-- alpha', '-- bravo', 'charlie' }, lines(buf))
      expect.equality({ 0, 1 }, rows_used(buf))
    end)

    it('follows an operator motion', function()
      local buf = scratch { 'alpha', 'bravo', 'charlie' }
      vim.bo[buf].commentstring = '-- %s'

      vim.api.nvim_feedkeys('gc2j', 'mx', false)

      expect.equality({ '-- alpha', '-- bravo', '-- charlie' }, lines(buf))
      expect.equality({ 0, 1, 2 }, rows_used(buf))
    end)
  end)
end)
