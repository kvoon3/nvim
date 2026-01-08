return {
  "nvim-treesitter/nvim-treesitter",
  build = function()
    require("nvim-treesitter.install").update({ with_sync = true })()
  end,
  config = function()
    require("nvim-treesitter.configs").setup({
      ensure_installed = {
        "vue",
        "typescript",
        "tsx",
        "javascript",
        "html",
        "css",
        "scss",
        "json",
        "jsonc",
        "yaml",
        "markdown",
        "markdown_inline",
        "lua",
        "vim",
        "vimdoc"
      },
      auto_install = true,
      highlight = {
        enable = true,
        additional_vim_regex_highlighting = false,
      },
      indent = {
        enable = true
      },
      incremental_selection = {
        enable = true,
        keymaps = {
          init_selection = "<CR>",
          node_incremental = "<CR>",
          scope_incremental = "<TAB>",
          node_decremental = "<S-CR>",
        },
      },
    })
  end
}
