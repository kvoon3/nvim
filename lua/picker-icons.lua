--[[ File icons for the picker surfaces real-icons does not patch.

real-icons' Snacks integration replaces the icon of every list row (it wraps
`picker.format.filename`). The explorer's preview pane is not a list row: when
the cursor sits on a directory, `snacks/picker/preview.lua` draws that
directory's contents itself through `Snacks.util.icon()`, so the entries come
out as Nerd Font glyphs while the list beside them shows the Catppuccin images.

This module replaces only that renderer with the same resolve-and-render path
real-icons uses, and re-draws the entries on `User RealIconsUpdated` so a cold
cache upgrades from the glyph to the image without moving the cursor. It is a
patch over a plugin private, kept here because real-icons only owns the list
integration; move it into the integration module if the fork ever grows one. ]]

local M = {}

-- Same namespace the Snacks preview uses, so `preview:reset()`/`clear()` still
-- wipes our extmarks when the pane switches to another item.
local namespace = vim.api.nvim_create_namespace 'snacks.picker.preview'

-- The listing currently on screen, so a cache or colorscheme update can redraw
-- the same extmarks instead of rebuilding the pane.
local shown = {}

local function segment(entry)
  local ok, icons = pcall(require, 'real-icons')
  if not ok then
    return nil
  end
  local success, result = pcall(icons.segment, entry.is_dir and 'directory' or 'file', entry.path)
  if not success or type(result) ~= 'table' then
    return nil
  end
  return result
end

local function draw(buffer, entry)
  local name_hl = entry.is_dir and 'Directory' or nil
  local icon = segment(entry)
  local chunks
  if icon then
    chunks = { { icon.text .. ' ', icon.hl }, { entry.name, name_hl } }
  else
    local glyph, hl = Snacks.util.icon(entry.name, entry.is_dir and 'directory' or 'file')
    chunks = { { glyph .. ' ', hl }, { entry.name, name_hl } }
  end
  entry.id = vim.api.nvim_buf_set_extmark(buffer, namespace, entry.row, 0, { id = entry.id, virt_text = chunks })
end

--[[ Mirror of Snacks' directory previewer: same layout and sorting, but each
entry keeps a stable extmark id so it can be redrawn in place. ]]
local function directory(ctx)
  local preview = ctx.preview
  preview:reset()
  preview:minimal()

  local path = Snacks.picker.util.path(ctx.item)
  if not path then
    preview:notify('Item has no `file`', 'error')
    return
  end
  preview:set_title(ctx.item.title or vim.fn.fnamemodify(path, ':t'))

  local entries = {}
  for file, kind in vim.fs.dir(path) do
    kind = kind or Snacks.util.path_type(path .. '/' .. file)
    entries[#entries + 1] = { name = file, path = path .. '/' .. file, is_dir = kind == 'directory' }
  end
  preview:set_lines(vim.split(string.rep('\n', #entries), '\n'))

  table.sort(entries, function(a, b)
    if a.is_dir ~= b.is_dir then
      return a.is_dir
    end
    return a.name < b.name
  end)

  shown = { buffer = ctx.buf, entries = entries }
  for row, entry in ipairs(entries) do
    entry.row = row - 1
    draw(ctx.buf, entry)
  end
end

local function redraw()
  if not shown.buffer or not vim.api.nvim_buf_is_valid(shown.buffer) then
    return
  end
  for _, entry in ipairs(shown.entries) do
    pcall(draw, shown.buffer, entry)
  end
end

function M.setup()
  local ok, preview = pcall(require, 'snacks.picker.preview')
  if not ok then
    return false, 'snacks picker preview is not available'
  end
  if preview._picker_icons_patched then
    return true
  end

  local original = preview.directory
  preview.directory = function(ctx)
    --[[ Fall back to the plugin's own renderer when real-icons is missing, so
the preview never regresses to a blank icon. ]]
    if not pcall(require, 'real-icons') then
      return original(ctx)
    end
    return directory(ctx)
  end
  preview._picker_icons_patched = true

  vim.api.nvim_create_autocmd('User', {
    group = vim.api.nvim_create_augroup('PickerIcons', { clear = true }),
    pattern = 'RealIconsUpdated',
    callback = redraw,
  })
  return true
end

return M
