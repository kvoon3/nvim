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
    }
  end,
}
