# eslint-codemod playground

A real ESLint project for end-to-end testing of the
`lua/eslint-codemod/` plugin. The plugin's Node worker spawns against
the `eslint` and `eslint-plugin-command` installed here, so
fixability checks and diffs reflect the actual upstream behavior.

## Install

```sh
pnpm install
```

## Manual test

```sh
nvim example.ts
```

Then place the cursor on a trigger line:

| Cursor position           | Trigger char | Available commands            |
|---------------------------|--------------|-------------------------------|
| After `///`               | `/`          | `to-*`, `reverse-if-else`, …  |
| After `// @`              | `@`          | `keep-sorted`, `keep-unique`, `regex101` |
| After `// :`              | `:`          | (alias form, see config)      |
| Inside `/* @ … */`        | `@`          | `keep-*`, `regex101`          |

The cmp menu should show only the commands valid in that comment kind,
with the ones that are actually fixable in this file (per real ESLint)
listed first when `autocomplete.onlyFixable` is on.

Selecting an item with `autocomplete.autoFix = true` runs
`source.fixAll.eslint`, which applies the codemod and removes the
marker comment.

## CLI sanity check

```sh
npx eslint .            # see all 8 markers
npx eslint . --fix      # apply the 2 fixable ones
```

`to-ternary` and `reverse-if-else` should fix; the rest should report
"Unable to find …" because the marker is on the wrong line relative
to its target.

## Files

- `package.json` — `eslint` + `eslint-plugin-command` + `typescript`
  (TS is installed but unused; the example avoids TS-only syntax to
  skip `@typescript-eslint`)
- `eslint.config.mjs` — flat config with `command/command` rule
- `example.ts` — self-contained blocks, one per command
- `.gitignore` — `node_modules/`, `.eslintcache`

## Known worker bug

`--check-all` mode rewrites only the **first** `///` line for every
command it tests. In files that have multiple kinds of trigger
comments (e.g. both `///` and `// @keep-sorted`), the leftover
`// @keep-sorted` line still fires its own error and may be reported
as the result of the next command being tested. For a single
trigger per buffer, results are correct.
