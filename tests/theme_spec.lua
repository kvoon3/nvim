-- Headless mini.test spec for lua/theme/init.lua.
-- Run all specs with: just test

local expect = require('mini.test').expect
local theme = require 'theme'

local runtime_file = vim.fn.stdpath 'data' .. '/theme_settings.json'

describe('theme', function()
  before_each(function()
    vim.fn.delete(runtime_file)
  end)

  after_each(function()
    vim.fn.delete(runtime_file)
  end)

  it('creates runtime settings from default on first load', function()
    package.loaded['theme'] = nil
    require 'theme'
    expect.equality(true, vim.fn.filereadable(runtime_file) == 1)
  end)

  it('returns default light and dark themes', function()
    expect.equality('vitesse-light-soft', theme.get_light())
    expect.equality('vitesse-black', theme.get_dark())
  end)

  it('updates runtime settings', function()
    theme.set_light 'kanagawa-lotus'
    theme.set_dark 'kanagawa-wave'

    expect.equality('kanagawa-lotus', theme.get_light())
    expect.equality('kanagawa-wave', theme.get_dark())
  end)

  describe('picker', function()
    local picker_opts

    before_each(function()
      -- Reset to defaults before each picker test.
      theme.set_light 'vitesse-light-soft'
      theme.set_dark 'vitesse-black'
      picker_opts = nil

      Snacks = {
        picker = {
          colorschemes = function(opts)
            picker_opts = opts
          end,
        },
      }
    end)

    after_each(function()
      Snacks = nil
    end)

    local function confirm(name)
      expect.equality('table', type(picker_opts))
      picker_opts.confirm({ close = function() end, preview = { state = {} } }, { text = name })
    end

    it('saves the selected light theme', function()
      theme.pick_light()
      confirm 'everforest'
      expect.equality('everforest', theme.get_light())
      expect.equality('vitesse-black', theme.get_dark())
    end)

    it('saves the selected dark theme', function()
      theme.pick_dark()
      confirm 'everforest'
      expect.equality('vitesse-light-soft', theme.get_light())
      expect.equality('everforest', theme.get_dark())
    end)

    it('keeps settings when the picker is cancelled', function()
      theme.pick_dark()
      expect.equality('table', type(picker_opts))
      picker_opts.confirm({ close = function() end, preview = { state = {} } }, nil)
      expect.equality('vitesse-black', theme.get_dark())
    end)
  end)
end)
