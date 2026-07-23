-- Vitesse colorscheme for Neovim
-- https://github.com/kvoon3/vitesse.nvim
-- The active variant is managed by auto-dark-mode.nvim.
return {
  'kvoon3/vitesse.nvim',
  lazy = true,
  config = function()
    require('vitesse').setup {
      -- Let the terminal compose Neovim's main background consistently.
      transparent = true,
      on_highlights = function(highlights, colors)
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
