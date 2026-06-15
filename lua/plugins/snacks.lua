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
          -- Preview the file under cursor in the main editor window,
          -- so its content is visible without pressing Enter.
          layout = {
            preset = "sidebar",
            preview = "main",
            layout = {
              position = "right",
            },
          },
          win = {
            list = {
              keys = {
                ["o"] = "confirm",
                ["O"] = "explorer_open",
              },
            },
          },
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
  config = function(_, opts)
    require("snacks").setup(opts)

    -- Auto-hide file explorer when focus moves into the editor
    local picker_fts = {
      snacks_picker_list = true,
      snacks_picker_input = true,
      snacks_picker_preview = true,
    }

    vim.api.nvim_create_autocmd("WinEnter", {
      group = vim.api.nvim_create_augroup("SnacksExplorerAutoHide", { clear = true }),
      callback = function()
        if picker_fts[vim.bo.filetype] then
          return
        end

        for _, picker in ipairs(Snacks.picker.get({ source = "explorer" })) do
          picker:close()
        end
      end,
    })
  end,
}
