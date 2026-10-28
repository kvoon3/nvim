return {
  'folke/snacks.nvim',
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
    lazygit = {
      enabled = true,
      configure = true,
    },
    picker = {
      sources = {
        explorer = {
          enabled = true,
          hidden = true, -- dotfiles
          ignored = true, -- gitignored (.git, etc.)
          -- Preview the file under cursor in the main editor window,
          -- so its content is visible without pressing Enter.
          layout = {
            preset = 'sidebar',
            preview = 'preview',
            layout = {
              position = 'right',
            },
          },
          win = {
            list = {
              keys = {
                ['o'] = 'confirm',
                ['O'] = 'explorer_open',
                ['%'] = 'explorer_add',
              },
            },
          },
        },
        -- Use a centered float modal for vim.ui.select confirmations
        -- (e.g. the "Delete ...?" prompt from Snacks explorer).
        select = {
          layout = {
            preset = 'select',
            layout = {
              position = 'float',
            },
          },
        },
      },
      --[[ No global `layout` here: it would leak into every source, turning files,
        grep, buffers, the command palette, and the colorscheme picker into right
        sidebars. The explorer keeps its own right/tree layout above. ]]
    },
    terminal = {
      win = {
        style = 'float',
      },
    },
  },
  config = function(_, opts)
    require('snacks').setup(opts)
    --[[ The explorer preview draws directory entries with Snacks' glyph icons;
run them through real-icons so the pane matches the file icon set. ]]
    require('picker-icons').setup()

    require('cmdr').add {
      {
        desc = 'Open lazygit',
        cmd = function()
          Snacks.lazygit()
        end,
        cat = 'git',
      },
      {
        desc = 'Show notification history',
        cmd = function()
          Snacks.notifier.show_history()
        end,
        cat = 'snacks',
      },
      {
        desc = 'Toggle file explorer',
        cmd = function()
          Snacks.picker.explorer()
        end,
        keys = { 'n', '<C-,>' },
        cat = 'snacks',
      },
    }

    -- Auto-hide file explorer when focus moves into the editor
    local picker_fts = {
      snacks_picker_list = true,
      snacks_picker_input = true,
      snacks_picker_preview = true,
    }

    vim.api.nvim_create_autocmd('WinEnter', {
      group = vim.api.nvim_create_augroup('SnacksExplorerAutoHide', { clear = true }),
      callback = function()
        if picker_fts[vim.bo.filetype] then
          return
        end

        for _, picker in ipairs(Snacks.picker.get { source = 'explorer' }) do
          picker:close()
        end
      end,
    })
  end,
}
