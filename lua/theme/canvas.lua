--[[ The colour the editor paints behind text, even when the scheme is transparent.

Animations that fade a region in have to blend toward *some* colour, so a
colorscheme that leaves `Normal` without a background used to fall back to plain
white or black. White is brighter than any light theme's canvas, so the fade
flashed a patch that belonged to no theme.

Ask the scheme for the canvas it would have painted, then the surfaces that keep
a background under `transparent`, and only then fall back to white/black. ]]

local M = {}

--[[ Color schemes that publish the canvas they omit from `Normal`, keyed by the
first word of `g:colors_name`. Called only when `Normal` has no background. ]]
local published = {
  vitesse = function()
    local style = (require('vitesse').styles or {})[vim.o.background]
    local palette = require('vitesse.palette').get(style)
    return palette and palette.bg
  end,
}

--[[ Elevated surfaces keep their background under `transparent`, so they are the
closest stand-in for the canvas when the scheme publishes nothing. ]]
local surfaces = { 'NormalNC', 'NormalFloat', 'Pmenu', 'ColorColumn', 'CursorLine' }

local function color(value)
  if type(value) == 'number' then
    return value
  end
  if type(value) == 'string' and value:match '^#%x%x%x%x%x%x$' then
    return tonumber(value:sub(2), 16)
  end
  return nil
end

local function background(name)
  local hl = vim.api.nvim_get_hl(0, { name = name, link = false })
  return color(hl and hl.bg)
end

local function scheme_canvas()
  local scheme = (vim.g.colors_name or ''):match '^(%w+)'
  local publisher = scheme and published[scheme]
  if not publisher then
    return nil
  end
  local ok, value = pcall(publisher)
  return ok and color(value) or nil
end

---Canvas colour as `0xRRGGBB`.
function M.get()
  local canvas = background 'Normal' or scheme_canvas()
  if canvas then
    return canvas
  end

  for _, surface in ipairs(surfaces) do
    canvas = background(surface)
    if canvas then
      return canvas
    end
  end

  return vim.o.background == 'light' and 0xffffff or 0x000000
end

return M
