-- Headless mini.test spec for lua/theme/canvas.lua.
-- Run all specs with: just test

local expect = require('mini.test').expect
local canvas = require 'theme.canvas'

describe('theme canvas', function()
  local original, saved

  before_each(function()
    original = vim.api.nvim_get_hl
    saved = { background = vim.o.background, colors_name = vim.g.colors_name }
  end)

  after_each(function()
    vim.api.nvim_get_hl = original
    vim.o.background = saved.background
    vim.g.colors_name = saved.colors_name
    package.loaded['vitesse'] = nil
    package.loaded['vitesse.palette'] = nil
  end)

  --[[ Answer highlight lookups from `map` instead of the live colorscheme. ]]
  local function highlights(map)
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.api.nvim_get_hl = function(_, opts)
      return map[opts and opts.name] or {}
    end
  end

  it('uses the Normal background when the scheme paints one', function()
    highlights { Normal = { fg = 0x000000, bg = 0xabcdef } }
    expect.equality(0xabcdef, canvas.get())
  end)

  it('asks a transparent colorscheme for the canvas it omits from Normal', function()
    -- vitesse drops Normal's background when it is set up as transparent, but
    -- its palette still knows the colour it would have painted.
    highlights { Normal = { fg = 0x393a34 } }
    vim.o.background = 'light'
    vim.g.colors_name = 'vitesse-light-soft'
    package.loaded['vitesse'] = { styles = { light = 'light_soft' } }
    package.loaded['vitesse.palette'] = {
      get = function()
        return { bg = '#f1f0e9' }
      end,
    }
    expect.equality(0xf1f0e9, canvas.get())
  end)

  it('ignores a colorscheme that publishes no canvas', function()
    highlights { Normal = { fg = 0x393a34 }, Pmenu = { bg = 0xe7e5db } }
    vim.g.colors_name = 'plain'
    expect.equality(0xe7e5db, canvas.get())
  end)

  it('falls back to white and black when nothing paints a background', function()
    highlights {}
    vim.g.colors_name = 'plain'

    vim.o.background = 'light'
    expect.equality(0xffffff, canvas.get())

    vim.o.background = 'dark'
    expect.equality(0x000000, canvas.get())
  end)
end)
