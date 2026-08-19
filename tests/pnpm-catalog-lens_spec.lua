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

  it('conceals the catalog protocol with a padded version badge', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    vim.fn.writefile(
      { 'catalog:', '  react: ^18.2.0', 'catalogs:', '  react17:', '    react-dom: ^17.0.2' },
      dir .. '/pnpm-workspace.yaml'
    )
    local manifest = dir .. '/package.json'
    vim.fn.writefile(
      { '{', '  "dependencies": {', '    "react": "catalog:",', '    "react-dom": "catalog:react17"', '  }', '}' },
      manifest
    )

    local bufnr = vim.fn.bufadd(manifest)
    vim.fn.bufload(bufnr)
    lens.refresh(bufnr)

    local ns = vim.api.nvim_create_namespace 'pnpm_catalog_lens'
    local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
    expect.equality(#marks, 2)

    local default = marks[1]
    expect.equality(default[2], 2) -- row of the react line, 0-indexed
    expect.equality(default[4].end_col - default[3], #'catalog:') -- concealed range covers the protocol
    expect.equality(default[4].conceal, '')
    expect.equality(default[4].virt_text, { { ' ^18.2.0 ', 'PnpmCatalogLens' } })

    local badge = vim.api.nvim_get_hl(0, { name = 'PnpmCatalogLens' })
    expect.equality(badge.fg, tonumber('f69220', 16))
    assert(badge.bg ~= nil, 'badge should have a background color')

    -- Named catalogs: version badge first, then the catalog name (VS Code layout).
    local named = marks[2]
    expect.equality(named[4].virt_text, {
      { ' ^17.0.2 ', 'PnpmCatalogLens_react17' },
      { ' react17', 'PnpmCatalogLens_react17Label' },
    })
  end)

  it('colors the default catalog pnpm orange and named catalogs deterministically', function()
    expect.equality(lens._catalog_color 'default', '#f69220')

    local named = lens._catalog_color 'react17'
    expect.equality(named, lens._catalog_color 'react17') -- stable
    assert(named:match '^#%x%x%x%x%x%x$', named)
    assert(named ~= lens._catalog_color 'default')
    assert(named ~= lens._catalog_color 'react18')
  end)
end)
