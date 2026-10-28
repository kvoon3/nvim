-- Headless mini.test spec for lua/wave.lua.
-- Run all specs with: just test

local expect = require('mini.test').expect
local wave = require 'wave'

local function namespace()
  return vim.api.nvim_get_namespaces().wave
end

local function marks(buf)
  return vim.api.nvim_buf_get_extmarks(buf, namespace(), 0, -1, { details = true })
end

--[[ A scratch buffer holding `lines`, with the cursor on the first row. ]]
local function scratch(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  return buf
end

describe('wave', function()
  local saved_normal

  before_each(function()
    wave.setup()
    saved_normal = vim.api.nvim_get_hl(0, { name = 'Normal' })
  end)

  after_each(function()
    wave.stop()
    wave.set_enabled(true)
    vim.api.nvim_set_hl(0, 'Normal', saved_normal)
  end)

  describe('slices', function()
    it('tiles a row span without gaps', function()
      expect.equality({
        { from = 2, to = 5 },
        { from = 5, to = 8 },
        { from = 8, to = 9 },
      }, wave.slices('abcdefghij', 2, 9, 3))
    end)

    it('never splits a multibyte character', function()
      local line = 'a世界b' -- 1 + 3 + 3 + 1 bytes
      expect.equality(8, #line)
      expect.equality({
        { from = 0, to = 4 },
        { from = 4, to = 7 },
        { from = 7, to = 8 },
      }, wave.slices(line, 0, #line, 2))
    end)

    it('leaves an empty span alone', function()
      expect.equality({}, wave.slices('abc', 1, 1, 2))
    end)
  end)

  describe('spans', function()
    it('covers whole lines for linewise regions', function()
      expect.equality({
        { from = 0, to = 5 },
        { from = 0, to = 0 },
        { from = 0, to = 3 },
      }, wave.spans('line', 0, 0, { 5, 0, 3 }))
    end)

    it('funnels a multi-line charwise region out of and back into the marks', function()
      expect.equality({
        { from = 2, to = 6 },
        { from = 0, to = 8 },
        { from = 0, to = 1 },
      }, wave.spans('char', 2, 1, { 6, 8, 4 }))
    end)

    it('keeps a single-line charwise region inside its marks', function()
      expect.equality({ { from = 2, to = 7 } }, wave.spans('char', 2, 7, { 9 }))
    end)

    it('rectangles a blockwise region on every row', function()
      expect.equality({
        { from = 1, to = 3 },
        { from = 1, to = 2 },
        { from = 1, to = 3 },
      }, wave.spans('block', 3, 1, { 9, 2, 9 }))
    end)
  end)

  describe('diagonal', function()
    it('runs from the top-left corner to the bottom-right one', function()
      expect.equality(0, wave.progress(1, 3, 0, 10))
      expect.equality(0.75, wave.progress(3, 3, 5, 10))
      expect.equality(1, wave.progress(3, 3, 10, 10))
    end)

    it('sweeps a single row left to right', function()
      expect.equality(0, wave.progress(1, 1, 0, 20))
      expect.equality(1, wave.progress(1, 1, 20, 20))
      expect.equality(true, wave.progress(1, 1, 5, 20) < wave.progress(1, 1, 15, 20))
    end)

    it('maps positions onto the band range', function()
      expect.equality(1, wave.band(0, 32))
      expect.equality(1, wave.band(-1, 32))
      expect.equality(32, wave.band(1, 32))
      expect.equality(32, wave.band(2, 32))
    end)

    it('spreads band start times across the stagger', function()
      expect.equality(0, wave.delay(1, 32, 150))
      expect.equality(150, wave.delay(32, 32, 150))
      expect.equality(0, wave.delay(1, 1, 150))
    end)

    it('stays invisible until its band starts and settles opaque', function()
      expect.equality(0, wave.opacity(0, 50, 100))
      expect.equality(0, wave.opacity(49, 50, 100))
      expect.equality(0.5, wave.opacity(100, 50, 100))
      expect.equality(1, wave.opacity(150, 50, 100))
      expect.equality(true, wave.opacity(75, 50, 100) > wave.opacity(60, 50, 100))
    end)
  end)

  describe('plan', function()
    it('buckets a grid top-left first and bottom-right last', function()
      local rows = {
        { row = 4, line = 'abcdefgh', from = 0, to = 8 },
        { row = 5, line = 'abcdefgh', from = 0, to = 8 },
      }
      local planned = wave.plan(rows, 8)

      expect.equality(true, #planned > 0)
      expect.equality({ row = 4, from = 0, band = 1 }, {
        row = planned[1].row,
        from = planned[1].from,
        band = planned[1].band,
      })
      expect.equality({ row = 5, band = 8 }, { row = planned[#planned].row, band = planned[#planned].band })

      for index = 2, #planned do
        expect.equality(true, planned[index].band >= planned[index - 1].band)
      end
    end)
  end)

  describe('rows', function()
    it('keeps the visible rows and their absolute positions', function()
      scratch { 'alpha', 'bravo', 'charlie' }

      local rows = wave.rows { top = 0, bottom = 2, shape = 'line' }
      expect.equality(3, #rows)
      expect.equality({ row = 0, from = 0, to = 5 }, { row = rows[1].row, from = rows[1].from, to = rows[1].to })
      expect.equality({ row = 2, from = 0, to = 7 }, { row = rows[3].row, from = rows[3].from, to = rows[3].to })
    end)

    it('refuses a region that is too large to take in', function()
      local lines = {}
      for index = 1, 200 do
        lines[index] = 'line ' .. index
      end
      scratch(lines)

      expect.equality(nil, wave.rows { top = 0, bottom = 199, shape = 'line' })
    end)

    it('refuses a single line that is too many bytes', function()
      scratch { string.rep('x', 12001), 'short' }

      expect.equality(nil, wave.rows { top = 0, bottom = 0, shape = 'line' })
    end)

    it('refuses a region that is not on screen', function()
      local lines = {}
      for index = 1, 100 do
        lines[index] = 'line ' .. index
      end
      scratch(lines)
      vim.api.nvim_win_set_cursor(0, { 1, 0 })

      expect.equality(nil, wave.rows { top = 60, bottom = 61, shape = 'line' })
    end)

    it('drops empty rows', function()
      scratch { 'alpha', '', 'charlie' }

      local rows = wave.rows { top = 0, bottom = 2, shape = 'line' }
      expect.equality(2, #rows)
      expect.equality(2, rows[2].row)
    end)
  end)

  describe('marked', function()
    it('reads the changed region and its shape', function()
      scratch { 'alpha', 'bravo', 'charlie', 'delta' }
      vim.cmd 'normal! Vj"ay'

      local rect = wave.marked 'line'
      expect.equality(
        { top = 0, bottom = 1, shape = 'line' },
        { top = rect.top, bottom = rect.bottom, shape = rect.shape }
      )
      expect.equality(true, rect.last >= #'bravo')
    end)
  end)

  describe('timing', function()
    local function region(count, span)
      local rows = {}
      for index = 1, count do
        rows[index] = { row = index - 1, line = string.rep('x', span), from = 0, to = span }
      end
      return rows
    end

    it('keeps a tiny region readable instead of blinking past', function()
      local total = wave.timing(region(1, 5))
      expect.equality(true, total >= 120)
    end)

    it('sweeps a long region for longer than a short one', function()
      local short = wave.timing(region(5, 40))
      local tall = wave.timing(region(20, 80))
      local taller = wave.timing(region(40, 120))

      expect.equality(true, short < tall)
      expect.equality(true, tall < taller)
    end)

    it('still settles a huge region quickly', function()
      local total = wave.timing(region(400, 400))
      expect.equality(800, total)
    end)

    it('keeps the front narrow so the direction reads', function()
      --[[ A band fade that swallows the whole sweep turns the diagonal into a
      plain fade, which is how the direction disappeared once. ]]
      for _, size in ipairs { { 1, 20 }, { 3, 30 }, { 5, 40 }, { 20, 80 }, { 40, 120 }, { 80, 200 } } do
        local total, fade = wave.timing(region(size[1], size[2]))
        expect.equality(true, fade / (total - fade) <= 0.4)
      end
    end)

    it('never lets the band fade outlast the sweep', function()
      for _, size in ipairs { { 1, 1 }, { 1, 5 }, { 3, 30 }, { 400, 400 } } do
        local total, fade = wave.timing(region(size[1], size[2]))
        expect.equality(true, fade < total)
      end
    end)
  end)

  describe('styles', function()
    it('fades text in from the background on an opaque theme', function()
      vim.api.nvim_set_hl(0, 'Normal', { fg = 0xcdd6f4, bg = 0x1e1e2e })
      local buf = scratch { 'alpha', 'bravo' }

      wave.fade_in { top = 0, bottom = 1, shape = 'line' }

      local painted = marks(buf)
      expect.equality(true, #painted > 0)
      local band = vim.api.nvim_get_hl(0, { name = painted[1][4].hl_group })
      expect.equality(0x1e1e2e, band.bg)
      expect.equality(band.bg, band.fg)
    end)

    it('flashes the background on an opaque theme', function()
      vim.api.nvim_set_hl(0, 'Normal', { fg = 0xcdd6f4, bg = 0x1e1e2e })
      local buf = scratch { 'alpha', 'bravo' }

      wave.flash({ top = 0, bottom = 1, shape = 'line' }, 0xe06c75)

      local painted = marks(buf)
      expect.equality(true, #painted > 0)
      local band = vim.api.nvim_get_hl(0, { name = painted[1][4].hl_group })
      expect.equality(nil, band.fg)
      expect.equality(true, band.bg ~= 0x1e1e2e)
    end)

    it('never paints a block on a transparent theme', function()
      vim.api.nvim_set_hl(0, 'Normal', { fg = 0x393a34 })
      local buf = scratch { 'alpha', 'bravo' }

      wave.fade_in { top = 0, bottom = 1, shape = 'line' }

      local painted = marks(buf)
      expect.equality(true, #painted > 0)
      local band = vim.api.nvim_get_hl(0, { name = painted[1][4].hl_group })
      expect.equality(nil, band.bg)
      expect.equality('number', type(band.fg))
    end)

    it('flashes the text color instead when the theme is transparent', function()
      vim.api.nvim_set_hl(0, 'Normal', { fg = 0x393a34 })
      local buf = scratch { 'alpha', 'bravo' }

      wave.flash({ top = 0, bottom = 1, shape = 'line' }, 0xe06c75)

      local painted = marks(buf)
      expect.equality(true, #painted > 0)
      local band = vim.api.nvim_get_hl(0, { name = painted[1][4].hl_group })
      expect.equality(nil, band.bg)
      expect.equality(true, band.fg ~= 0x393a34)
    end)

    it('clears its marks and groups when the sweep ends', function()
      local buf = scratch { 'alpha' }

      wave.flash({ top = 0, bottom = 0, shape = 'line' }, 0x98c379)
      expect.equality(true, wave.is_running())

      vim.wait(800, function()
        return not wave.is_running()
      end, 20)

      expect.equality(false, wave.is_running())
      expect.equality(0, #marks(buf))
      expect.equality(vim.empty_dict(), vim.api.nvim_get_hl(0, { name = 'WaveBand1' }))
    end)

    it('draws nothing while disabled', function()
      local buf = scratch { 'alpha' }

      wave.set_enabled(false)
      wave.flash({ top = 0, bottom = 0, shape = 'line' }, 0x98c379)

      expect.equality(0, #marks(buf))
      expect.equality(false, wave.is_running())
    end)
  end)
end)
