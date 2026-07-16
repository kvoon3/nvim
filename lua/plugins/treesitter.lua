return {
  'nvim-treesitter/nvim-treesitter',
  lazy = false,
  build = ':TSUpdate',
  config = function()
    require('nvim-treesitter').setup {
      install_dir = vim.fn.stdpath 'data' .. '/site',
    }

    -- Parsers needed for Vue SFCs (script + template + style) and common langs.
    -- install() is async and a no-op when already present.
    require('nvim-treesitter').install {
      'vue',
      'typescript',
      'javascript',
      'tsx',
      'html',
      'css',
      'scss',
      'json',
      'lua',
      'luadoc',
      'vim',
      'vimdoc',
      'query',
      'markdown',
      'markdown_inline',
      'bash',
      'regex',
      'yaml',
      'toml',
      'rust',
    }

    -- Enable treesitter highlighting (and injection) for every filetype
    -- that has a parser. Vue SFCs need this for multi-language highlighting.
    vim.api.nvim_create_autocmd('FileType', {
      group = vim.api.nvim_create_augroup('TreesitterHighlight', { clear = true }),
      callback = function(ev)
        local ok = pcall(vim.treesitter.start, ev.buf)
        if not ok then
          return
        end

        -- Prefer treesitter folds when available (works with nvim-ufo).
        vim.wo.foldexpr = 'v:lua.vim.treesitter.foldexpr()'
        vim.wo.foldmethod = 'expr'
      end,
    })

    require('cmdr').add {
      {
        desc = 'Install treesitter parser for current filetype',
        cmd = function()
          local ft = vim.bo.filetype
          if ft == '' then
            vim.notify('No filetype detected', vim.log.levels.WARN)
            return
          end
          vim.cmd('TSInstall ' .. ft)
        end,
        cat = 'treesitter',
      },
      {
        desc = 'Update all treesitter parsers',
        cmd = '<CMD>TSUpdate<CR>',
        cat = 'treesitter',
      },
    }
  end,
}
