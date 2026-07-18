local M = {}

-- Ahead/behind counts cached per git root; `running` dedupes concurrent refreshes.
local cache = {}
local running = {}

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO)
end

--[[ Run a git command asynchronously in root and invoke on_done(code, stdout, stderr) on the main loop. ]]
local function git(args, root, on_done)
  vim.system(vim.list_extend({ 'git' }, args), { cwd = root, text = true }, function(result)
    vim.schedule(function()
      on_done(result.code, result.stdout or '', result.stderr or '')
    end)
  end)
end

--[[ Query the upstream sync state of root asynchronously and refresh the cache.
A non-zero exit means there is no upstream (or not a repo): no arrows are shown. ]]
function M.refresh(root)
  if not root or root == '' or running[root] then
    return
  end
  running[root] = true
  git({ 'rev-list', '--left-right', '--count', '@{u}...HEAD' }, root, function(code, stdout)
    running[root] = nil
    local new
    if code == 0 then
      -- --left-right @{u}...HEAD: left counts upstream-only commits (behind), right counts HEAD-only (ahead)
      local behind, ahead = stdout:match '(%d+)%s+(%d+)'
      new = { ahead = tonumber(ahead) or 0, behind = tonumber(behind) or 0, upstream = true }
    else
      new = { ahead = 0, behind = 0, upstream = false }
    end
    if not vim.deep_equal(cache[root], new) then
      cache[root] = new
      vim.cmd 'redrawstatus'
    end
  end)
end

--[[ Sync state for a buffer: branch from gitsigns, ahead/behind from the cache.
Returns nil outside a git repository. ]]
function M.get(bufnr)
  local dict = vim.b[bufnr].gitsigns_status_dict
  if not dict or not dict.head or dict.head == '' then
    return nil
  end
  local counts = dict.root and cache[dict.root]
  return {
    branch = dict.head,
    root = dict.root,
    upstream = counts and counts.upstream or false,
    ahead = counts and counts.ahead or 0,
    behind = counts and counts.behind or 0,
  }
end

--[[ Run a git operation in the current buffer's repo; notify the result and refresh the cache. ]]
local function run_in_repo(args, desc, on_success)
  local status = M.get(0)
  if not status or not status.root then
    notify('Not in a git repository', vim.log.levels.WARN)
    return
  end
  git(args, status.root, function(code, _, stderr)
    if code ~= 0 then
      notify(desc .. ' failed: ' .. vim.trim(stderr), vim.log.levels.ERROR)
      M.refresh(status.root)
      return
    end
    notify(desc .. ': done')
    if on_success then
      on_success(status.root)
    else
      M.refresh(status.root)
    end
  end)
end

function M.push()
  run_in_repo({ 'push' }, 'git push')
end

function M.pull()
  run_in_repo({ 'pull' }, 'git pull')
end

--[[ Pull with rebase, then push; used when the branch has diverged (both ahead and behind). ]]
function M.pull_rebase_push()
  run_in_repo({ 'pull', '--rebase' }, 'git pull --rebase', function(root)
    git({ 'push' }, root, function(code, _, stderr)
      if code == 0 then
        notify 'git push: done'
      else
        notify('git push failed: ' .. vim.trim(stderr), vim.log.levels.ERROR)
      end
      M.refresh(root)
    end)
  end)
end

local function refresh_buffer(bufnr)
  local dict = vim.b[bufnr].gitsigns_status_dict
  if dict and dict.root then
    M.refresh(dict.root)
  end
end

local group = vim.api.nvim_create_augroup('GitStatusRefresh', { clear = true })

vim.api.nvim_create_autocmd({ 'BufEnter', 'FocusGained' }, {
  group = group,
  callback = function()
    refresh_buffer(0)
  end,
})

vim.api.nvim_create_autocmd('User', {
  group = group,
  pattern = 'GitSignsUpdate',
  callback = function(ev)
    if ev.data and ev.data.buffer then
      refresh_buffer(ev.data.buffer)
    end
  end,
})

require('cmdr').add {
  {
    desc = 'Git push',
    cmd = M.push,
    cat = 'git',
  },
  {
    desc = 'Git pull',
    cmd = M.pull,
    cat = 'git',
  },
  {
    desc = 'Git pull --rebase & push',
    cmd = M.pull_rebase_push,
    cat = 'git',
  },
}

return M
