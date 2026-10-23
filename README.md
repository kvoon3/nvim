# nvim

Kevin Kwong's Neovim configuration.

## Install

Requires [mise](https://mise.jdx.dev) (with its shell hook enabled) and **Neovim 0.12+**. Mermaid diagram rendering shells out to Node, which mise installs.

```sh
git clone https://github.com/kvoon3/nvim.git ~/.config/nvim
cd ~/.config/nvim
mise install
mise run prepare
```

Open Neovim once to install the Lazy plugins. LSP servers and linters are installed by mise from the
global manifest (`~/.config/mise/config.toml`), not by a Neovim plugin manager, because they run in
the edited project's directory.

```sh
just check   # format, lint, and tests
just format  # apply formatting
```

Tests run with `mini.test` in an isolated Neovim data directory. The pre-commit hook checks staged Lua files with StyLua and Selene.

The eslint-codemod plugin has an extra integration suite backed by a real ESLint project in [`playground/eslint-codemod/`](playground/eslint-codemod). Run `pnpm install` once there; without it the suite stays green via a placeholder.

### Optional: full-color file icons

Icons come from the [Catppuccin Icons](https://github.com/catppuccin/vscode-icons) VS Code
extension, rendered by [real-icons.nvim](https://github.com/Mirsmog/real-icons.nvim) through the
Kitty Graphics Protocol. Install the extension in VS Code, then let real-icons convert it:

```sh
brew install librsvg   # rsvg-convert; ImageMagick's own SVG renderer cannot draw these icons
:lua require('catppuccin-icons').build { force = true }
```

Without both pieces, or outside Kitty/Ghostty, icons fall back to mini.icons glyphs.

### Optional: macOS input-method switching

```sh
brew install daipeihust/tap/im-select
```

### Optional: inline translation

Inline translation calls OpenRouter, so it needs an API key:

```sh
export OPENROUTER_API_KEY=sk-or-v1-...
```

If unset, the `openrouter` token in `~/.pi/agent/auth.json` is reused. Enable it from the command palette (`Translate: toggle inline translation`): paragraphs in the visible part of the buffer get a Chinese translation as virtual lines underneath, and the rest is translated lazily while scrolling. Translations are cached in `stdpath('cache')/inline-translate`; `Translate: clear translation cache` drops them. Override the model with `INLINE_TRANSLATE_MODEL`.

## Features

- **Editing:** Flash jumps, Treesitter-aware comments and JSDoc highlighting, surround editing, Markdown table formatting, Mermaid diagram rendering, enclosing-bracket highlights, pnpm catalog version hints, ESLint codemod autocomplete (`///` `// @` `/* @` triggers with fixability filtering via eslint-plugin-command), folds, CJK motions, and system clipboard helpers.
- **LSP:** mise-managed Lua, TypeScript, Vue, web, Rust, spelling, and grammar servers; TS/JS runs on `tsrs` (TypeScript 7 in Rust), projects that pin TypeScript 7.1+ in `node_modules` use that native `tsc` instead (content mappers only behind a `.nvim-content-mappers` marker), and the fallback is the project's `tsserver` (`touch .nvim-tsserver` forces it), Vue keeps `ts_ls` + `@vue/typescript-plugin`; completion via blink.cmp with its Rust fuzzy matcher, LuaSnip snippets, formatting, linting with silent stylistic diagnostics, and ESLint fixes on save. References and friends use the built-in `grr`/`gri`/`grt`/`gra`/`grn` maps, and eagle.nvim pops a float with diagnostics plus LSP hover info when the mouse rests on a symbol (or on `:EagleWin`).
- **Navigation:** `gd` follows Markdown links, wiki links, and anchors (falling back to LSP definitions), Snacks pickers for files, grep, buffers, help, TODOs, and colorschemes (with previews and jump-to-source), Snacks file explorer, editable quickfix lists, mini.starter start screen with recent projects, and a command palette.
- **Git:** Gitsigns, floating LazyGit (`:lg`), GitHub links, and terminal-aware Git editing.
- **UI:** Lazy.nvim, macOS-aware light/dark themes, theme-tinted undo-glow feedback for undo, redo, paste, search, yanks, and comments, notifications, keybinding clues, theme-aware mini.statusline with the project TODO count, winbar with an unsaved-change indicator, hidden-by-default line numbers with a command-palette toggle, cursor smear animation with a command-palette toggle, tiny-inline-diagnostic.nvim for inline diagnostic messages, full-color Catppuccin file icons in pickers, the explorer, and the statusline, and prose wrapping.
- **Reading:** lazy bilingual inline translation (OpenRouter `gemini-2.5-flash-lite`) for Markdown and prose buffers, rendered as virtual lines under the paragraphs currently on screen.
- **Performance:** ~40ms startup; word motions use the Rust jieba segmenter only in buffers that actually contain CJK text (builtin Vim motions elsewhere, with a token cap for huge lines); buffers holding very long lines (minified/generated files) opt out of LSP, Treesitter highlighting and `virtcol()`-based statusline items, and the statusline TODO search is throttled per project and requires a project marker.

## Notes

- [Vue & Treesitter](notes/vue-treesitter.md) — Vue hybrid LSP and Treesitter context.
- [Performance](notes/performance.md) — startup budget, jieba/Rust segmentation, and the big-file guards.
