return {
  "folke/snacks.nvim",
  priority = 1000,
  lazy = false,
  opts = {
    bigfile = { enabled = true },
    quickfile = { enabled = true },
    indent = { enabled = false },
    scroll = { enabled = false },
    statuscolumn = { enabled = true },
    notifier = { 
      enabled = true,
      timeout = 3000,
    },
    input = { enabled = true },
    words = { enabled = true },
    scope = { enabled = true },
    explorer = {
      replace_netrw = true,
      trash = true,
    },
    dashboard = {
      enabled = true,
      sections = {
        { section = "header" },
        { section = "keys", gap = 1, padding = 1 },
        { section = "startup" },
      },
    },
    lazygit = {
      enabled = true,
      configure = true,
    },
    picker = {
      sources = {
        explorer = {
          show_hidden = true,
        }
      }
    },
    terminal = {
      win = {
        style = "float",
      },
    },
  },
}
