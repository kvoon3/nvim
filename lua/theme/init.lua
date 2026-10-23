local M = {}

local runtime_file = vim.fn.stdpath 'data' .. '/theme_settings.json'
local default_file =
  vim.fn.fnamemodify(vim.api.nvim_get_runtime_file('lua/theme/default-theme-settings.json', false)[1] or '', ':p')

--[[ Read the runtime theme settings as a table, or nil if missing/invalid. ]]
local function read_settings()
  local f = io.open(runtime_file, 'r')
  if not f then
    return nil
  end
  local content = f:read '*a'
  f:close()
  local ok, data = pcall(vim.json.decode, content)
  if ok and type(data) == 'table' then
    return data
  end
  return nil
end

--[[ Persist the runtime theme settings table. ]]
local function write_settings(data)
  local f = io.open(runtime_file, 'w')
  if not f then
    vim.notify('theme: failed to write ' .. runtime_file, vim.log.levels.ERROR)
    return
  end
  f:write(vim.json.encode(data))
  f:close()
end

--[[ Copy the bundled default settings to the runtime path if no runtime file exists yet. ]]
local function ensure_runtime_settings()
  local f = io.open(runtime_file, 'r')
  if f then
    f:close()
    return
  end

  local src = io.open(default_file, 'r')
  if not src then
    vim.notify('theme: default settings not found at ' .. default_file, vim.log.levels.ERROR)
    return
  end
  local content = src:read '*a'
  src:close()

  local dest = io.open(runtime_file, 'w')
  if not dest then
    vim.notify('theme: failed to create ' .. runtime_file, vim.log.levels.ERROR)
    return
  end
  dest:write(content)
  dest:close()
end

--[[ Return a theme value from settings, falling back to the bundled default. ]]
local function get(mode)
  local settings = read_settings()
  if settings and settings[mode] then
    return settings[mode]
  end

  local src = io.open(default_file, 'r')
  if not src then
    return mode == 'light' and 'vitesse-light-soft' or 'vitesse-black'
  end
  local content = src:read '*a'
  src:close()
  local ok, data = pcall(vim.json.decode, content)
  if ok and type(data) == 'table' and data[mode] then
    return data[mode]
  end
  return mode == 'light' and 'vitesse-light-soft' or 'vitesse-black'
end

function M.get_light()
  return get 'light'
end

function M.get_dark()
  return get 'dark'
end

function M.set_light(name)
  local settings = read_settings() or {}
  settings.light = name
  write_settings(settings)
end

function M.set_dark(name)
  local settings = read_settings() or {}
  settings.dark = name
  write_settings(settings)
end

--[[ Open a Snacks colorscheme picker for the given mode and save the choice on confirm.
Snacks previews each entry live and restores the previous scheme on close; we only persist the choice. ]]
local function pick(mode, title)
  local set = mode == 'light' and M.set_light or M.set_dark

  Snacks.picker.colorschemes {
    title = title,
    confirm = function(picker, item)
      picker:close()
      if not item then
        return
      end

      --[[ Drop the preview snapshot so WinClosed does not revert to the previous scheme. ]]
      picker.preview.state.colorscheme = nil
      --[[ Preview normally applies the scheme; re-apply so an immediate confirm still lands. ]]
      pcall(vim.cmd.colorscheme, item.text)
      set(item.text)
    end,
  }
end

function M.pick_light()
  pick('light', 'Set light theme')
end

function M.pick_dark()
  pick('dark', 'Set dark theme')
end

ensure_runtime_settings()

return M
