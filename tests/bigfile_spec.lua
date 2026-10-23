-- Headless mini.test spec for lua/bigfile.lua.
-- Run all specs with: just test

local expect = require('mini.test').expect
local bigfile = require 'bigfile'

local function scratch(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end

describe('bigfile', function()
  it('is false for ordinary code', function()
    expect.equality(false, bigfile.is_bigfile(scratch { 'const a = 1', ('x'):rep(120) }))
  end)

  it('is true once a line exceeds the limit', function()
    expect.equality(true, bigfile.is_bigfile(scratch { 'ok', ('x'):rep(2001) }))
  end)

  it('recomputes after the buffer changes', function()
    local buf = scratch { 'short' }
    expect.equality(false, bigfile.is_bigfile(buf))
    vim.api.nvim_buf_set_lines(buf, 1, -1, false, { ('y'):rep(5000) })
    expect.equality(true, bigfile.is_bigfile(buf))
  end)
end)
