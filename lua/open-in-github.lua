local M = {}

local function get_git_root()
  local result = vim.fn.systemlist 'git rev-parse --show-toplevel'
  if vim.v.shell_error ~= 0 or #result == 0 then
    return nil
  end
  return vim.fn.trim(result[1])
end

local function get_remote_url(root)
  local result = vim.fn.systemlist('git -C ' .. vim.fn.shellescape(root) .. ' remote get-url origin')
  if vim.v.shell_error ~= 0 or #result == 0 then
    return nil
  end
  return vim.fn.trim(result[1])
end

local function parse_github_url(remote)
  local user, repo = remote:match '^git@github%.com:(.+)/(.+)%.git$'
  if not user then
    user, repo = remote:match '^git@github%.com:(.+)/(.+)$'
  end
  if not user then
    user, repo = remote:match '^https?://github%.com/(.+)/(.+)%.git$'
  end
  if not user then
    user, repo = remote:match '^https?://github%.com/(.+)/(.+)$'
  end
  if user and repo then
    return string.format('https://github.com/%s/%s', user, repo)
  end
  return nil
end

local function plugin_spec_to_url(spec)
  local user, repo = spec:match '^([^/]+)/([^/]+)$'
  if user and repo then
    repo = repo:gsub('%.git$', '')
    return string.format('https://github.com/%s/%s', user, repo)
  end
  return nil
end

local function get_branch(root)
  local result = vim.fn.systemlist('git -C ' .. vim.fn.shellescape(root) .. ' branch --show-current')
  if vim.v.shell_error ~= 0 or #result == 0 or result[1] == '' then
    result = vim.fn.systemlist('git -C ' .. vim.fn.shellescape(root) .. ' rev-parse HEAD')
    if vim.v.shell_error ~= 0 or #result == 0 then
      return nil
    end
  end
  return vim.fn.trim(result[1])
end

local function get_relative_path(root, filepath)
  if not filepath or filepath == '' then
    return nil
  end
  if filepath:sub(1, #root) ~= root then
    return nil
  end
  local rel = filepath:sub(#root + 2)
  if rel == '' then
    return nil
  end
  return rel
end

local function encode_url_part(part)
  return part:gsub(' ', '%%20')
end

local function get_line_anchor()
  local mode = vim.fn.mode()
  if mode == 'v' or mode == 'V' or mode == '\22' then
    local start_pos = vim.fn.getpos 'v'
    local end_pos = vim.fn.getpos '.'
    local start_line = start_pos[2]
    local end_line = end_pos[2]
    if start_line > end_line then
      start_line, end_line = end_line, start_line
    end
    if start_line == end_line then
      return '#L' .. start_line
    end
    return '#L' .. start_line .. '-L' .. end_line
  end
  return '#L' .. vim.fn.line '.'
end

local function open_url(url)
  vim.ui.open(url)
end

function M.open_in_github()
  local root = get_git_root()
  if not root then
    vim.notify('Not in a git repository', vim.log.levels.WARN)
    return
  end

  local remote = get_remote_url(root)
  if not remote then
    vim.notify("No 'origin' remote found", vim.log.levels.WARN)
    return
  end

  local base_url = parse_github_url(remote)
  if not base_url then
    vim.notify('Remote is not a GitHub repository: ' .. remote, vim.log.levels.WARN)
    return
  end

  local branch = get_branch(root)
  if not branch then
    vim.notify('Could not determine branch or commit', vim.log.levels.WARN)
    return
  end

  local filepath = vim.fn.expand '%:p'
  local rel = get_relative_path(root, filepath)

  local url
  if rel then
    url = base_url .. '/blob/' .. encode_url_part(branch) .. '/' .. encode_url_part(rel) .. get_line_anchor()
  else
    url = base_url
  end

  open_url(url)
end

--[[ Open the GitHub repository of a lazy.nvim-managed plugin in the default browser. ]]
function M.open_plugin_in_github()
  local ok, lazy_config = pcall(require, 'lazy.core.config')
  if not ok or not lazy_config.plugins then
    vim.notify('lazy.nvim plugin list is not available', vim.log.levels.WARN)
    return
  end

  local plugins = {}
  for name, plugin in pairs(lazy_config.plugins) do
    local url = plugin.url or plugin_spec_to_url(plugin[1])
    if url then
      local github_url = parse_github_url(url) or url
      table.insert(plugins, { name = name, url = github_url })
    end
  end

  if #plugins == 0 then
    vim.notify('No plugins found', vim.log.levels.WARN)
    return
  end

  table.sort(plugins, function(a, b)
    return a.name < b.name
  end)

  local function open_plugin(plugin)
    open_url(plugin.url)
  end

  local telescope_ok, telescope = pcall(function()
    return {
      pickers = require 'telescope.pickers',
      finders = require 'telescope.finders',
      conf = require('telescope.config').values,
      actions = require 'telescope.actions',
      action_state = require 'telescope.actions.state',
    }
  end)

  if telescope_ok then
    telescope.pickers
      .new({}, {
        prompt_title = 'Select plugin to open in GitHub',
        finder = telescope.finders.new_table {
          results = plugins,
          entry_maker = function(plugin)
            return {
              value = plugin,
              display = plugin.name,
              ordinal = plugin.name,
            }
          end,
        },
        sorter = telescope.conf.generic_sorter {},
        attach_mappings = function(prompt_bufnr)
          telescope.actions.select_default:replace(function()
            local selection = telescope.action_state.get_selected_entry()
            telescope.actions.close(prompt_bufnr)
            if selection then
              open_plugin(selection.value)
            end
          end)
          return true
        end,
      })
      :find()
    return
  end

  local items = vim.tbl_map(function(plugin)
    return plugin.name
  end, plugins)

  vim.ui.select(items, { prompt = 'Select plugin:' }, function(choice)
    if not choice then
      return
    end
    for _, plugin in ipairs(plugins) do
      if plugin.name == choice then
        open_plugin(plugin)
        return
      end
    end
  end)
end

--[[ Open the GitHub repository of the lazy.nvim plugin that owns the current buffer. ]]
function M.open_current_plugin_in_github()
  local filepath = vim.fn.expand '%:p'
  if not filepath or filepath == '' then
    vim.notify('Current buffer is not a file', vim.log.levels.WARN)
    return
  end

  local lazy_root = vim.fn.stdpath 'data' .. '/lazy'
  if filepath:sub(1, #lazy_root) ~= lazy_root then
    vim.notify('Current file is not inside a lazy.nvim plugin directory', vim.log.levels.WARN)
    return
  end

  local rel = filepath:sub(#lazy_root + 2)
  local plugin_name = rel:match '^([^/]+)'
  if not plugin_name then
    vim.notify('Could not determine plugin name from path', vim.log.levels.WARN)
    return
  end

  local ok, lazy_config = pcall(require, 'lazy.core.config')
  if not ok or not lazy_config.plugins then
    vim.notify('lazy.nvim plugin list is not available', vim.log.levels.WARN)
    return
  end

  local plugin = lazy_config.plugins[plugin_name]
  if not plugin then
    vim.notify('Plugin not found: ' .. plugin_name, vim.log.levels.WARN)
    return
  end

  local url = plugin.url or plugin_spec_to_url(plugin[1])
  if not url then
    vim.notify('Could not determine repository URL for ' .. plugin_name, vim.log.levels.WARN)
    return
  end

  open_url(parse_github_url(url) or url)
end

vim.api.nvim_create_user_command('OpenInGitHub', M.open_in_github, {
  desc = 'Open current file or repository in GitHub',
})

vim.api.nvim_create_user_command('OpenPluginInGitHub', M.open_plugin_in_github, {
  desc = 'Open a lazy.nvim plugin repository in GitHub',
})

vim.api.nvim_create_user_command('OpenCurrentPluginInGitHub', M.open_current_plugin_in_github, {
  desc = 'Open the GitHub repository of the plugin owning the current file',
})

return M
