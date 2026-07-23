return {
  'neo451/jieba-lua',
  lazy = false,
  config = function()
    --[[
      Default HMM mode can split multi-byte non-Chinese chars (e.g. · U+00B7)
      into raw bytes. wordmotion then crashes with "invalid UTF-8 code" and
      shows the hit-enter prompt. Dictionary mode avoids that; quality is fine
      for normal Chinese text.
    ]]
    local j = require 'wordmotion.nvim.jieba'
    j.jieba_motion = {
      jieba = require('jieba.jieba').Jieba { hmm = false },
    }
    j.motion = nil
    j.init()

    -- Plugin maps w/b/e/ge; add WORD variants.
    j.set_keymaps {
      W = { { 'n', 'x' }, { true, true } },
      B = { { 'n', 'x' }, { true, false } },
      E = { { 'n', 'x' }, { false, true } },
      gE = { { 'n', 'x' }, { false, false } },
    }

    vim.schedule(function()
      local clue = require 'mini.clue'
      for _, mapping in ipairs {
        { 'ge', 'Go backwards to end of previous word' },
        { 'gE', 'Go backwards to end of previous WORD' },
      } do
        clue.set_mapping_desc('n', mapping[1], mapping[2])
        clue.set_mapping_desc('x', mapping[1], mapping[2])
      end
    end)
  end,
}
