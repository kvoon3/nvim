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
    before_each(function()
      -- Reset to defaults before each picker test.
      theme.set_light 'vitesse-light-soft'
      theme.set_dark 'vitesse-black'

      package.loaded['telescope.actions'] = {
        select_default = function(_) end,
      }
      package.loaded['telescope.actions.state'] = {
        get_selected_entry = function()
          return nil
        end,
      }
      package.loaded['telescope.builtin'] = {
        colorscheme = function(opts)
          local prompt_bufnr = 0
          local mappings = {}

          local function map(mode, key, fn)
            mappings[mode .. key] = fn
          end

          local ok, ret = pcall(opts.attach_mappings, prompt_bufnr, map)
          expect.equality(true, ok)
          expect.equality(true, ret)

          local action_state = require 'telescope.actions.state'
          local orig_get_selected = action_state.get_selected_entry
          action_state.get_selected_entry = function()
            return { value = 'everforest' }
          end

          local on_confirm = mappings['i<CR>'] or mappings['n<CR>']
          expect.equality('function', type(on_confirm))
          on_confirm()

          action_state.get_selected_entry = orig_get_selected

          for _, cb in ipairs(opts.on_complete or {}) do
            cb()
          end
        end,
      }
    end)

    it('saves the selected light theme', function()
      theme.pick_light()
      expect.equality('everforest', theme.get_light())
      expect.equality('vitesse-black', theme.get_dark())
    end)

    it('saves the selected dark theme', function()
      theme.pick_dark()
      expect.equality('vitesse-light-soft', theme.get_light())
      expect.equality('everforest', theme.get_dark())
    end)
  end)
end)
