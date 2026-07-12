--[[ Oxlint integration: default config, type-aware + typeCheck (tsgolint/tsgo), safe fix on save. ]]

local M = {}

local DEFAULT_CONFIG = vim.fn.stdpath('config') .. '/config/oxlint/.oxlintrc.json'

M.enabled = true

local PROJECT_CONFIG_NAMES = {
  '.oxlintrc.json',
  '.oxlintrc.jsonc',
  'oxlint.config.ts',
}

--[[ True when the workspace root already has a project oxlint config. ]]
local function has_project_config(root_dir)
  if root_dir == nil or root_dir == '' then
    return false
  end
  for _, name in ipairs(PROJECT_CONFIG_NAMES) do
    if vim.fn.filereadable(vim.fs.joinpath(root_dir, name)) == 1 then
      return true
    end
  end
  return false
end

--[[ Resolve workspace root: project oxlint config, then package.json/.git, else cwd. ]]
local function resolve_root(bufnr, on_dir)
  local fname = vim.api.nvim_buf_get_name(bufnr)
  local start = (fname ~= '' and fname) or vim.fn.getcwd()

  local project = vim.fs.find(PROJECT_CONFIG_NAMES, {
    path = start,
    upward = true,
    type = 'file',
  })[1]
  if project then
    on_dir(vim.fs.dirname(project))
    return
  end

  local fallback = vim.fs.find({ 'package.json', '.git' }, {
    path = start,
    upward = true,
  })[1]
  if fallback then
    on_dir(vim.fs.dirname(fallback))
    return
  end

  on_dir(vim.fn.getcwd())
end

--[[ Locate tsgolint (oxlint-tsgolint): PATH, project bin, then next to the oxlint install (e.g. vite-plus). ]]
local function find_tsgolint(root_dir)
  if vim.fn.executable('tsgolint') == 1 then
    return vim.fn.exepath('tsgolint')
  end

  local candidates = {}

  if root_dir and root_dir ~= '' then
    table.insert(candidates, vim.fs.joinpath(root_dir, 'node_modules', '.bin', 'tsgolint'))
    table.insert(candidates, vim.fs.joinpath(root_dir, 'node_modules', 'oxlint-tsgolint', 'bin', 'tsgolint.js'))
  end

  local oxlint = vim.fn.exepath('oxlint')
  if oxlint ~= '' then
    local oxlint_dir = vim.fs.dirname(vim.fn.resolve(oxlint))
    -- e.g. .../vite-plus/bin -> .../vite-plus/node_modules/.bin/tsgolint
    table.insert(candidates, vim.fs.joinpath(oxlint_dir, '..', 'node_modules', '.bin', 'tsgolint'))
    table.insert(
      candidates,
      vim.fs.joinpath(oxlint_dir, '..', 'node_modules', 'oxlint-tsgolint', 'bin', 'tsgolint.js')
    )
  end

  for _, path in ipairs(candidates) do
    local resolved = vim.fn.resolve(path)
    if vim.fn.executable(resolved) == 1 or vim.fn.filereadable(resolved) == 1 then
      return resolved
    end
  end

  return nil
end

--[[ Prefer project-local oxlint, else PATH. ]]
local function resolve_oxlint_cmd(root_dir)
  if root_dir and root_dir ~= '' then
    local local_cmd = vim.fs.joinpath(root_dir, 'node_modules', '.bin', 'oxlint')
    if vim.fn.executable(local_cmd) == 1 then
      return local_cmd
    end
  end
  return 'oxlint'
end

function M.is_available()
  return vim.fn.executable('oxlint') == 1
end

function M.setup(opts)
  opts = opts or {}
  if not M.is_available() then
    return
  end

  local capabilities = opts.capabilities

  vim.lsp.config('oxlint', {
    capabilities = capabilities,
    -- Allow linting outside projects that declare oxlint/vite-plus explicitly.
    workspace_required = false,
    root_dir = resolve_root,
    cmd = function(dispatchers, config)
      local cmd = resolve_oxlint_cmd((config or {}).root_dir)
      local tsgolint = find_tsgolint((config or {}).root_dir)
      local extra = {}
      if tsgolint then
        -- Oxlint discovers tsgolint via PATH or OXLINT_TSGOLINT_PATH.
        local env = vim.fn.environ()
        env.OXLINT_TSGOLINT_PATH = tsgolint
        env.PATH = vim.fs.dirname(tsgolint) .. ':' .. (env.PATH or '')
        extra.env = env
      end
      return vim.lsp.rpc.start({ cmd, '--lsp' }, dispatchers, extra)
    end,
    settings = {
      run = 'onType',
      fixKind = 'safe_fix',
      -- Always prefer type-aware + TSGo type diagnostics when tsgolint is available.
      typeAware = true,
      typeCheck = true,
    },
    before_init = function(init_params, config)
      local settings = vim.deepcopy(config.settings or {})

      -- Prefer project config; otherwise point the LSP at our default
      -- (which enables options.typeAware / options.typeCheck).
      if not has_project_config(config.root_dir) and vim.fn.filereadable(DEFAULT_CONFIG) == 1 then
        settings.configPath = DEFAULT_CONFIG
      end

      local tsgolint = find_tsgolint(config.root_dir)
      if tsgolint then
        settings.typeAware = true
        settings.typeCheck = true
      else
        -- Without tsgolint, force-off to avoid noisy "failed to find tsgolint" loops.
        settings.typeAware = false
        settings.typeCheck = false
        vim.schedule(function()
          vim.notify(
            'oxlint: tsgolint not found; type-aware/typeCheck disabled. Install oxlint-tsgolint (or vite-plus).',
            vim.log.levels.WARN
          )
        end)
      end

      config.settings = settings
      local init_options = config.init_options or {}
      init_options.settings = vim.tbl_extend('force', init_options.settings or {}, settings)
      init_params.initializationOptions = init_options
    end,
    on_attach = function(client, bufnr)
      vim.api.nvim_buf_create_user_command(bufnr, 'LspOxlintFixAll', function()
        client:exec_cmd({
          title = 'Apply Oxlint automatic fixes',
          command = 'oxc.fixAll',
          arguments = { { uri = vim.uri_from_bufnr(bufnr) } },
        })
      end, {
        desc = 'Apply Oxlint automatic fixes',
      })

      -- Safe auto-fixes for the current buffer on save (same idea as eslint).
      vim.api.nvim_create_autocmd('BufWritePre', {
        buffer = bufnr,
        group = vim.api.nvim_create_augroup('OxlintFixOnSave' .. bufnr, { clear = true }),
        callback = function()
          if not M.enabled then
            return
          end
          if vim.fn.exists(':LspOxlintFixAll') == 2 then
            vim.cmd('LspOxlintFixAll')
          end
        end,
        desc = 'Apply safe oxlint fixes on save',
      })
    end,
  })

  if M.enabled then
    vim.lsp.enable('oxlint')
  end
end

return M
