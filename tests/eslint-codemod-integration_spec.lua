-- Integration tests for the eslint-codemod plugin against a real
-- ESLint installation in `playground/`. Skipped if the playground
-- hasn't been installed (no `node_modules`).
--
-- Enable by running:
--   cd playground && pnpm install
--   just test
--
-- These tests are slower than the unit tests in
-- eslint-codemod_spec.lua (each test spawns `node`) but validate the
-- contract between the Lua worker bridge and the Node `lint.mjs`:
--   - fixable commands return `fixable: true`
--   - non-fixable commands return `fixable: false`
--
-- Tests live in their own file so the suite still passes in
-- environments where the playground is not installed (CI, fresh
-- clones, etc.).

local expect = require('mini.test').expect

--[[ Resolve paths relative to the project root (parent of `tests/`),
  not relative to the running script — `debug.getinfo` returns
  `[string ":lua"]` when sourced via `-c lua ...`, which has no
  usable directory. ]]
local function project_root()
  local src = debug.getinfo(1, 'S').source:sub(2)
  if src:sub(1, 1) == '/' then
    return vim.fn.fnamemodify(src, ':h:h')
  end

  --[[ Fall back to cwd; mini.test runs from the project root. ]]
  return vim.fn.getcwd()
end

local PLAYGROUND = project_root() .. '/playground/eslint-codemod'
local HAS_PLAYGROUND = vim.fn.isdirectory(PLAYGROUND .. '/node_modules/eslint') == 1
  and vim.fn.executable 'node' == 1
  and vim.fn.filereadable(PLAYGROUND .. '/example.ts') == 1

describe('eslint-codemod integration', function()
  if not HAS_PLAYGROUND then
    --[[ No-op test so the suite stays green when the playground is
      absent. Run `cd playground && pnpm install` to enable the real
      integration checks below. ]]
    it('is skipped (playground/node_modules not present)', function()
      expect.equality(PLAYGROUND, PLAYGROUND)
    end)

    return
  end

  local lint

  before_each(function()
    package.loaded['eslint-codemod.lint'] = nil
    lint = require 'eslint-codemod.lint'
  end)

  it('check_fixable_batch agrees with real eslint on example.ts', function()
    local bufnr = vim.api.nvim_create_buf(true, false)
    --[[ Set the buffer name so vim.fs.root can locate the
      playground's eslint config (no name = no root). ]]
    vim.api.nvim_buf_set_name(bufnr, PLAYGROUND .. '/example.ts')
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.fn.readfile(PLAYGROUND .. '/example.ts'))
    vim.bo[bufnr].filetype = 'typescript'

    local done, map = false, nil
    lint.check_fixable_batch(
      { 'to-ternary', 'reverse-if-else', 'to-arrow', 'to-function' },
      { bufnr = bufnr, row = 0 },
      function(m)
        map, done = m, true
      end
    )
    vim.wait(5000, function()
      return done
    end)

    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end

    assert(done, 'callback should fire within 2s')
    --[[ to-ternary and reverse-if-else have valid structures. ]]
    if map['to-ternary'] ~= true or map['reverse-if-else'] ~= true then
      error('unexpected fixable map: ' .. vim.inspect(map))
    end

    expect.equality(true, map['to-ternary'])
    expect.equality(true, map['reverse-if-else'])
    --[[ to-arrow / to-function have no valid target. ]]
    expect.equality(false, map['to-arrow'])
    expect.equality(false, map['to-function'])
  end)
end)
