-- Headless mini.test spec for lua/jieba-native.lua.
-- Run all specs with: just test
--
-- The harness uses a temporary XDG_DATA_HOME, so the shared library is normally
-- absent: these cases cover the fallback contract. Export
-- NVIM_JIEBA_NATIVE_LIB=~/.local/share/nvim/jieba-native/libjieba_native.dylib
-- to also exercise the native segmentation paths.

local expect = require('mini.test').expect
local native = require 'jieba-native'

--- Segmenter under test, or nil when the library has not been built.
local function segmenter()
  local seg, reason = native.new { hmm = false }
  if seg == nil then
    expect.equality('string', type(reason))
  end
  return seg
end

describe('jieba-native', function()
  it('reports why the native segmenter is unavailable', function()
    local seg, reason = native.new {}
    if seg ~= nil then
      expect.equality(nil, native.reason())
      return
    end
    expect.equality('string', type(reason))
    expect.equality(reason, native.reason())
  end)

  it('reuses the shared segmenter and prewarms without errors', function()
    local first, reason = native.get { hmm = false }
    expect.equality(true, first == native.get { hmm = false })
    local ok = pcall(native.prewarm, { hmm = false })
    expect.equality(true, ok)
    if first == nil then
      expect.equality('string', type(reason))
    end
  end)

  it('cuts chinese words into a partition of the input', function()
    local seg = segmenter()
    if seg == nil then
      return
    end
    local text = '我们正在测试 Neovim 的中文分词功能'
    local tokens = seg:cut(text)
    expect.equality(text, table.concat(tokens))
    expect.equality({ '我们', '正在', '测试' }, { tokens[1], tokens[2], tokens[3] })
  end)

  it('keeps separator gaps so tokens always cover the input', function()
    local seg = segmenter()
    if seg == nil then
      return
    end
    local text = '  前导 和 尾随  '
    expect.equality(text, table.concat(seg:cut(text)))
  end)

  it('returns no tokens for an empty string', function()
    local seg = segmenter()
    if seg == nil then
      return
    end
    expect.equality({}, seg:cut '')
  end)

  it('matches the lua jieba on common words', function()
    local seg = segmenter()
    --[[ The Lua jieba ships with the jieba-lua plugin (lazy-rocks), which the test
    harness does not load; skip the comparison when it is absent. ]]
    local ok, lua_jieba = pcall(function()
      return require('jieba.jieba').Jieba { hmm = false }
    end)
    if seg == nil or not ok then
      return
    end
    for _, text in ipairs { '你好世界', '中文分词', '我们出去玩吧' } do
      expect.equality(table.concat(lua_jieba:cut(text), '|'), table.concat(seg:cut(text), '|'))
    end
  end)
end)
