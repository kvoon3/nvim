-- Headless plenary/busted spec for lua/git-status.lua.
-- Run all specs with: just test

local git_status = require 'git-status'

describe('git-status', function()
  local bufnr
  local root
  local root_seq = 0
  local system_calls
  local system_queue
  local notifications
  local orig_system
  local orig_notify

  local function queue_result(code, stdout, stderr)
    table.insert(system_queue, { code = code, stdout = stdout or '', stderr = stderr or '' })
  end

  -- Each test uses a fresh root so the module-level cache never leaks between tests.
  local function fresh_root()
    root_seq = root_seq + 1
    return '/repo' .. root_seq
  end

  local function flush()
    vim.wait(50)
  end

  local function notified(pattern)
    for _, n in ipairs(notifications) do
      if n.msg:find(pattern) then
        return true
      end
    end
    return false
  end

  before_each(function()
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr) -- before the dict is set, so the BufEnter autocmd no-ops
    root = fresh_root()
    system_calls = {}
    system_queue = {}
    notifications = {}
    orig_system = vim.system
    orig_notify = vim.notify
    vim.system = function(cmd, opts, on_exit)
      table.insert(system_calls, { cmd = cmd, opts = opts })
      local result = table.remove(system_queue, 1) or { code = 0, stdout = '', stderr = '' }
      if on_exit then
        on_exit(result)
      end
    end
    vim.notify = function(msg, level)
      table.insert(notifications, { msg = msg, level = level })
    end
  end)

  after_each(function()
    vim.system = orig_system
    vim.notify = orig_notify
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  it('returns nil without gitsigns data', function()
    assert.is_nil(git_status.get(bufnr))
  end)

  it('returns the branch with zero counts before any refresh', function()
    vim.b[bufnr].gitsigns_status_dict = { head = 'main', root = root }
    local status = git_status.get(bufnr)
    assert.are.equal('main', status.branch)
    assert.are.equal(0, status.ahead)
    assert.are.equal(0, status.behind)
    assert.is_false(status.upstream)
  end)

  it('caches ahead/behind from rev-list --left-right output', function()
    vim.b[bufnr].gitsigns_status_dict = { head = 'main', root = root }
    queue_result(0, '3\t2\n')
    git_status.refresh(root)
    flush()

    assert.are.same({ 'git', 'rev-list', '--left-right', '--count', '@{u}...HEAD' }, system_calls[1].cmd)
    assert.are.equal(root, system_calls[1].opts.cwd)

    local status = git_status.get(bufnr)
    assert.are.equal(2, status.ahead) -- right side: HEAD-only commits
    assert.are.equal(3, status.behind) -- left side: upstream-only commits
    assert.is_true(status.upstream)
  end)

  it('treats a non-zero exit as no upstream', function()
    vim.b[bufnr].gitsigns_status_dict = { head = 'main', root = root }
    queue_result(128, '', 'fatal: no upstream configured')
    git_status.refresh(root)
    flush()
    assert.is_false(git_status.get(bufnr).upstream)
  end)

  it('dedupes concurrent refreshes for the same root', function()
    queue_result(0, '0\t0\n')
    git_status.refresh(root)
    git_status.refresh(root)
    flush()
    assert.are.equal(1, #system_calls)
  end)

  it('push runs git push in the repo root and refreshes', function()
    vim.b[bufnr].gitsigns_status_dict = { head = 'main', root = root }
    queue_result(0, '') -- push
    queue_result(0, '0\t0\n') -- refresh
    git_status.push()
    flush()

    assert.are.same({ 'git', 'push' }, system_calls[1].cmd)
    assert.are.equal(root, system_calls[1].opts.cwd)
    assert.is_true(notified 'git push: done')
  end)

  it('push failure notifies the stderr', function()
    vim.b[bufnr].gitsigns_status_dict = { head = 'main', root = root }
    queue_result(1, '', 'rejected: non-fast-forward')
    queue_result(0, '1\t0\n')
    git_status.push()
    flush()
    assert.is_true(notified 'non%-fast%-forward')
  end)

  it('pull_rebase_push chains pull --rebase then push', function()
    vim.b[bufnr].gitsigns_status_dict = { head = 'main', root = root }
    queue_result(0, '') -- pull --rebase
    queue_result(0, '') -- push
    queue_result(0, '0\t0\n') -- refresh
    git_status.pull_rebase_push()
    flush()

    assert.are.same({ 'git', 'pull', '--rebase' }, system_calls[1].cmd)
    assert.are.same({ 'git', 'push' }, system_calls[2].cmd)
    assert.is_true(notified 'git push: done')
  end)

  it('pull_rebase_push stops after a failed rebase', function()
    vim.b[bufnr].gitsigns_status_dict = { head = 'main', root = root }
    queue_result(1, '', 'could not apply abc123')
    queue_result(0, '2\t1\n')
    git_status.pull_rebase_push()
    flush()

    assert.are.equal(2, #system_calls) -- no push after a failed rebase
    assert.is_true(notified 'could not apply')
  end)

  it('warns instead of running outside a git repository', function()
    git_status.push()
    assert.are.equal(0, #system_calls)
    assert.is_true(notified 'Not in a git repository')
  end)
end)
