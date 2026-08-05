return {
  'vuki656/package-info.nvim',
  dependencies = { 'MunifTanjim/nui.nvim' },
  ft = 'json',
  config = function()
    local pi = require 'package-info'
    pi.setup()

    -- Re-run on each package.json since the plugin only attaches to the
    -- current buffer at setup time
    vim.api.nvim_create_autocmd('BufRead', {
      pattern = 'package.json',
      callback = function()
        pi.show()
      end,
    })

    vim.keymap.set('n', 'K', function()
      if vim.fn.expand '%:t' == 'package.json' then
        pi.show()
      else
        vim.lsp.buf.hover()
      end
    end, { desc = 'Show package info (package.json) or LSP hover' })

    require('cmdr').add {
      {
        desc = 'Show package versions',
        cmd = function()
          pi.show()
        end,
        cat = 'package',
      },
      {
        desc = 'Hide package versions',
        cmd = function()
          pi.hide()
        end,
        cat = 'package',
      },
      {
        desc = 'Update package under cursor',
        cmd = function()
          pi.update()
        end,
        cat = 'package',
      },
      {
        desc = 'Change package version',
        cmd = function()
          pi.change_version()
        end,
        cat = 'package',
      },
      {
        desc = 'Install a new package',
        cmd = function()
          pi.install()
        end,
        cat = 'package',
      },
    }
  end,
}
