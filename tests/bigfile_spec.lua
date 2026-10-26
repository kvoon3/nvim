-- Headless mini.test spec for lua/bigfile.lua.
-- Run all specs with: just test

local expect = require('mini.test').expect
local bigfile = require 'bigfile'

local function scratch(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end

-- Enough short lines to cross the 256KB size threshold without any long line.
local function bulky_lines(count, width)
  local lines = {}
  for i = 1, count do
    lines[i] = string.format('%05d', i) .. ('-'):rep(width - 5)
  end
  return lines
end

describe('bigfile', function()
  it('is false for ordinary code', function()
    expect.equality(false, bigfile.is_bigfile(scratch { 'const a = 1', ('x'):rep(120) }))
  end)

  it('is true once a line exceeds the limit', function()
    expect.equality(true, bigfile.is_bigfile(scratch { 'ok', ('x'):rep(2001) }))
  end)

  it('is true for a large file made of short lines', function()
    expect.equality(true, bigfile.is_bigfile(scratch(bulky_lines(4000, 100))))
  end)

  it('is false just below the size threshold', function()
    expect.equality(false, bigfile.is_bigfile(scratch(bulky_lines(2000, 100))))
  end)

  it('recomputes after the buffer changes', function()
    local buf = scratch { 'short' }
    expect.equality(false, bigfile.is_bigfile(buf))
    vim.api.nvim_buf_set_lines(buf, 1, -1, false, { ('y'):rep(5000) })
    expect.equality(true, bigfile.is_bigfile(buf))
  end)

  it('recomputes back to false when the content shrinks', function()
    local buf = scratch(bulky_lines(4000, 100))
    expect.equality(true, bigfile.is_bigfile(buf))
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'small' })
    expect.equality(false, bigfile.is_bigfile(buf))
  end)
end)
