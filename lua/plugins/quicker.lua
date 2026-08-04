return {
  'stevearc/quicker.nvim',
  ft = 'qf',
  opts = {},
  init = function()
    require('cmdr').add {
      {
        desc = 'Toggle quickfix list',
        cmd = function()
          require('quicker').toggle()
        end,
        cat = 'quickfix',
      },
      {
        desc = 'Toggle location list',
        cmd = function()
          require('quicker').toggle { loclist = true }
        end,
        cat = 'quickfix',
      },
    }
  end,
}
