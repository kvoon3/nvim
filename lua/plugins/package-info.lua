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

    -- Hover a dep line to show npm metadata (description, homepage, repo)
    -- ponytail: fetches on every K press; add a cache if registry latency annoys
    vim.keymap.set('n', 'K', function()
      if vim.fn.expand '%:t' ~= 'package.json' then
        return vim.lsp.buf.hover()
      end
      local name = vim.api.nvim_get_current_line():match '^%s*"(.-)"%s*:'
      if not name then
        return
      end
      vim.system(
        { 'npm', 'view', name, 'description', 'homepage', 'repository.url', '--json' },
        { text = true },
        function(res)
          if res.code ~= 0 then
            return
          end
          local data = vim.json.decode(res.stdout)
          local lines = {
            '# ' .. name,
            '',
            data.description or '',
            '',
            data.homepage or '',
            data['repository.url'] or '',
          }
          while lines[#lines] == '' do
            lines[#lines] = nil
          end
          vim.schedule(function()
            vim.lsp.util.open_floating_preview(lines, 'markdown', { focusable = false })
          end)
        end
      )
    end, { desc = 'Show npm metadata (package.json) or LSP hover' })

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
