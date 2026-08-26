#!/usr/bin/env lua
--[[ Regenerate `commands.lua` builtin table from
  `antfu/eslint-plugin-command` source on GitHub.

  Each command is a TS file under `src/commands/<name>.ts` exporting
  `default { meta: { commentType?: 'line' | 'block' | 'both' } }`.
  We only need `name` + `commentType`, so a directory listing via
  the GitHub Contents API is enough.

  Usage:
    GITHUB_TOKEN=ghp_... lua lua/eslint-codemod/scripts/generate-commands.lua \
      > lua/eslint-codemod/commands.lua
    # pin a ref:
    REF=v0.6.0 lua lua/eslint-codemod/scripts/generate-commands.lua

  Requires Neovim (uses vim.system + vim.jsondecode).
]]

local REF = os.getenv 'REF' or 'main'
local REPO = 'antfu/eslint-plugin-command'
local API = string.format('https://api.github.com/repos/%s/contents/src/commands?ref=%s', REPO, REF)

if not (vim and vim.system) then
  vim.api.nvim_err_writeln 'requires Neovim (uses vim.system + vim.jsondecode)'
  os.exit(1)
end

local args = { 'curl', '-fsSL' }
local token = os.getenv 'GITHUB_TOKEN'
if token and token ~= '' then
  table.insert(args, '-H')
  table.insert(args, 'Authorization: Bearer ' .. token)
end

table.insert(args, API)

local res = vim.system(args, { text = true }):wait()
if res.code ~= 0 then
  vim.api.nvim_err_writeln(
    'curl failed (HTTP '
      .. tostring(res.code)
      .. '). The unauthenticated GitHub API is rate-limited; set GITHUB_TOKEN to regenerate.\n'
      .. (res.stderr or '')
      .. '\n'
  )
  os.exit(1)
end

local ok, entries = pcall(vim.fn.jsondecode, res.stdout)
if not ok or type(entries) ~= 'table' then
  vim.api.nvim_err_writeln 'invalid json'
  os.exit(1)
end

local names = {}
for _, entry in ipairs(entries) do
  if entry.type == 'file' and entry.name:match '%.ts$' then
    table.insert(names, entry.name:gsub('%.ts$', ''))
  end
end

table.sort(names)

--[[ We default to 'line'; `block`/`both` are hand-curated for the
  three commands that the upstream meta file actually marks as
  non-line. Keep the list minimal — adding a new `both` here
  without a known mapping risks silently expanding triggers. ]]
local function comment_type_for(name)
  if name == 'keep-sorted' or name == 'keep-unique' or name == 'regex101' then
    return 'both'
  end

  return 'line'
end

io.write '--[[ THIS FILE IS GENERATED. DO NOT EDIT.\n'
io.write '  Run scripts/generate-commands.lua to regenerate. ]]\n'
io.write 'local M = {}\n\n'
io.write 'M.builtin = {\n'
for _, name in ipairs(names) do
  io.write(string.format("  { name = '%s', commentType = '%s' },\n", name, comment_type_for(name)))
end
io.write '}\n\n'
io.write 'function M.get_all() return M.builtin end\n\n'
io.write 'function M.find(name)\n'
io.write '  for _, cmd in ipairs(M.builtin) do\n'
io.write '    if cmd.name == name then return cmd end\n'
io.write '  end\n'
io.write '  return nil\n'
io.write 'end\n\n'
io.write 'return M\n'
