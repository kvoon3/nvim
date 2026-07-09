return {
  'neo451/jieba-lua',
  lazy = false,
  config = function()
    --[[
      jieba.hmm.cut prints non-Chinese blocks (debug leftover), which floods
      the message area on w/b/e and triggers the hit-enter prompt.
    ]]
    local hmm = require('jieba.hmm')
    local cut = hmm.cut
    hmm.cut = function(sentence)
      local old = print
      print = function() end
      local ok, result = pcall(cut, sentence)
      print = old
      if not ok then
        error(result)
      end
      return result
    end

    -- Plugin maps w/b/e/ge; add WORD variants.
    require('wordmotion.nvim.jieba').set_keymaps({
      W = { { 'n', 'x' }, { true, true } },
      B = { { 'n', 'x' }, { true, false } },
      E = { { 'n', 'x' }, { false, true } },
      gE = { { 'n', 'x' }, { false, false } },
    })
  end,
}
