return {
  'f-person/auto-dark-mode.nvim',
  lazy = false,
  priority = 999,
  dependencies = {
    'kvoon3/vitesse.nvim',
    { dir = vim.fn.stdpath 'config' .. '/lua/theme' },
  },
  opts = {
    update_interval = 1000,
    set_dark_mode = function()
      vim.cmd.colorscheme(require('theme').get_dark())
    end,
    set_light_mode = function()
      vim.cmd.colorscheme(require('theme').get_light())
    end,
  },
}
