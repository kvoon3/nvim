-- Headless mini.test spec for lua/product-icons.lua.
-- Run all specs with: just test

local expect = require('mini.test').expect
local product = require 'product-icons'

local spec = debug.getinfo(1, 'S').source:sub(2)
local root = vim.fs.dirname(vim.fs.dirname(spec))

describe('product icons', function()
  it('has a vendored Carbon SVG per role', function()
    local roles = product.roles()
    expect.equality(true, #roles >= 8)

    for _, role in ipairs(roles) do
      local source = product.source(role)
      expect.equality('string', type(source))

      local path = root .. '/assets/product-icons/' .. source .. '.svg'
      expect.equality(1, vim.fn.filereadable(path), role .. ' is missing ' .. path)

      local body = table.concat(vim.fn.readfile(path), '')
      expect.equality(true, body:find('viewBox', 1, true) ~= nil, role .. ' SVG has no viewBox')
      -- The tint is applied by replacing this keyword, so it must be present.
      expect.equality(true, body:find('currentColor', 1, true) ~= nil, role .. ' SVG is not tinted')
    end
  end)

  it('wraps a known role in statusline highlights', function()
    for _, role in ipairs(product.roles()) do
      local segment = product.segment(role)
      expect.equality(true, segment ~= nil)

      local text = product.statusline(role)
      if segment.text == '' then
        expect.equality('', text)
      else
        expect.equality(true, text:find('^%%#', 1, false) ~= nil, role .. ' did not open a highlight')
        expect.equality(true, text:find '%%#%w+#$' ~= nil, role .. ' did not restore a highlight')
      end
    end
  end)

  it('restores the requested group after a severity icon', function()
    local segment = product.segment('error', { restore = 'MiniStatuslineDevinfo' })
    expect.equality('DiagnosticError', segment.group)
    expect.equality('MiniStatuslineDevinfo', segment.restore)
    expect.equality(
      true,
      product.statusline('error', { restore = 'MiniStatuslineDevinfo' }):find('DiagnosticError', 1, true) ~= nil
    )
  end)

  it('is empty for an unknown role', function()
    expect.equality(nil, product.segment 'no-such-icon')
    expect.equality('', product.statusline 'no-such-icon')
    expect.equality('', product.glyph 'no-such-icon')
  end)

  it('falls back to the Nerd Font glyph without an image backend', function()
    -- The test environment has no real-icons on the runtimepath, so no image is
    -- available and the plain glyph has to keep the footer readable.
    local segment = product.segment 'branch'
    expect.equality(false, segment.image)
    expect.equality(product.glyph 'branch', segment.text)
  end)
end)
