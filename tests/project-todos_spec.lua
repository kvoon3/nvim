-- Headless mini.test spec for lua/project-todos.lua.
-- Run all specs with: just test

local expect = require('mini.test').expect

local config_root = vim.fn.fnamemodify(vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h'), ':h')

local searched
local results

local function stub_search(items)
  searched = {}
  results = items or {}
  package.loaded['todo-comments.config'] = { loaded = true, options = {} }
  package.loaded['todo-comments.search'] = {
    search = function(cb, opts)
      table.insert(searched, opts.cwd)
      cb(results)
    end,
  }
end

local function fresh()
  package.loaded['project-todos'] = nil
  return dofile(config_root .. '/lua/project-todos.lua')
end

local function scratch(name)
  vim.cmd('edit ' .. vim.fn.fnameescape(name))
  return vim.api.nvim_get_current_buf()
end

local function fake_results(n)
  local items = {}
  for i = 1, n do
    items[i] = { filename = 'probe.lua', lnum = i, col = 1, line = 'TODO: probe' }
  end
  return items
end

local project, plain

describe('project-todos', function()
  local original_cwd

  before_each(function()
    original_cwd = vim.fn.getcwd()
    local base = vim.fn.tempname()
    local base_plain = vim.fn.tempname()
    vim.fn.mkdir(base .. '/.git', 'p')
    vim.fn.mkdir(base_plain, 'p')
    vim.fn.writefile({ 'TODO: probe' }, base .. '/probe.lua')
    vim.fn.writefile({ 'TODO: probe' }, base_plain .. '/todo.md')
    project = vim.uv.fs_realpath(base)
    plain = vim.uv.fs_realpath(base_plain)
  end)

  after_each(function()
    vim.cmd('cd ' .. vim.fn.fnameescape(original_cwd))
    pcall(vim.api.nvim_del_augroup_by_name, 'ProjectTodos')
    package.loaded['todo-comments.config'] = nil
    package.loaded['todo-comments.search'] = nil
    vim.cmd 'silent! %bwipeout!'
    vim.fn.delete(project, 'rf')
    vim.fn.delete(plain, 'rf')
  end)

  describe('root resolution', function()
    it('skips the search when only $HOME is above the file', function()
      stub_search()
      vim.cmd('cd ' .. vim.fn.fnameescape(vim.fn.expand '~'))
      local module = fresh()
      expect.equality('', module.section(scratch(plain .. '/todo.md')))
      expect.equality({}, searched)
      expect.equality(nil, module.count(0))
    end)

    it('skips the search when the cwd has no project marker', function()
      stub_search()
      vim.cmd('cd ' .. vim.fn.fnameescape(plain))
      local module = fresh()
      expect.equality('', module.section(scratch(plain .. '/todo.md')))
      expect.equality({}, searched)
    end)

    it('searches at the git root above the file', function()
      stub_search()
      local module = fresh()
      expect.equality('TODO:0', module.section(scratch(project .. '/probe.lua')))
      expect.equality({ project }, searched)
    end)

    it('warns instead of opening a picker outside a project', function()
      stub_search()
      vim.cmd('cd ' .. vim.fn.fnameescape(vim.fn.expand '~'))
      local notified = {}
      local orig_notify = vim.notify
      vim.notify = function(msg, level)
        table.insert(notified, { msg = msg, level = level })
      end
      fresh().open(scratch(plain .. '/todo.md'))
      vim.notify = orig_notify
      expect.equality(1, #notified)
      expect.equality(vim.log.levels.WARN, notified[1].level)
      expect.equality({}, searched)
    end)
  end)

  describe('statusline section', function()
    it('shows the exact count below the cap', function()
      stub_search(fake_results(3))
      expect.equality('TODO:3', fresh().section(scratch(project .. '/probe.lua')))
    end)

    it('clamps the display above the cap while keeping count truthful', function()
      stub_search(fake_results(6000))
      local module = fresh()
      expect.equality('TODO:5000+', module.section(scratch(project .. '/probe.lua')))
      expect.equality(6000, module.count(0))
    end)

    it('is empty for non-file buffers', function()
      stub_search(fake_results(3))
      local buf = vim.api.nvim_create_buf(false, true)
      expect.equality('', fresh().section(buf))
      expect.equality({}, searched)
    end)
  end)

  describe('refresh triggers', function()
    it('searches once at startup and again after a write', function()
      stub_search(fake_results(2))
      local module = fresh()
      local buf = scratch(project .. '/probe.lua')
      module.setup()
      expect.equality({ project }, searched)

      vim.cmd 'silent write'
      expect.equality({ project, project }, searched)
      expect.equality('TODO:2', module.section(buf))
    end)

    it('does not re-search the same root within the throttle window', function()
      stub_search(fake_results(1))
      vim.fn.writefile({ 'TODO: other' }, project .. '/other.lua')
      local module = fresh()
      local buf = scratch(project .. '/probe.lua')
      module.setup()
      expect.equality({ project }, searched)
      expect.equality('TODO:1', module.section(buf))

      scratch(project .. '/other.lua')
      expect.equality({ project }, searched)
    end)

    it('does not error on writes outside a project', function()
      stub_search()
      vim.cmd('cd ' .. vim.fn.fnameescape(vim.fn.expand '~'))
      local module = fresh()
      local buf = scratch(plain .. '/todo.md')
      vim.api.nvim_set_current_buf(buf)
      module.setup()
      expect.equality(true, pcall(vim.cmd, 'silent write'))
      expect.equality({}, searched)
    end)
  end)
end)
