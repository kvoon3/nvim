local M = {}

-- Git status cached per root; `running` dedupes concurrent refreshes.
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

--[[ Parse Git's machine-readable status output into the statusline state. ]]
local function parse_status(stdout)
  local status = { branch = false, upstream = false, ahead = 0, behind = 0, dirty = false }
  for line in stdout:gmatch '[^\r\n]+' do
    local branch = line:match '^# branch%.head (.+)$'
    if branch then
      status.branch = branch == '(detached)' and false or branch
    elseif line:match '^# branch%.upstream ' then
      status.upstream = true
    else
      local ahead, behind = line:match '^# branch%.ab %+(%d+) %-(%d+)$'
      if ahead then
        status.ahead = tonumber(ahead)
        status.behind = tonumber(behind)
      elseif line:sub(1, 1) ~= '#' then
        status.dirty = true
      end
    end
  end
  return status
end

local function update_cache(root, status)
  if vim.deep_equal(cache[root], status) then
    return false
  end
  cache[root] = status
  return true
end

--[[ Refresh all statusline Git fields with one asynchronous Git command. ]]
function M.refresh(root)
  if not root or root == '' or running[root] then
    return
  end
  running[root] = true
  git({ 'status', '--porcelain=v2', '--branch' }, root, function(code, stdout)
    running[root] = nil
    if code == 0 and update_cache(root, parse_status(stdout)) then
      vim.cmd 'redrawstatus'
    end
  end)
end

--[[ Resolve the Git root for a buffer from gitsigns or its file or directory path. ]]
local function buffer_root(bufnr)
  local dict = vim.b[bufnr].gitsigns_status_dict
  if dict and dict.root then
    return dict.root
  end
  local path = vim.bo[bufnr].filetype == 'netrw' and vim.b[bufnr].netrw_curdir or vim.api.nvim_buf_get_name(bufnr)
  if not path or path == '' then
    return nil
  end
  return vim.fs.root(path, '.git')
end

--[[ Return cached Git status for a buffer and start a refresh when it is stale or absent. ]]
function M.get(bufnr)
  local root = buffer_root(bufnr)
  if not root then
    return nil
  end
  M.refresh(root)
  local status = cache[root] or {}
  return {
    branch = status.branch,
    root = root,
    upstream = status.upstream or false,
    ahead = status.ahead or 0,
    behind = status.behind or 0,
    dirty = status.dirty or false,
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
  local root = buffer_root(bufnr)
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
