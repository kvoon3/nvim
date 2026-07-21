local typescript = require 'config.typescript'

describe('TypeScript LSP configuration', function()
  local root

  before_each(function()
    root = vim.fn.tempname()
    vim.fn.mkdir(vim.fs.joinpath(root, 'node_modules', 'typescript', 'lib'), 'p')
  end)

  after_each(function()
    vim.fn.delete(root, 'rf')
  end)

  it('uses the workspace tsserver when it exists', function()
    local tsserver = vim.fs.joinpath(root, 'node_modules', 'typescript', 'lib', 'tsserver.js')
    vim.fn.writefile({}, tsserver)

    assert.are.equal(tsserver, typescript.tsserver_path(root))
  end)

  it('uses the workspace TypeScript 7 executable when tsserver is absent', function()
    local bin_dir = vim.fs.joinpath(root, 'node_modules', '.bin')
    local tsc = vim.fs.joinpath(bin_dir, 'tsc')
    vim.fn.mkdir(bin_dir, 'p')
    vim.fn.writefile({}, tsc)
    vim.uv.fs_chmod(tsc, 493)

    assert.are.equal(tsc, typescript.tsgo_path(root))
  end)

  it('keeps Vue projects on ts_ls for TypeScript plugin support', function()
    local bin_dir = vim.fs.joinpath(root, 'node_modules', '.bin')
    local source_dir = vim.fs.joinpath(root, 'src')
    local tsc = vim.fs.joinpath(bin_dir, 'tsc')
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.fn.mkdir(bin_dir, 'p')
    vim.fn.mkdir(source_dir, 'p')
    vim.fn.writefile({}, tsc)
    vim.uv.fs_chmod(tsc, 493)
    vim.fn.writefile({}, vim.fs.joinpath(root, 'pnpm-lock.yaml'))
    vim.fn.writefile({ '{"dependencies":{"vue":"latest"}}' }, vim.fs.joinpath(root, 'package.json'))
    local source_file = vim.fs.joinpath(source_dir, 'index.ts')
    vim.fn.writefile({}, source_file)
    vim.api.nvim_buf_set_name(bufnr, source_file)
    vim.bo[bufnr].filetype = 'typescript'

    local ts_ls_root
    local tsgo_root
    typescript.ts_ls_root_dir(bufnr, function(value)
      ts_ls_root = value
    end)
    typescript.tsgo_root_dir(bufnr, function(value)
      tsgo_root = value
    end)

    vim.api.nvim_buf_delete(bufnr, { force = true })
    assert.are.equal(vim.uv.fs_realpath(root), ts_ls_root)
    assert.is_nil(tsgo_root)
  end)

  it('sets and clears the configured tsserver path before initialization', function()
    local tsserver = vim.fs.joinpath(root, 'node_modules', 'typescript', 'lib', 'tsserver.js')
    local config = {
      root_dir = root,
      init_options = { tsserver = { path = '/stale/tsserver.js' } },
    }

    typescript.before_init({}, config)
    assert.is_nil(config.init_options.tsserver.path)

    vim.fn.writefile({}, tsserver)
    typescript.before_init({}, config)
    assert.are.equal(tsserver, config.init_options.tsserver.path)
  end)

  it('detects dependency installation changes', function()
    local before = typescript.dependency_signature(root)
    vim.fn.writefile({ 'layoutVersion: 5' }, vim.fs.joinpath(root, 'node_modules', '.modules.yaml'))
    local after = typescript.dependency_signature(root)

    assert.are_not.equal(before, after)
  end)

  it('restarts an attached TypeScript client after dependencies change', function()
    local restart_count = 0
    local original_get_clients = vim.lsp.get_clients
    local client = {
      name = 'tsgo',
      root_dir = root,
      exit_timeout = false,
      _restart = function()
        restart_count = restart_count + 1
      end,
    }

    typescript.track(client)
    vim.fn.writefile({ 'layoutVersion: 5' }, vim.fs.joinpath(root, 'node_modules', '.modules.yaml'))
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.lsp.get_clients = function()
      return { client }
    end
    typescript.refresh()
    vim.wait(1000, function()
      return restart_count == 1
    end)

    vim.lsp.get_clients = original_get_clients
    assert.are.equal(1, restart_count)
  end)
end)
