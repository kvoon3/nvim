local expect = require('mini.test').expect
local typescript = require 'config.typescript'

describe('TypeScript LSP configuration', function()
  local root

  local function write_tsc(version)
    local bin_dir = vim.fs.joinpath(root, 'node_modules', '.bin')
    local bin = vim.fs.joinpath(bin_dir, 'tsc')
    vim.fn.mkdir(bin_dir, 'p')
    vim.fn.writefile({ '#!/bin/sh', 'echo "Version ' .. version .. '"' }, bin)
    vim.uv.fs_chmod(bin, 493)
    return bin
  end

  local function project_buffer(filetype)
    local source_dir = vim.fs.joinpath(root, 'src')
    local file = vim.fs.joinpath(source_dir, 'index.ts')
    vim.fn.mkdir(source_dir, 'p')
    vim.fn.writefile({}, vim.fs.joinpath(root, 'pnpm-lock.yaml'))
    vim.fn.writefile({}, file)

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, file)
    vim.bo[bufnr].filetype = filetype
    return bufnr
  end

  local function resolved_root(resolver, bufnr)
    local resolved
    resolver(bufnr, function(value)
      resolved = value
    end)
    return resolved
  end

  local function realpath(path)
    return path and vim.uv.fs_realpath(path) or nil
  end

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

    expect.equality(tsserver, typescript.tsserver_path(root))
  end)

  it('detects a workspace TypeScript 7.1 native compiler', function()
    local bin = write_tsc '7.1.0-beta'

    expect.equality(bin, typescript.tsc_bin(root))
  end)

  it('rejects older compilers and rechecks after an upgrade', function()
    write_tsc '6.2.0'
    expect.equality(nil, typescript.tsc_bin(root))

    local bin = write_tsc '7.1.0-beta'
    expect.equality(bin, typescript.tsc_bin(root))
  end)

  it('keeps Vue projects on ts_ls for TypeScript plugin support', function()
    write_tsc '7.1.0-beta'
    vim.fn.writefile({ '{"dependencies":{"vue":"latest"}}' }, vim.fs.joinpath(root, 'package.json'))
    local bufnr = project_buffer 'typescript'

    local ts_ls_root = resolved_root(typescript.ts_ls_root_dir, bufnr)
    local tsc_root = resolved_root(typescript.tsc_root_dir, bufnr)
    vim.api.nvim_buf_delete(bufnr, { force = true })

    expect.equality(realpath(root), realpath(ts_ls_root))
    expect.equality(nil, tsc_root)
  end)

  it('honours the .nvim-tsserver escape hatch', function()
    write_tsc '7.1.0-beta'
    local bufnr = project_buffer 'typescript'
    vim.fn.writefile({}, vim.fs.joinpath(root, '.nvim-tsserver'))

    local ts_ls_root = resolved_root(typescript.ts_ls_root_dir, bufnr)
    local tsc_root = resolved_root(typescript.tsc_root_dir, bufnr)
    vim.api.nvim_buf_delete(bufnr, { force = true })

    expect.equality(realpath(root), realpath(ts_ls_root))
    expect.equality(nil, tsc_root)
  end)

  it('routes non-Vue TypeScript 7.1 projects to the native compiler', function()
    write_tsc '7.1.0-beta'
    local bufnr = project_buffer 'typescript'

    local tsc_root = resolved_root(typescript.tsc_root_dir, bufnr)
    local ts_ls_root = resolved_root(typescript.ts_ls_root_dir, bufnr)
    vim.api.nvim_buf_delete(bufnr, { force = true })

    expect.equality(realpath(root), realpath(tsc_root))
    expect.equality(nil, ts_ls_root)
  end)

  it('sets and clears the configured tsserver path before initialization', function()
    local tsserver = vim.fs.joinpath(root, 'node_modules', 'typescript', 'lib', 'tsserver.js')
    local config = {
      root_dir = root,
      init_options = { tsserver = { path = '/stale/tsserver.js' } },
    }

    typescript.before_init({}, config)
    expect.equality(nil, config.init_options.tsserver.path)

    vim.fn.writefile({}, tsserver)
    typescript.before_init({}, config)
    expect.equality(tsserver, config.init_options.tsserver.path)
  end)

  it('runs content mappers only behind the marker', function()
    local config = { root_dir = root, init_options = {} }

    typescript.tsc_before_init({}, config)
    expect.equality(false, config.init_options.runExternalCode)

    vim.fn.writefile({}, vim.fs.joinpath(root, '.nvim-content-mappers'))
    typescript.tsc_before_init({}, config)
    expect.equality(true, config.init_options.runExternalCode)
  end)

  it('detects dependency installation changes', function()
    local before = typescript.dependency_signature(root)
    vim.fn.writefile({ 'layoutVersion: 5' }, vim.fs.joinpath(root, 'node_modules', '.modules.yaml'))
    local after = typescript.dependency_signature(root)

    expect.no_equality(before, after)
  end)

  it('restarts an attached TypeScript client after dependencies change', function()
    local restart_count = 0
    local original_get_clients = vim.lsp.get_clients
    local client = {
      name = 'tsrs',
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
    expect.equality(1, restart_count)
  end)
end)
