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
    dashboard = {
      enabled = true,
      sections = {
        { section = 'header' },
        { section = 'keys', gap = 1, padding = 1 },
        { section = 'startup' },
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
        -- We explicitly set position = "float" to override the global
        -- sidebar/right layout that would otherwise leak into this source.
        select = {
          layout = {
            preset = 'select',
            layout = {
              position = 'float',
            },
          },
        },
      },
      layout = {
        preset = 'sidebar',
        layout = {
          position = 'right',
        },
      },
    },
    terminal = {
      win = {
        style = 'float',
      },
    },
  },
  config = function(_, opts)
    require('snacks').setup(opts)

    require('cmdr').add {
      {
        desc = 'Open lazygit',
        cmd = function()
          Snacks.lazygit()
        end,
        cat = 'git',
      },
      {
        desc = 'Open dashboard',
        cmd = function()
          Snacks.dashboard.open()
        end,
        cat = 'snacks',
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
