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
    vim.keymap.set({ 'n', 'v' }, '<C-.>', vim.lsp.buf.code_action, opts)
    --[[ `gr` (references) is intentionally not mapped: the runtime ships built-in `gr*` maps
      (grr/gri/grt/grx/gra/grn) and a buffer-local `gr` would become their prefix sibling,
      so mini.clue's `g` trigger can never reach a unique target and stalls on a clue float. ]]
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

--[[ Main navigation paths skip hints/infos so real problems don't get buried;
  [D/]D cover all severities, <leader>hn stays hint-specific. ]]
local w_e = { vim.diagnostic.severity.WARN, vim.diagnostic.severity.ERROR }
vim.keymap.set('n', '[d', jump_diagnostic(-1, w_e), { desc = 'Go to previous diagnostic' })
vim.keymap.set('n', ']d', jump_diagnostic(1, w_e), { desc = 'Go to next diagnostic' })
vim.keymap.set('n', '<leader>en', jump_diagnostic(1, w_e), { desc = 'Go to next diagnostic' })
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
local silent_lint_rules = {
  'style/*',
  '*-indent',
  '*-spacing',
  '*-spaces',
  '*-order',
  '*-dangle',
  '*-newline',
  '*quotes',
  '*semi',
}
--[[ Oxlint codes look like `stylistic(semi)`, `perfectionist(sort-imports)`: plugin-scoped, parenthesized.
  glob2regpat('*-semi') -> '-semi$' would require the code to END in '-semi', which a parenthesized code never does.
  So extract the parenthesized rule name and match its suffix (the glob's `*` = leading wildcard). ]]
local silent_lint_rule_suffixes = vim.tbl_map(function(rule)
  if rule == 'style/*' then
    return 'stylistic'
  end
  return (rule:gsub('^%*%-', ''):gsub('^%*', ''))
end, silent_lint_rules)
local publish_diagnostics = vim.lsp.handlers['textDocument/publishDiagnostics']

local function is_silenced_lsp_diagnostic(diagnostic)
  local rule = tostring(diagnostic.code or '')
  local rule_name = rule:match '^[%w-]+%(([%w-]+)%)$'
  if not rule_name then
    return false
  end
  return vim.iter(silent_lint_rule_suffixes):any(function(suffix)
    return suffix ~= '' and rule_name:sub(-#suffix) == suffix
  end)
end

local function filter_lsp_diagnostics(items)
  return vim.tbl_filter(function(diagnostic)
    return not is_silenced_lsp_diagnostic(diagnostic)
  end, items)
end

local function filter_stylistic_diagnostics(err, result, ctx, config)
  --[[ Hide stylistic Oxlint diagnostics without disabling its fix-all command. ]]
  if result then
    result.diagnostics = filter_lsp_diagnostics(result.diagnostics)
  end
  return publish_diagnostics(err, result, ctx, config)
end

--[[ Oxlint (>= 1.77) dropped `workspace/executeCommand oxc.fixAll`;
  lspconfig's :LspOxlintFixAll is now a dead command (server logs `Unknown command oxc.fixAll`).
  The working mechanism is textDocument/codeAction `source.fixAll.oxc`.
  Its first response is computed against stale state and drops overlapping fixes,
  so loop: each pass re-requests after applying, until the server returns no edits. ]]
local function oxlint_fix_all(bufnr)
  local client = vim.lsp.get_clients({ bufnr = bufnr, name = 'oxlint' })[1]
  if not client then
    return
  end
  local uri = vim.uri_from_bufnr(bufnr)
  for _ = 1, 5 do
    local params = {
      textDocument = { uri = uri },
      range = {
        start = { line = 0, character = 0 },
        ['end'] = { line = vim.api.nvim_buf_line_count(bufnr) - 1, character = 0 },
      },
      context = { diagnostics = {}, only = { 'source.fixAll.oxc' } },
    }
    local responses = vim.lsp.buf_request_sync(bufnr, 'textDocument/codeAction', params, 2000)
    local applied_edits = 0
    for _, res in pairs(responses or {}) do
      if res.result and #res.result > 0 then
        local edit = res.result[1].edit
        local changes = edit.changes and edit.changes[uri]
        applied_edits = applied_edits + (changes and #changes or 0)
        vim.lsp.util.apply_workspace_edit(edit, client.offset_encoding or 'utf-16')
      end
    end
    if applied_edits == 0 then
      break
    end
    --[[ The server recomputes diagnostics asynchronously after the buffer change;
      waiting too short returns the stale fix set and drops overlapping fixes (quotes). ]]
    vim.wait(300)
  end
end

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
  tsc = {
    cmd = typescript.tsgo_cmd,
    root_dir = typescript.tsgo_root_dir,
  },
  vue_ls = {},
  eslint = {
    settings = {
      rulesCustomizations = vim.tbl_map(function(rule)
        return { rule = rule, severity = 'off', fixable = true }
      end, silent_lint_rules),
    },
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
  oxlint = {
    handlers = {
      ['textDocument/publishDiagnostics'] = filter_stylistic_diagnostics,
      --[[ oxlint 1.77+ advertises diagnosticProvider (pull-based); Neovim 0.12 then
        pulls via textDocument/diagnostic, bypassing publishDiagnostics. Filter there too. ]]
      ['textDocument/diagnostic'] = function(err, result, ctx)
        if result and result.kind == 'full' then
          result.items = filter_lsp_diagnostics(result.items)
        end
        return vim.lsp.diagnostic.on_diagnostic(err, result, ctx)
      end,
    },
    on_attach = function(_, bufnr)
      --[[ oxlint_fix_all is synchronous (buf_request_sync), so it completes before nvim writes. ]]
      vim.api.nvim_create_autocmd('BufWritePre', {
        buffer = bufnr,
        callback = function()
          oxlint_fix_all(bufnr)
        end,
      })
    end,
  },
  oxfmt = {},

  -- Spelling / grammar
  typos_lsp = {},
  harper_ls = {},

  -- CSS / HTML
  cssls = {},
  html = {},

  -- Rust
  rust_analyzer = {},
}

local ensure_installed = vim
  .iter(vim.tbl_keys(servers or {}))
  :filter(function(server_name)
    return server_name ~= 'tsc'
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
