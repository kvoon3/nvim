return {
  "folke/snacks.nvim",
  priority = 1000,
  lazy = false,
  opts = {
    bigfile = { enabled = true },
    quickfile = { enabled = false },
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
      enabled = true,
      replace_netrw = false,
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
          enabled = true,
          show_hidden = true,
        }
      },
      layout = {
        preset = "sidebar",
        layout = {
          position = "right",
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
