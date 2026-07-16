return {
  dir = vim.fn.stdpath 'config' .. '/lua/theme',
  lazy = false,
  dependencies = { 'nvim-telescope/telescope.nvim' },
  config = function()
    local theme = require 'theme'

    require('cmdr').add {
      {
        desc = 'Set light theme',
        cmd = theme.pick_light,
        cat = 'theme',
      },
      {
        desc = 'Set dark theme',
        cmd = theme.pick_dark,
        cat = 'theme',
      },
    }
  end,
}
