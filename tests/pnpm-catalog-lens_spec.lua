-- Headless mini.test spec for lua/pnpm-catalog-lens.lua.
-- Run all specs with: just test

local expect = require('mini.test').expect
local lens = require 'pnpm-catalog-lens'

describe('pnpm-catalog-lens', function()
  local function with_yaml(lines)
    local path = vim.fn.tempname() .. '.yaml'
    vim.fn.writefile(vim.split(lines, '\n'), path)
    return path
  end

  it('parses default and named catalogs', function()
    local catalogs = lens._parse_catalogs(with_yaml [[
packages:
  - 'packages/*'

catalog:
  react: ^18.2.0
  '@scope/pkg': "1.0.0"

catalogs:
  react17:
    react: ^17.0.2
    react-dom: ^17.0.2
]])

    expect.equality(catalogs.default, { react = '^18.2.0', ['@scope/pkg'] = '1.0.0' })
    expect.equality(catalogs.react17, { react = '^17.0.2', ['react-dom'] = '^17.0.2' })
  end)

  it('strips quotes and ignores comments and blank lines', function()
    local catalogs = lens._parse_catalogs(with_yaml [[
# a comment
catalog:
  vue: "^3.4.0" # trailing comment

  lodash: '^4.17.21'
]])

    expect.equality(catalogs.default, { vue = '^3.4.0', lodash = '^4.17.21' })
  end)

  it('resets when a new top-level section starts', function()
    local catalogs = lens._parse_catalogs(with_yaml [[
catalog:
  react: ^18.2.0
overrides:
  react: $react
]])

    expect.equality(catalogs.default, { react = '^18.2.0' })
    expect.equality(catalogs.overrides, nil)
  end)
end)
