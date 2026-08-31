# nvim

Kevin Kwong's Neovim configuration.

## Install

Requires [mise](https://mise.jdx.dev) (with its shell hook enabled) and **Neovim 0.12+**.

```sh
git clone https://github.com/kvoon3/nvim.git ~/.config/nvim
cd ~/.config/nvim
mise install
mise run prepare
```

Open Neovim once to install Lazy and Mason dependencies.

```sh
just check   # format, lint, and tests
just format  # apply formatting
```

Tests run with `mini.test` in an isolated Neovim data directory. The pre-commit hook checks staged Lua files with StyLua and Selene.

The eslint-codemod plugin has an extra integration suite backed by a real ESLint project in [`playground/eslint-codemod/`](playground/eslint-codemod). Run `pnpm install` once there; without it the suite stays green via a placeholder.

### Optional: macOS input-method switching

```sh
brew install daipeihust/tap/im-select
```

## Features

- **Editing:** Flash jumps, Treesitter-aware comments and JSDoc highlighting, surround editing, Markdown table formatting, enclosing-bracket highlights, pnpm catalog version hints, ESLint codemod autocomplete (`///` `// @` `/* @` triggers with fixability filtering via eslint-plugin-command), folds, CJK motions, and system clipboard helpers.
- **LSP:** Mason-managed Lua, TypeScript, Vue, web, Rust, spelling, and grammar servers; completion, snippets, formatting, linting with silent stylistic diagnostics, and ESLint fixes on save. References and friends use the built-in `grr`/`gri`/`grt`/`gra`/`grn` maps.
- **Navigation:** Telescope, Snacks file explorer, editable quickfix lists, mini.starter start screen with recent projects, and a command palette.
- **Git:** Gitsigns, floating LazyGit (`:lg`), GitHub links, and terminal-aware Git editing.
- **UI:** Lazy.nvim, macOS-aware light/dark themes, notifications, keybinding clues, theme-aware mini.statusline, winbar with an unsaved-change indicator, hidden-by-default line numbers with a command-palette toggle, and prose wrapping.

## Notes

- [Vue & Treesitter](notes/vue-treesitter.md) — Vue hybrid LSP and Treesitter context.
