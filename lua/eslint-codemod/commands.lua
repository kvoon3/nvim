local M = {}

--[[ Static builtin commands mirroring eslint-plugin-command.

  Each entry may specify `commentType`:
    - nil / "line"  -> only line comments (//, ///, // @, // :)
    - "block"       -> only block comments (/* @ */)
    - "both"        -> either

  The list is intentionally static so the nvim plugin has zero Node
  dependency for basic completion. The source of truth is
  `antfu/eslint-plugin-command/src/commands/`. To regenerate after
  upstream adds a new command:

    REF=main lua lua/eslint-codemod/scripts/generate-commands.lua \
      > lua/eslint-codemod/commands.lua

  The generator's `commentType` mapping is hand-curated (only
  `keep-sorted`, `keep-unique`, `regex101` are `both` upstream);
  update it there when upstream introduces a new non-line command.

  Alias is *not* stored here; it lives in config.alias and is
  expanded at completion time.
]]
M.builtin = {
  { name = 'hoist-regexp', commentType = 'line' },
  { name = 'inline-arrow', commentType = 'line' },
  { name = 'keep-aligned', commentType = 'line' },
  { name = 'keep-sorted', commentType = 'both' },
  { name = 'keep-unique', commentType = 'both' },
  { name = 'no-shorthand', commentType = 'line' },
  { name = 'no-type', commentType = 'line' },
  { name = 'no-x-above', commentType = 'line' },
  { name = 'regex101', commentType = 'both' },
  { name = 'reverse-if-else', commentType = 'line' },
  { name = 'to-arrow', commentType = 'line' },
  { name = 'to-destructuring', commentType = 'line' },
  { name = 'to-dynamic-import', commentType = 'line' },
  { name = 'to-for-each', commentType = 'line' },
  { name = 'to-for-of', commentType = 'line' },
  { name = 'to-function', commentType = 'line' },
  { name = 'to-one-line', commentType = 'line' },
  { name = 'to-promise-all', commentType = 'line' },
  { name = 'to-string-literal', commentType = 'line' },
  { name = 'to-template-literal', commentType = 'line' },
  { name = 'to-ternary', commentType = 'line' },
}

function M.get_all()
  return M.builtin
end

function M.find(name)
  for _, cmd in ipairs(M.builtin) do
    if cmd.name == name then
      return cmd
    end
  end

  return nil
end

return M
