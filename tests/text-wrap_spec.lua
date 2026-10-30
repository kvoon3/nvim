-- Headless mini.test spec for lua/text-wrap.lua.
-- Run all specs with: just test

local expect = require('mini.test').expect
local wrap = require('text-wrap').wrap

describe('text-wrap', function()
  it('breaks at word boundaries', function()
    expect.equality({ 'hello', 'world' }, wrap('hello world', 10))
    expect.equality({ 'hello world' }, wrap('hello world', 11))
  end)

  it('counts CJK characters as two cells', function()
    local lines = wrap(string.rep('中', 10), 10)
    expect.equality({ '中中中中中', '中中中中中' }, lines)
  end)

  it('hard-breaks tokens wider than the window', function()
    local lines = wrap('supercalifragilistic', 10)
    for _, line in ipairs(lines) do
      expect.equality(true, vim.fn.strdisplaywidth(line) <= 10)
    end
  end)

  it('never exceeds the requested display width', function()
    local text =
      'Serialize the request body, stream the response, and coalesce chunks that arrive faster than the render loop.'
    for _, width in ipairs { 10, 20, 33, 80 } do
      for _, line in ipairs(wrap(text, width)) do
        expect.equality(true, vim.fn.strdisplaywidth(line) <= width)
      end
    end
  end)
end)
