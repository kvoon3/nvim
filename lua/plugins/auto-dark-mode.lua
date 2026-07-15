return {
  'f-person/auto-dark-mode.nvim',
  lazy = false,
  priority = 999,
  dependencies = { 'kvoon3/vitesse.nvim' },
  opts = {
    update_interval = 1000,
    set_dark_mode = function()
      vim.cmd.colorscheme 'vitesse-black'
    end,
    set_light_mode = function()
      vim.cmd.colorscheme 'vitesse-light-soft'
    end,
  },
}
