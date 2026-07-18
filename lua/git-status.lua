local M = {}

-- Ahead/behind and dirty state cached per git root; `running*` dedupes concurrent refreshes.
local cache = {}
local running = {}
local running_dirty = {}

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

local function update_cache(root, key, value)
  cache[root] = cache[root] or {}
  if cache[root][key] ~= value then
    cache[root][key] = value
    return true
  end
  return false
end

local function refresh_sync(root)
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
    local ahead_changed = update_cache(root, 'ahead', new.ahead)
    local behind_changed = update_cache(root, 'behind', new.behind)
    local upstream_changed = update_cache(root, 'upstream', new.upstream)
    if ahead_changed or behind_changed or upstream_changed then
      vim.cmd 'redrawstatus'
    end
  end)
end

local function refresh_dirty(root)
  if not root or root == '' or running_dirty[root] then
    return
  end
  running_dirty[root] = true
  git({ 'status', '--porcelain' }, root, function(code, stdout)
    running_dirty[root] = nil
    if code ~= 0 then
      return
    end
    local dirty = stdout:match '%S' ~= nil
    if update_cache(root, 'dirty', dirty) then
      vim.cmd 'redrawstatus'
    end
  end)
end

--[[ Query the upstream sync state and dirty state of root asynchronously and refresh the cache.
A non-zero exit from rev-list means there is no upstream (or not a repo): no arrows are shown. ]]
function M.refresh(root)
  refresh_sync(root)
  refresh_dirty(root)
end

local function is_git_worktree(path)
  return vim.fn.isdirectory(path .. '/.git') == 1 or vim.fn.filereadable(path .. '/.git') == 1
end

--[[ Resolve the git root and branch for a buffer.
Normal buffers get this from gitsigns; netrw buffers use the browsed directory and have no branch name. ]]
local function buffer_repo(bufnr)
  local dict = vim.b[bufnr].gitsigns_status_dict
  if dict and dict.head and dict.head ~= '' and dict.root then
    return dict.root, dict.head
  end
  if vim.bo[bufnr].filetype == 'netrw' then
    local root = vim.b[bufnr].netrw_curdir
    if root and root ~= '' and is_git_worktree(root) then
      return root, nil
    end
  end
  return nil, nil
end

--[[ Sync and dirty state for a buffer: branch from gitsigns, ahead/behind/dirty from the cache.
For netrw buffers only the sync/dirty state is shown. Returns nil outside a git repository. ]]
function M.get(bufnr)
  local root, branch = buffer_repo(bufnr)
  if not root then
    return nil
  end
  local counts = cache[root] or {}
  return {
    branch = branch,
    root = root,
    upstream = counts.upstream or false,
    ahead = counts.ahead or 0,
    behind = counts.behind or 0,
    dirty = counts.dirty or false,
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
  local root = buffer_repo(bufnr)
  if root then
    M.refresh(root)
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
    -- Gitsigns omits `data` when the repo HEAD changes (e.g. after a commit),
    -- so fall back to the current buffer.
    refresh_buffer(ev.data and ev.data.buffer or 0)
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
