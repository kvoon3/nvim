# Vue & Treesitter

`.vue` once looked broken: only regex `syntax/vue.vim`, and `vue_ls` alone (no TS in `<script>`).

- **Highlighting**: treesitter runtime is in Neovim core; **parsers** (vue/ts/html/…) still need installing. We use archived [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) (2026-04) as a frozen installer + queries for 0.12 — see `lua/plugins/treesitter.lua`. Needs `tree-sitter-cli`.
- **LSP**: vue language tools v3 is **hybrid** — `vue_ls` for template/style, `ts_ls` + `@vue/typescript-plugin` with `vue` in filetypes for script. Don’t drop either. See `lua/config/lsp.lua` and [wiki](https://github.com/vuejs/language-tools/wiki/Neovim).
