-- Headless mini.test spec for lua/jieba-tokens.lua.
-- Run all specs with: just test

local expect = require('mini.test').expect
local tokens_mod = require 'jieba-tokens'

--- Segmenter stub returning `tokens` for any input.
local function stub(tokens)
  return {
    cut = function(_, _)
      return tokens
    end,
  }
end

describe('jieba-tokens', function()
  it('passes short lines through unchanged', function()
    local inner = stub { 'hello', ' ', 'world' }
    local cut = tokens_mod.wrap(inner)
    expect.equality({ 'hello', ' ', 'world' }, cut:cut 'hello world')
  end)

  it('caps the token count on pathological lines', function()
    local text = ('a'):rep(20000)
    local inner = stub(vim.split(text, '', { plain = true }))
    local tokens = tokens_mod.wrap(inner):cut(text)
    expect.equality(true, #tokens <= 4096)
    expect.equality(text, table.concat(tokens))
  end)

  it('never splits a multi-byte character', function()
    local text = ('中文测试'):rep(5000) -- 60 KB of UTF-8
    local inner = stub(vim.fn.split(text, '\\zs'))
    local tokens = tokens_mod.wrap(inner):cut(text)
    expect.equality(true, #tokens <= 4096)
    expect.equality(text, table.concat(tokens))
    for _, token in ipairs(tokens) do
      --[[ strcharpart/strchars round-trip is false when the token starts or
      ends inside a multi-byte sequence. ]]
      expect.equality(token, vim.fn.strcharpart(token, 0, vim.fn.strchars(token)))
    end
  end)

  it('memoizes the last big line only', function()
    local text = ('ab'):rep(8000)
    local calls = 0
    local inner = {
      cut = function(_, _)
        calls = calls + 1
        return vim.split(text, '', { plain = true })
      end,
    }
    local cut = tokens_mod.wrap(inner)
    local first = cut:cut(text)
    expect.equality(true, first == cut:cut(text))
    expect.equality(1, calls)
    cut:cut 'short'
    cut:cut 'short'
    expect.equality(3, calls)
  end)
end)
