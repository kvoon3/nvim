return {
  -- LSP configuration
  {
    'neovim/nvim-lspconfig',
    dependencies = {
      -- Install/update LSP servers, DAP servers, linters, and formatters
      { 'williamboman/mason.nvim', config = true },
      'williamboman/mason-lspconfig.nvim',

      -- Useful status updates for LSP
      { 'j-hui/fidget.nvim', opts = {} },

      -- LuaLS library for Neovim/plugin APIs (replaces neodev)
      {
        'folke/lazydev.nvim',
        ft = 'lua',
        opts = {
          library = {
            { path = '${3rd}/luv/library', words = { 'vim%.uv' } },
          },
        },
      },
    },
    config = function()
      vim.api.nvim_create_user_command('ReloadLsp', function()
        vim.cmd 'lsp restart'
      end, {})

      require('cmdr').add {
        {
          desc = 'LSP: reload all language servers',
          cmd = '<CMD>ReloadLsp<CR>',
          cat = 'lsp',
        },
      }
    end,
  },

  -- Autocompletion
  {
    'hrsh7th/nvim-cmp',
    dependencies = {
      -- Snippet Engine & its associated nvim-cmp source
      {
        'L3MON4D3/LuaSnip',
        build = (function()
          if vim.fn.has 'win32' == 1 or vim.fn.executable 'make' == 0 then
            return nil
          end
          return 'make install_jsregexp'
        end)(),
        dependencies = { 'rafamadriz/friendly-snippets' },
      },
      'saadparwaiz1/cmp_luasnip',

      -- Adds other completion capabilities.
      'hrsh7th/cmp-nvim-lsp',
      'hrsh7th/cmp-path',
      'hrsh7th/cmp-buffer',
    },
    config = function()
      local cmp = require 'cmp'
      local luasnip = require 'luasnip'
      luasnip.config.setup {}
      local function configure_console_log_snippets()
        --[[ Hide generic console.log snippets that overlap local expression snippets. ]]
        for _, ft in ipairs { 'javascript', 'javascriptreact', 'vue', 'svelte' } do
          for _, snippet in ipairs(luasnip.get_snippets(ft)) do
            if snippet.name == 'console.log' and snippet.trigger == 'cl' then
              snippet.hidden = true
            elseif snippet.name == 'console.log with log' and snippet.trigger == 'log' then
              snippet.show_condition = function(line)
                return not line:match '%.%w*$'
              end
            end
          end
        end
      end
      vim.api.nvim_create_autocmd('User', {
        pattern = 'LuasnipSnippetsAdded',
        callback = configure_console_log_snippets,
      })
      require('luasnip.loaders.from_vscode').lazy_load()
      configure_console_log_snippets()

      cmp.setup {
        snippet = {
          expand = function(args)
            luasnip.lsp_expand(args.body)
          end,
        },
        completion = { completeopt = 'menu,menuone,noinsert' },
        formatting = {
          format = function(entry, vim_item)
            if entry.source.name == 'luasnip' and entry.completion_item and entry.completion_item.data then
              local ok, snip = pcall(require('luasnip').get_id_snippet, entry.completion_item.data.snip_id)
              if ok and snip and snip.name then
                vim_item.abbr = snip.name
              end
            end
            return vim_item
          end,
        },
        mapping = cmp.mapping.preset.insert {
          ['<C-n>'] = cmp.mapping.select_next_item(),
          ['<C-p>'] = cmp.mapping.select_prev_item(),
          ['<C-b>'] = cmp.mapping.scroll_docs(-4),
          ['<C-f>'] = cmp.mapping.scroll_docs(4),
          ['<C-Space>'] = cmp.mapping.complete {},
          ['<Tab>'] = cmp.mapping(function(fallback)
            if luasnip.expandable() then
              luasnip.expand()
            elseif cmp.visible() then
              cmp.confirm { select = true }
            else
              fallback()
            end
          end, { 'i', 's' }),
          ['<C-l>'] = cmp.mapping(function()
            if luasnip.expand_or_locally_jumpable() then
              luasnip.expand_or_jump()
            end
          end, { 'i', 's' }),
          ['<C-h>'] = cmp.mapping(function()
            if luasnip.locally_jumpable(-1) then
              luasnip.jump(-1)
            end
          end, { 'i', 's' }),
        },
        sources = {
          { name = 'lazydev', group_index = 0 },
          { name = 'nvim_lsp' },
          { name = 'luasnip' },
          { name = 'path' },
          { name = 'buffer' },
        },
      }
    end,
  },
}
