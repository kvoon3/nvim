local M = {}

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

function M.tsgo_path(root_dir)
  if M.tsserver_path(root_dir) then
    return nil
  end

  local path = root_dir and vim.fs.joinpath(root_dir, 'node_modules', '.bin', 'tsc') or nil
  return path and vim.fn.executable(path) == 1 and path or nil
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

function M.ts_ls_root_dir(bufnr, on_dir)
  local root_dir = project_root(bufnr)
  if is_vue_project(bufnr, root_dir) or not M.tsgo_path(root_dir) then
    on_dir(root_dir)
  end
end

function M.tsgo_root_dir(bufnr, on_dir)
  local root_dir = project_root(bufnr)
  if M.tsgo_path(root_dir) and not is_vue_project(bufnr, root_dir) then
    on_dir(root_dir)
  end
end

function M.tsgo_cmd(dispatchers, config)
  local path = M.tsgo_path(config.root_dir)
  return vim.lsp.rpc.start(
    { assert(path, 'workspace TypeScript 7 executable not found'), '--lsp', '--stdio' },
    dispatchers
  )
end

function M.dependency_signature(root_dir)
  local node_modules = vim.fs.joinpath(root_dir, 'node_modules')
  return table.concat({
    stat_signature(node_modules, true),
    stat_signature(vim.fs.joinpath(node_modules, '.modules.yaml')),
    stat_signature(vim.fs.joinpath(node_modules, 'typescript'), true),
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
end

local function restart_changed_clients()
  local seen_clients = {}

  for _, client in ipairs(vim.lsp.get_clients()) do
    local root_dir = client.root_dir
    local key = root_dir and client.name .. ':' .. root_dir or nil
    if (client.name == 'ts_ls' or client.name == 'tsgo') and key and not seen_clients[key] then
      seen_clients[key] = true
      local signature = M.dependency_signature(root_dir)
      local previous = dependency_states[key]
      dependency_states[key] = signature

      if previous and previous ~= signature then
        vim.notify('TypeScript dependencies changed; restarting ' .. client.name, vim.log.levels.INFO)
        -- ponytail: _restart is private API; if it breaks on nvim upgrade, replace with stop_client + restart.
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
  if (client.name == 'ts_ls' or client.name == 'tsgo') and client.root_dir then
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
