# nvim

Kevin Kwong's Neovim config.

## Install

Requires [mise](https://mise.jdx.dev) (shell hook / `mise activate`). Optional macOS: `brew install daipeihust/tap/im-select`.

```sh
git clone https://github.com/kvoon3/nvim.git ~/.config/nvim
cd ~/.config/nvim
mise install      # stylua, selene, just, …
mise run prepare  # install .githooks/pre-commit → .git/hooks/
```

Open nvim once for Lazy/Mason. Pre-commit: stylua --check + selene on staged `*.lua`. Full tree: `just check`.

## Features

### Editing

- **Fast jump**: [flash.nvim](https://github.com/folke/flash.nvim) for quick character-level navigation.
- **Jump to errors**: Navigate diagnostics (`[d` / `]d` / `<leader>en` / `<leader>wn` / `<leader>in` / `<leader>hn`), open diagnostic float (`<leader>df`), and diagnostics list (`<leader>q`).
- **Mouse support**: Full mouse support for clicking to position the cursor, selecting text, scrolling, and more.
- **Auto-pairs & surround**: Automatic bracket pairing and [nvim-surround](https://github.com/kylechui/nvim-surround) for changing surrounding characters.
- **Enhanced commenting**: [ts-comments.nvim](https://github.com/folke/ts-comments.nvim) for context-aware line/block comments.
- **Code folding**: [nvim-ufo](https://github.com/kevinhwang91/nvim-ufo) with fold level keymaps (`zR`, `zM`, `zr`, `zm`).
- **System clipboard**: Paste from system clipboard via `<leader>p`.
- **Select all**: `<leader>a` selects the entire buffer.

CJK Text Enhancement:

- **Word Split**: [jieba](https://github.com/neo451/jieba-lua)-powered `w`/`b`/`e` motions for Chinese and mixed-language text.
- **Input method auto-switch**: Optional `im-select` integration that switches input methods automatically when leaving/entering insert mode on macOS.

### LSP & Completion

- **Language servers**: [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig) + [Mason](https://github.com/williamboman/mason.nvim) manage `lua_ls`, `ts_ls`, `vue_ls`, `cssls`, `html`, `unocss`, and `rust_analyzer`.
- **Vue hybrid mode**: `vue_ls` (template/style) + `ts_ls` with `@vue/typescript-plugin` (`<script>` TS). Context: [notes/vue-treesitter.md](notes/vue-treesitter.md).
- **Autocompletion**: [nvim-cmp](https://github.com/hrsh7th/nvim-cmp) with LSP, LuaSnip, path, and buffer sources.
- **Snippets**: [LuaSnip](https://github.com/L3MON4D3/LuaSnip) with `<C-l>` / `<C-h>` jump mappings.
- **LSP actions**: Go to definition/references (`gd`, `gr`), hover (`gh`), rename (`<leader>rn`), code actions (`<leader>ca`), and format (`<leader>f`).
- **Run on save**: `.nvim/settings.json` → `runOnSave: { "<glob>": string[] }` (shell cmds, sequential). `${{filepath}}` = saved file path.

### Syntax & Treesitter

- **Treesitter**: [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) installs parsers; core `vim.treesitter.start()` does highlighting. Context: [notes/vue-treesitter.md](notes/vue-treesitter.md).

### Finding & Exploring

- **Fuzzy finding**: [Telescope](https://github.com/nvim-telescope/telescope.nvim) for files (`<C-p>`), live grep (`<leader>ff`), buffers (`<leader>fb`), help tags (`<leader>fh`), and colorschemes (`<leader>cs`).
- **File explorer**: [snacks.nvim](https://github.com/folke/snacks.nvim) `explorer` with a right-side sidebar, hidden files, and live preview. Delete/move confirmations use a centered float modal.
- **Command palette**: [commander.nvim](https://github.com/FeiyouG/commander.nvim) accessible with `<C-S-p>` or `<leader>cc`.
- **Dashboard**: Snacks startup dashboard on launch.

### Git

- **Inline Git signs**: [gitsigns.nvim](https://github.com/lewis6991/gitsigns.nvim) for blame, diff, and hunk actions.
- **Visual diff**: [codediff.nvim](https://github.com/esmuellert/codediff.nvim) opens a VSCode-style diff explorer with `:CodeDiff`. Use `<leader>gd` for git status, `<leader>gD` to diff the current file against `HEAD`, and `<leader>gh` for file history. All commands are also available in the commander palette.
- **LazyGit**: Open a floating LazyGit terminal with `<leader>lg` or the `:Lazygit` command.
- **Open in GitHub**: `<leader>go` opens the current file, selection, or repository in GitHub in your default browser.
- **Git-aware terminal**: [flatten.nvim](https://github.com/willothy/flatten.nvim) opens files from inside terminal buffers in the current Neovim instance and handles `git commit`/`git rebase` smoothly.

### Panel Management

- **Smart panel toggles**: `<C-w>l` toggles the right file-explorer panel; `<C-w>j` toggles the bottom terminal panel.
- **Toggle terminal**: [toggleterm.nvim](https://github.com/akinsho/toggleterm.nvim) with `<C-t>`, numbered terminals (`<leader>1/2/3`), and terminal-window navigation.
- **Auto-hide panels**: Side (file explorer) and bottom (terminal) panels automatically close when focus moves back to the main editor.

### UI & Themes

- **Plugin management**: [lazy.nvim](https://github.com/folke/lazy.nvim) for fast, declarative plugin loading.
- **Auto dark mode**: [auto-dark-mode.nvim](https://github.com/f-person/auto-dark-mode.nvim) switches between vitesse-light-soft (light) and vitesse-black (dark) based on macOS appearance.
- **Color schemes**: [Vitesse](https://github.com/kvoon3/vitesse.nvim), [Everforest](https://github.com/neanias/everforest-nvim), [Kanagawa](https://github.com/rebelot/kanagawa.nvim), [moonfly](https://github.com/bluz71/vim-moonfly-colors), and [olive-crt](https://github.com/torgeir/olive-crt.nvim).
- **Notifications & input**: Snacks notifier and input UI replace default message boxes.
- **Statusline**: Custom minimal statusline showing filename, modified flag, and cursor position.
- **Markdown rendering**: [render-markdown.nvim](https://github.com/MeanderingProgrammer/render-markdown.nvim) with toggle commands.

### Others

- **Coding time tracking**: [vim-wakatime](https://github.com/wakatime/vim-wakatime) integration.

## Notes

- [Vue & Treesitter](notes/vue-treesitter.md) — why hybrid LSP + archived nvim-treesitter
