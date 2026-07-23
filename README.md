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

### Optional: macOS input-method switching

```sh
brew install daipeihust/tap/im-select
```

## Features

- **Editing:** Flash jumps, Treesitter-aware comments, surround editing, enclosing-bracket highlights, folds, CJK motions, and system clipboard helpers.
- **LSP:** Mason-managed Lua, TypeScript, Vue, web, and Rust servers; completion, snippets, formatting, linting with silent stylistic diagnostics, and ESLint fixes on save.
- **Navigation:** Telescope, Snacks file explorer and dashboard, plus a command palette.
- **Git:** Gitsigns, floating LazyGit (`:lg`), GitHub links, and terminal-aware Git editing.
- **UI:** Lazy.nvim, macOS-aware light/dark themes, notifications, mini.statusline, winbar with an unsaved-change indicator, and prose wrapping.

## Notes

- [Vue & Treesitter](notes/vue-treesitter.md) — Vue hybrid LSP and Treesitter context.
