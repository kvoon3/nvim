-- Native LSP configuration (replaces coc.nvim)
-- Add servers you install via Mason to the `ensure_installed` list below.

local typescript = require 'config.typescript'

vim.api.nvim_create_autocmd('LspAttach', {
  group = vim.api.nvim_create_augroup('UserLspConfig', {}),
  callback = function(ev)
    local client = vim.lsp.get_client_by_id(ev.data.client_id)
    if client then
      typescript.track(client)
    end

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

-- Diagnostic navigation (goto_next/goto_prev are deprecated; use jump)
vim.diagnostic.config {
  virtual_text = true,
  signs = true,
  underline = true,
  update_in_insert = false,
  jump = {
    on_jump = function(_, bufnr)
      vim.diagnostic.open_float { bufnr = bufnr, scope = 'cursor', focus = false }
    end,
  },
}

local function clear_diag_virtual_text_bg()
  --[[ Preserve linked foreground colors while making diagnostic virtual text transparent. ]]
  for _, severity in ipairs { 'Error', 'Warn', 'Info', 'Hint' } do
    local group = 'DiagnosticVirtualText' .. severity
    local link_to = 'Diagnostic' .. severity
    local fg = vim.api.nvim_get_hl(0, { name = link_to, link = false }).fg
    vim.api.nvim_set_hl(0, group, { fg = fg, bg = 'NONE' })
  end
end
clear_diag_virtual_text_bg()
vim.api.nvim_create_autocmd('ColorScheme', {
  group = vim.api.nvim_create_augroup('DiagVirtualTextBg', {}),
  callback = clear_diag_virtual_text_bg,
})

local function jump_diagnostic(count, severity)
  return function()
    vim.diagnostic.jump { count = count, severity = severity }
  end
end

vim.keymap.set('n', '[d', jump_diagnostic(-1), { desc = 'Go to previous diagnostic' })
vim.keymap.set('n', ']d', jump_diagnostic(1), { desc = 'Go to next diagnostic' })
vim.keymap.set('n', '<leader>en', jump_diagnostic(1, vim.diagnostic.severity.ERROR), { desc = 'Go to next error' })
vim.keymap.set('n', '<leader>wn', jump_diagnostic(1, vim.diagnostic.severity.WARN), { desc = 'Go to next warning' })
vim.keymap.set('n', '<leader>in', jump_diagnostic(1, vim.diagnostic.severity.INFO), { desc = 'Go to next info' })
vim.keymap.set('n', '<leader>hn', jump_diagnostic(1, vim.diagnostic.severity.HINT), { desc = 'Go to next hint' })
vim.keymap.set('n', '<leader>df', vim.diagnostic.open_float, { desc = 'Open diagnostic float' })
vim.keymap.set('n', '<leader>q', vim.diagnostic.setloclist, { desc = 'Open diagnostics list' })

-- Mason setup
require('mason').setup()

-- Configure servers here.
-- Servers listed in `ensure_installed` will be installed automatically by Mason.
--
-- Vue hybrid mode (vue_ls v3+):
--   vue_ls owns HTML/CSS in .vue files;
--   ts_ls (+ @vue/typescript-plugin) owns <script> TS/JS and must attach to vue ft.
-- See: https://github.com/vuejs/language-tools/wiki/Neovim
local vue_language_server_path = vim.fn.expand '$MASON/packages/vue-language-server/node_modules/@vue/language-server'
if vim.fn.isdirectory(vue_language_server_path) == 0 then
  vue_language_server_path = vim.fn.stdpath 'data'
    .. '/mason/packages/vue-language-server/node_modules/@vue/language-server'
end

local vue_plugin = {
  name = '@vue/typescript-plugin',
  location = vue_language_server_path,
  languages = { 'vue' },
  configNamespace = 'typescript',
}

local eslint_on_attach = vim.lsp.config.eslint.on_attach

local servers = {
  lua_ls = {
    settings = {
      Lua = {
        completion = { callSnippet = 'Replace' },
        workspace = {
          library = vim.list_extend(vim.api.nvim_get_runtime_file('', true), {
            '${3rd}/busted/library',
            '${3rd}/luassert/library',
          }),
        },
      },
    },
  },
  -- Vue / JS / TS (hybrid mode)
  ts_ls = {
    before_init = typescript.before_init,
    root_dir = typescript.ts_ls_root_dir,
    init_options = {
      plugins = {
        vue_plugin,
      },
    },
    filetypes = {
      'typescript',
      'javascript',
      'javascriptreact',
      'typescriptreact',
      'vue',
    },
  },
  tsgo = {
    cmd = typescript.tsgo_cmd,
    root_dir = typescript.tsgo_root_dir,
  },
  vue_ls = {},
  eslint = {
    on_attach = function(client, bufnr)
      if eslint_on_attach then
        eslint_on_attach(client, bufnr)
      end
      vim.api.nvim_create_autocmd('BufWritePre', {
        buffer = bufnr,
        command = 'LspEslintFixAll',
      })
    end,
  },
  --[[ Oxlint fixAll is async, so running it in BufWritePre leaves the buffer modified after the file is written. ]]
  oxlint = {},
  oxfmt = {},

  -- CSS / HTML
  cssls = {},
  html = {},

  -- Rust
  rust_analyzer = {},
}

local ensure_installed = vim
  .iter(vim.tbl_keys(servers or {}))
  :filter(function(server_name)
    return server_name ~= 'tsgo'
  end)
  :totable()

require('mason-lspconfig').setup {
  ensure_installed = ensure_installed,
  automatic_enable = false, -- we enable servers manually below
}

typescript.setup()

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
vim.lsp.enable 'unocss'
