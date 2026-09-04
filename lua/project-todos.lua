local M = {}

local cache = {}
local running = {}
local setup_done = false

local function project_root(bufnr)
  local path = vim.api.nvim_buf_get_name(bufnr)
  path = path ~= '' and path or vim.fn.getcwd()
  return vim.fs.root(path, '.git') or vim.fn.getcwd()
end

local function todo_config()
  local ok, config = pcall(require, 'todo-comments.config')
  return ok and config.loaded and config or nil
end

--[[ Keep the project-wide search asynchronous because statusline rendering is frequent and synchronous rg would block editing. ]]
function M.refresh(bufnr)
  local root = project_root(bufnr)
  if running[root] or not todo_config() then
    return
  end

  running[root] = true
  require('todo-comments.search').search(function(results)
    running[root] = nil
    cache[root] = #results
    vim.cmd 'redrawstatus'
  end, { cwd = root, disable_not_found_warnings = true })
end

function M.count(bufnr)
  local root = project_root(bufnr)
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
  return count and ('TODO:' .. count) or ''
end

--[[ Open the project's recognized TODO comments in Telescope so its normal preview and jump mappings apply. ]]
function M.open(bufnr)
  local telescope = require 'telescope'
  telescope.load_extension 'todo-comments'
  telescope.extensions['todo-comments'].todo { cwd = project_root(bufnr or vim.api.nvim_get_current_buf()) }
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
      cache[root] = nil
      M.refresh(ev.buf)
    end,
  })

  M.refresh(0)
end

return M
