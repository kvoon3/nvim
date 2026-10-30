-- Vitesse colorscheme for Neovim
-- https://github.com/kvoon3/vitesse.nvim
-- The active variant is managed by auto-dark-mode.nvim.

--[[ Mix `alpha` (0..1) of `tint` into `base` and return the result as `#rrggbb`.
Both arguments are palette colours, already in that form. ]]
local function mix(base, tint, alpha)
  local function channels(hex)
    return tonumber(hex:sub(2, 3), 16), tonumber(hex:sub(4, 5), 16), tonumber(hex:sub(6, 7), 16)
  end
  local br, bg, bb = channels(base)
  local tr, tg, tb = channels(tint)
  return string.format(
    '#%02x%02x%02x',
    math.floor(br + (tr - br) * alpha + 0.5),
    math.floor(bg + (tg - bg) * alpha + 0.5),
    math.floor(bb + (tb - bb) * alpha + 0.5)
  )
end

return {
  'kvoon3/vitesse.nvim',
  lazy = true,
  config = function()
    require('vitesse').setup {
      -- Let the terminal compose Neovim's main background consistently.
      transparent = true,
      on_highlights = function(highlights, colors)
        --[[ The scheme's visual background sits within a few percent of the canvas and the
        terminal paints its own background underneath, so a selection barely separates from
        plain text. Lift it into a mid grey, then keep a green cast: grey enough to stay calm,
        tinted enough to read as a selection rather than as another syntax colour. A light
        canvas needs a smaller push — on white the dark-mode weight reads as a shadow. ]]
        local light = vim.o.background == 'light'
        local grey = mix(colors.bg_visual, colors.fg, light and 0.08 or 0.18)
        local selection = mix(grey, colors.green, light and 0.18 or 0.25)
        highlights.Visual = { bg = selection }
        highlights.VisualNOS = { bg = selection }

        highlights.MiniStatuslineModeNormal = { fg = colors.bg, bg = colors.green, bold = true }
        highlights.MiniStatuslineModeInsert = { fg = colors.bg, bg = colors.blue, bold = true }
        highlights.MiniStatuslineModeVisual = { fg = colors.bg, bg = colors.magenta, bold = true }
        highlights.MiniStatuslineModeReplace = { fg = colors.bg, bg = colors.red, bold = true }
        highlights.MiniStatuslineModeCommand = { fg = colors.bg, bg = colors.yellow, bold = true }
        highlights.MiniStatuslineModeOther = { fg = colors.bg, bg = colors.cyan, bold = true }
        highlights.MiniStatuslineDevinfo = { link = 'StatusLine' }
        highlights.MiniStatuslineFilename = { link = 'StatusLineNC' }
        highlights.MiniStatuslineFileinfo = { link = 'StatusLine' }
        highlights.MiniStatuslineInactive = { link = 'StatusLineNC' }
      end,
    }
  end,
}
