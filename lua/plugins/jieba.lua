return {
  'neo451/jieba-lua',
  --[[ Building the jieba dictionary and loading wordmotion costs ~50ms at startup.
  Defer both until a word motion is pressed; lazy.nvim replays the key after the
  plugin loads, so the motions behave exactly as when loaded eagerly. ]]
  keys = {
    { 'w', mode = { 'n', 'x' } },
    { 'b', mode = { 'n', 'x' } },
    { 'e', mode = { 'n', 'x' } },
    { 'ge', mode = { 'n', 'x' } },
    { 'W', mode = { 'n', 'x' } },
    { 'B', mode = { 'n', 'x' } },
    { 'E', mode = { 'n', 'x' } },
    { 'gE', mode = { 'n', 'x' } },
  },
  config = function()
    --[[
      Default HMM mode can split multi-byte non-Chinese chars (e.g. · U+00B7)
      into raw bytes. wordmotion then crashes with "invalid UTF-8 code" and
      shows the hit-enter prompt. Dictionary mode avoids that; quality is fine
      for normal Chinese text.
    ]]
    local j = require 'wordmotion.nvim.jieba'
    --[[ Prefer the Rust segmenter (jieba-rs through FFI): cut() is ~140x faster
      than the pure-Lua dictionary. `get` reuses the instance prewarmed at
      startup; fall back to the Lua jieba when the library is not built.
      `jieba-tokens` bounds the token count so single-line minified files do not
      re-tokenize ~700KB into 400k tokens on every w/b/e press. ]]
    j.jieba_motion = {
      jieba = require('jieba-tokens').wrap(
        require('jieba-native').get { hmm = false } or require('jieba.jieba').Jieba { hmm = false }
      ),
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
