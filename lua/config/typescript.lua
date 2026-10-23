local M = {}

local managed_servers = { ts_ls = true, tsrs = true, tsc = true }
local dependency_states = {}
local refresh_pending = false
local last_refresh_ts = 0
local project_markers = { 'package-lock.json', 'yarn.lock', 'pnpm-lock.yaml', 'bun.lockb', 'bun.lock', '.git' }

local function stat_signature(path, use_lstat)
  local stat = (use_lstat and vim.uv.fs_lstat or vim.uv.fs_stat)(path)
  if not stat then
    return '-'
  end

  return table.concat({
    stat.type or '',
    stat.size or 0,
    stat.mtime.sec,
    stat.mtime.nsec,
    stat.ino or 0,
  }, ':')
end

function M.tsserver_path(root_dir)
  if not root_dir then
    return nil
  end

  local path = vim.fs.joinpath(root_dir, 'node_modules', 'typescript', 'lib', 'tsserver.js')
  return vim.uv.fs_stat(path) and path or nil
end

local vue_plugin_dir_cache ---@type string|false|nil

--[[ Locate the @vue/typescript-plugin package, which tsserver resolves from the `location`
  handed to ts_ls. Walk up from the vue-language-server executable first, following symlinks
  because node `.bin` entries are links. Fall back to mise's isolated install layout: its
  pnpm-style store keeps the plugin inside the language-server package's own node_modules
  instead of hoisting it, and `mise which` cannot answer outside the config project. ]]
function M.vue_ts_plugin_dir()
  if vue_plugin_dir_cache ~= nil then
    return vue_plugin_dir_cache or nil
  end

  local function from_exe()
    local exe = vim.fn.exepath 'vue-language-server'
    if exe == '' then
      return nil
    end

    local dir = vim.fs.dirname(vim.uv.fs_realpath(exe) or exe)
    while dir and dir ~= '/' and dir ~= '' do
      if vim.fs.basename(dir) == 'language-server' and vim.fs.basename(vim.fs.dirname(dir)) == '@vue' then
        return dir
      end
      dir = vim.fs.dirname(dir)
    end

    return nil
  end

  local function from_mise()
    local data = vim.env.XDG_DATA_HOME or vim.fs.joinpath(vim.fn.expand '~', '.local', 'share')
    local pattern = vim.fs.joinpath(
      data,
      'mise',
      'installs',
      'npm-vue-language-server',
      '*',
      'node_modules',
      '@vue',
      'language-server'
    )
    return vim.fn.glob(pattern, false, true)[1]
  end

  vue_plugin_dir_cache = from_exe() or from_mise() or false
  return vue_plugin_dir_cache or nil
end

--[[ tsrs: Rust port of the TypeScript 7 compiler and language server
  (`mise use -g npm:tsrs`). It speaks the same `--lsp -stdio` protocol as tsgo, so it
  needs no adapter; Vue keeps ts_ls because @vue/typescript-plugin only exists in the
  JS tsserver and tsrs runs no content mappers. ]]
function M.tsrs_path()
  local path = vim.fn.exepath 'tsrs'
  return path ~= '' and path or nil
end

--[[ Workspace TypeScript 7.1+ native compiler. `bin/tsc` is the package's documented
  entry point, so it survives the platform-package reshuffle between 7.0
  (`@typescript/native-preview`) and 7.1 (`@typescript/typescript-<os>-<arch>`).
  Source phase imports, the es2026 libs and content mappers all landed in 7.1; a 7.0
  binary would lose features tsrs already has, so only 7.1+ outranks tsrs. ]]
local tsc_versions = {}

local function tsc_supports_71(path)
  local signature = stat_signature(path)
  local cached = tsc_versions[path]
  if cached and cached.signature == signature then
    return cached.ok
  end

  local result = vim.system({ path, '--version' }, { text = true }):wait()
  local version = result.code == 0 and vim.version.parse(result.stdout or '') or nil
  local ok = version ~= nil and version.major >= 7 and (version.major > 7 or version.minor >= 1)
  tsc_versions[path] = { signature = signature, ok = ok }
  return ok
end

function M.tsc_bin(root_dir)
  if not root_dir then
    return nil
  end

  local path = vim.fs.joinpath(root_dir, 'node_modules', '.bin', 'tsc')
  if vim.fn.executable(path) ~= 1 or not tsc_supports_71(path) then
    return nil
  end
  return path
end

local function project_root(bufnr)
  local buffer_path = vim.api.nvim_buf_get_name(bufnr)
  return vim.fs.root(buffer_path ~= '' and buffer_path or vim.fn.getcwd(), project_markers) or vim.fn.getcwd()
end

local function is_vue_project(bufnr, root_dir)
  if vim.bo[bufnr].filetype == 'vue' then
    return true
  end

  local buffer_path = vim.api.nvim_buf_get_name(bufnr)
  local package_json = vim.fs.find('package.json', {
    upward = true,
    path = vim.fs.dirname(buffer_path),
    stop = vim.fs.dirname(root_dir),
  })[1]
  if not package_json then
    return false
  end

  local ok, package = pcall(vim.json.decode, table.concat(vim.fn.readfile(package_json), '\n'))
  if not ok then
    return false
  end

  for _, field in ipairs { 'dependencies', 'devDependencies', 'peerDependencies' } do
    if package[field] and package[field].vue then
      return true
    end
  end
  return false
end

--[[ Escape hatch from the TypeScript 7 server: tsrs rejects options TypeScript 7
  removed (`baseUrl`, `target: ES5`, AMD/UMD modules, ...). `touch .nvim-tsserver` in such a
  repository to go back to its pinned tsserver. ]]
local function prefers_tsserver(bufnr)
  local buffer_path = vim.api.nvim_buf_get_name(bufnr)
  local start = buffer_path ~= '' and vim.fs.dirname(buffer_path) or vim.fn.getcwd()
  return #vim.fs.find('.nvim-tsserver', { upward = true, path = start }) > 0
end

--[[ One TS/JS server per buffer, first match wins. Vue keeps ts_ls: the Vue plugin only
  exists in the JS tsserver and needs the virtual-file protocol. A workspace 7.1+ compiler
  outranks tsrs so projects that pin the beta get the features tsrs does not port yet. ]]
local function ts_server(bufnr, root_dir)
  if is_vue_project(bufnr, root_dir) or prefers_tsserver(bufnr) then
    return 'ts_ls'
  end
  if M.tsc_bin(root_dir) then
    return 'tsc'
  end
  if M.tsrs_path() then
    return 'tsrs'
  end
  return 'ts_ls'
end

function M.ts_ls_root_dir(bufnr, on_dir)
  local root_dir = project_root(bufnr)
  if ts_server(bufnr, root_dir) == 'ts_ls' then
    on_dir(root_dir)
  end
end

function M.tsrs_root_dir(bufnr, on_dir)
  local root_dir = project_root(bufnr)
  if ts_server(bufnr, root_dir) == 'tsrs' then
    on_dir(root_dir)
  end
end

function M.tsrs_cmd(dispatchers)
  local path = assert(M.tsrs_path(), 'tsrs executable not found (mise use -g npm:tsrs)')
  return vim.lsp.rpc.start({ path, '--lsp', '-stdio' }, dispatchers)
end

function M.tsc_root_dir(bufnr, on_dir)
  local root_dir = project_root(bufnr)
  if ts_server(bufnr, root_dir) == 'tsc' then
    on_dir(root_dir)
  end
end

function M.tsc_cmd(dispatchers, config)
  local path = assert(M.tsc_bin(config.root_dir), 'workspace TypeScript 7.1 executable not found')
  return vim.lsp.rpc.start({ path, '--lsp', '--stdio' }, dispatchers)
end

function M.dependency_signature(root_dir)
  local node_modules = vim.fs.joinpath(root_dir, 'node_modules')
  return table.concat({
    stat_signature(node_modules, true),
    stat_signature(vim.fs.joinpath(node_modules, '.modules.yaml')),
    stat_signature(vim.fs.joinpath(node_modules, 'typescript'), true),
    stat_signature(vim.fs.joinpath(node_modules, '.bin', 'tsc')),
  }, '|')
end

function M.before_init(params, config)
  local root_dir = config.root_dir
  if params.rootUri then
    root_dir = vim.uri_to_fname(params.rootUri)
  end

  config.init_options = config.init_options or {}
  config.init_options.tsserver = config.init_options.tsserver or {}
  config.init_options.tsserver.path = M.tsserver_path(root_dir)

  --[[ initializationOptions is the same table as `init_options`, so filling it in here
    still reaches the server while keeping the lookup off the startup path. ]]
  local vue_plugin_dir = M.vue_ts_plugin_dir()
  if vue_plugin_dir then
    config.init_options.plugins = {
      {
        name = '@vue/typescript-plugin',
        location = vue_plugin_dir,
        languages = { 'vue' },
        configNamespace = 'typescript',
      },
    }
  end
end

--[[ `runExternalCode` lets a tsconfig `contentMappers` entry spawn workspace code. Neovim
  has no workspace-trust prompt, so require an explicit marker instead of trusting every
  project that pins TypeScript 7.1. ]]
local function runs_content_mappers(root_dir)
  return root_dir ~= nil and #vim.fs.find('.nvim-content-mappers', { upward = true, path = root_dir }) > 0
end

function M.tsc_before_init(params, config)
  local root_dir = config.root_dir
  if params.rootUri then
    root_dir = vim.uri_to_fname(params.rootUri)
  end

  config.init_options = config.init_options or {}
  config.init_options.runExternalCode = runs_content_mappers(root_dir)
end

local function restart_changed_clients()
  local seen_clients = {}

  for _, client in ipairs(vim.lsp.get_clients()) do
    local root_dir = client.root_dir
    local key = root_dir and client.name .. ':' .. root_dir or nil
    if managed_servers[client.name] and key and not seen_clients[key] then
      seen_clients[key] = true
      local signature = M.dependency_signature(root_dir)
      local previous = dependency_states[key]
      dependency_states[key] = signature

      if previous and previous ~= signature then
        vim.notify('TypeScript dependencies changed; restarting ' .. client.name, vim.log.levels.INFO)
        -- _restart is private API; if it breaks on nvim upgrade, replace with stop_client + restart.
        client:_restart(client.exit_timeout)
      end
    end
  end
end

function M.refresh()
  local now = vim.uv.hrtime() / 1e9
  if refresh_pending or now - last_refresh_ts < 2 then
    return
  end

  refresh_pending = true
  last_refresh_ts = now
  vim.defer_fn(function()
    refresh_pending = false
    restart_changed_clients()
  end, 150)
end

function M.track(client)
  if managed_servers[client.name] and client.root_dir then
    dependency_states[client.name .. ':' .. client.root_dir] = M.dependency_signature(client.root_dir)
  end
end

function M.setup()
  local group = vim.api.nvim_create_augroup('TypeScriptDependencies', { clear = true })
  vim.api.nvim_create_autocmd({ 'BufEnter', 'FocusGained', 'TermClose' }, {
    group = group,
    callback = M.refresh,
  })
end

return M
