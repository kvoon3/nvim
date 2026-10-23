local M = {}

local cache = {}
local running = {}
local last_search = {}
local setup_done = false

local MAX_SHOWN = 5000
local MIN_INTERVAL = 30 -- seconds between searches for the same root
local MARKERS = { '.git', 'package.json', 'pnpm-workspace.yaml', 'Cargo.toml', 'go.mod', 'pyproject.toml' }

--[[ Only treat a directory as a project when it holds a marker. Opening a file in
/tmp used to fall back to the cwd, so rg walked all of /tmp, failed on unreadable
files (exit code 2) and was respawned on every statusline refresh.
$HOME stays excluded: it holds ~/Library and would take minutes to walk. ]]
local function project_root(bufnr)
  local path = vim.api.nvim_buf_get_name(bufnr)
  path = path ~= '' and path or vim.fn.getcwd()
  local root = vim.fs.root(path, MARKERS) or vim.fs.root(vim.fn.getcwd(), MARKERS)
  return root ~= vim.fn.expand '~' and root or nil
end

local function todo_config()
  local ok, config = pcall(require, 'todo-comments.config')
  return ok and config.loaded and config or nil
end

--[[ Keep the project-wide search asynchronous because statusline rendering is frequent and synchronous rg would block editing. ]]
function M.refresh(bufnr)
  local root = project_root(bufnr)
  if not root or running[root] or not todo_config() then
    return
  end

  --[[ Throttle per root: the statusline calls this on every render, so a slow or
  failing search (rg exit code 2) must not be respawned continuously. ]]
  local now = os.time()
  if last_search[root] and now - last_search[root] < MIN_INTERVAL then
    return
  end
  last_search[root] = now

  running[root] = true
  require('todo-comments.search').search(function(results)
    running[root] = nil
    cache[root] = #(results or {})
    vim.cmd 'redrawstatus'
  end, { cwd = root, disable_not_found_warnings = true })
end

function M.count(bufnr)
  local root = project_root(bufnr)
  if not root then
    return nil
  end
  if cache[root] == nil then
    M.refresh(bufnr)
  end
  return cache[root]
end

function M.section(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if vim.bo[bufnr].buftype ~= '' then
    return ''
  end
  local count = M.count(bufnr)
  if not count then
    return ''
  end
  --[[ Past a few thousand the exact number is noise and only squeezes the footer, so clamp the display while keeping count truthful. ]]
  return 'TODO:' .. (count > MAX_SHOWN and MAX_SHOWN .. '+' or count)
end

--[[ Open the project's recognized TODO comments in the Snacks picker so its preview and jump mappings apply. ]]
function M.open(bufnr)
  local root = project_root(bufnr or vim.api.nvim_get_current_buf())
  if not root then
    vim.notify('project-todos: no project root above the current file, skipping $HOME-wide search', vim.log.levels.WARN)
    return
  end
  Snacks.picker.todo_comments { cwd = root }
end

--[[ Refresh on entering a project and after writes so the cached footer count follows saved changes. ]]
function M.setup()
  if setup_done then
    return
  end
  setup_done = true

  local group = vim.api.nvim_create_augroup('ProjectTodos', { clear = true })
  vim.api.nvim_create_autocmd({ 'BufEnter', 'FocusGained' }, {
    group = group,
    callback = function(ev)
      M.refresh(ev.buf)
    end,
  })
  vim.api.nvim_create_autocmd('BufWritePost', {
    group = group,
    callback = function(ev)
      local root = project_root(ev.buf)
      if root then
        cache[root] = nil
        last_search[root] = nil
      end
      M.refresh(ev.buf)
    end,
  })

  M.refresh(0)
end

return M
