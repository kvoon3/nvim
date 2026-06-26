-- Everforest colorscheme: Lua-native port with soft background contrast
-- Kept as an alternative; the active colorscheme is managed by auto-dark-mode.nvim.
return {
  "neanias/everforest-nvim",
  lazy = true,
  config = function()
    require("everforest").setup({
      background = "soft",
    })
  end,
}
