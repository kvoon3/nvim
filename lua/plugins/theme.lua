local function pick_colorscheme()
  Snacks.picker.colorschemes()
end

return {
  dir = vim.fn.stdpath 'config' .. '/lua/theme',
  lazy = false,
  config = function()
    local theme = require 'theme'

    vim.keymap.set('n', '<leader>cs', pick_colorscheme, { desc = 'Switch colorscheme' })

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
      {
        desc = 'Switch colorscheme',
        cmd = pick_colorscheme,
        keys = { 'n', '<leader>cs' },
        cat = 'theme',
      },
    }
  end,
}
