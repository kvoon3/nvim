-- Native LSP configuration (replaces coc.nvim)
-- Add servers you install via Mason to the `ensure_installed` list below.

vim.api.nvim_create_autocmd('LspAttach', {
  group = vim.api.nvim_create_augroup('UserLspConfig', {}),
  callback = function(ev)
    -- Enable completion triggered by <c-x><c-o>
    vim.bo[ev.buf].omnifunc = 'v:lua.vim.lsp.omnifunc'

    -- Buffer local mappings.
    local opts = { buffer = ev.buf }
    vim.keymap.set('n', 'gD', vim.lsp.buf.declaration, opts)
    vim.keymap.set('n', 'gd', vim.lsp.buf.definition, opts)
    vim.keymap.set('n', 'gh', vim.lsp.buf.hover, opts)
    vim.keymap.set('n', 'gi', vim.lsp.buf.implementation, opts)
    vim.keymap.set('n', '<C-k>', vim.lsp.buf.signature_help, opts)
    vim.keymap.set('n', '<leader>wa', vim.lsp.buf.add_workspace_folder, opts)
    vim.keymap.set('n', '<leader>wr', vim.lsp.buf.remove_workspace_folder, opts)
    vim.keymap.set('n', '<leader>wl', function()
      print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
    end, opts)
    vim.keymap.set('n', 'gt', vim.lsp.buf.type_definition, opts)
    vim.keymap.set('n', '<leader>rn', vim.lsp.buf.rename, opts)
    vim.keymap.set({ 'n', 'v' }, '<leader>ca', vim.lsp.buf.code_action, opts)
    vim.keymap.set('n', 'gr', vim.lsp.buf.references, opts)
    vim.keymap.set('n', '<leader>f', function()
      vim.lsp.buf.format { async = true }
    end, opts)

    -- ponytail: format-on-save for Rust, sync so write waits for fmt
    if vim.bo[ev.buf].filetype == 'rust' then
      vim.api.nvim_create_autocmd('BufWritePre', {
        buffer = ev.buf,
        callback = function()
          vim.lsp.buf.format { async = false }
        end,
      })
    end
  end,
})

-- Diagnostic keymaps
vim.keymap.set('n', '[d', vim.diagnostic.goto_prev, { desc = 'Go to previous diagnostic' })
vim.keymap.set('n', ']d', vim.diagnostic.goto_next, { desc = 'Go to next diagnostic' })
vim.keymap.set('n', '<leader>en', function()
  vim.diagnostic.goto_next({ severity = vim.diagnostic.severity.ERROR })
end, { desc = 'Go to next error' })
vim.keymap.set('n', '<leader>df', vim.diagnostic.open_float, { desc = 'Open diagnostic float' })
vim.keymap.set('n', '<leader>q', vim.diagnostic.setloclist, { desc = 'Open diagnostics list' })

-- Mason setup
require('mason').setup()

-- Configure servers here.
-- Servers listed in `ensure_installed` will be installed automatically by Mason.
local servers = {
  lua_ls = {
    settings = {
      Lua = {
        completion = { callSnippet = 'Replace' },
        diagnostics = { disable = { 'missing-fields' } },
      },
    },
  },
  -- Vue / JS / TS
  ts_ls = {},
  vue_ls = {},

  -- CSS / HTML
  cssls = {},
  html = {},

  -- Rust
  rust_analyzer = {},
}

local ensure_installed = vim.tbl_keys(servers or {})

require('mason-lspconfig').setup {
  ensure_installed = ensure_installed,
  automatic_enable = false, -- we enable servers manually below
}

local capabilities = require('cmp_nvim_lsp').default_capabilities()

for server_name, server in pairs(servers) do
  server.capabilities = capabilities
  vim.lsp.config(server_name, server)
  vim.lsp.enable(server_name)
end

-- UnoCSS language server (installed via npm, not Mason)
vim.lsp.config('unocss', {
  capabilities = capabilities,
})
vim.lsp.enable('unocss')
