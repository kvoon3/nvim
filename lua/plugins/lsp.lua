return {
  -- LSP configuration
  {
    'neovim/nvim-lspconfig',
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

  -- Useful status updates for LSP
  { 'j-hui/fidget.nvim', event = 'LspAttach', opts = {} },

  -- Autocompletion: Rust fuzzy matcher in-process via blink.cmp
  {
    'saghen/blink.cmp',
    version = '1.*',
    event = 'InsertEnter',
    dependencies = {
      -- Snippet engine and its bundled snippet collection
      {
        'L3MON4D3/LuaSnip',
        build = (function()
          if vim.fn.has 'win32' == 1 or vim.fn.executable 'make' == 0 then
            return nil
          end
          return 'make install_jsregexp'
        end)(),
        dependencies = { 'rafamadriz/friendly-snippets' },
        config = function()
          local luasnip = require 'luasnip'
          luasnip.config.setup {}
          require('luasnip.loaders.from_vscode').lazy_load()
          --[[ Snippets use LuaSnip; loading them here keeps them off the startup path. ]]
          require 'config.console-log'

          --[[ Hide generic console.log snippets that overlap local expression snippets. ]]
          local function configure_console_log_snippets()
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
          configure_console_log_snippets()
        end,
      },
    },
    opts = {
      keymap = {
        preset = 'none',
        ['<C-n>'] = { 'select_next', 'fallback' },
        ['<C-p>'] = { 'select_prev', 'fallback' },
        ['<C-b>'] = { 'scroll_documentation_up', 'fallback' },
        ['<C-f>'] = { 'scroll_documentation_down', 'fallback' },
        ['<C-Space>'] = { 'show', 'fallback' },
        --[[ Expand or jump a snippet first, then accept the selection. ]]
        ['<Tab>'] = { 'snippet_forward', 'select_and_accept', 'fallback' },
        --[[ No fallback: Ctrl-L only jumps snippets and is otherwise swallowed, as before. ]]
        ['<C-l>'] = { 'snippet_forward' },
        ['<C-h>'] = { 'snippet_backward', 'fallback' },
      },
      appearance = { nerd_font_variant = 'mono' },
      completion = {
        documentation = { auto_show = true, auto_show_delay_ms = 200 },
        ghost_text = { enabled = false },
      },
      snippets = { preset = 'luasnip' },
      --[[ Rust matcher; falls back to Lua only when the prebuilt binary is missing. ]]
      fuzzy = { implementation = 'prefer_rust' },
      sources = {
        default = { 'lazydev', 'eslint_codemod', 'lsp', 'path', 'snippets', 'buffer' },
        providers = {
          lazydev = {
            name = 'LazyDev',
            module = 'lazydev.integrations.blink',
            score_offset = 100,
          },
          eslint_codemod = {
            name = 'ESLint Codemod',
            module = 'eslint-codemod.blink-source',
          },
        },
      },
    },
  },
}
