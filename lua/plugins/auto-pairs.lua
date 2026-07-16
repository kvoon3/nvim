return {
  'windwp/nvim-autopairs',
  config = function()
    require('nvim-autopairs').setup {}

    require('cmdr').add {
      {
        desc = 'Toggle autopairs',
        cmd = function()
          require('nvim-autopairs').toggle()
        end,
        cat = 'autopairs',
      },
      {
        desc = 'Enable autopairs',
        cmd = function()
          require('nvim-autopairs').enable()
        end,
        cat = 'autopairs',
      },
      {
        desc = 'Disable autopairs',
        cmd = function()
          require('nvim-autopairs').disable()
        end,
        cat = 'autopairs',
      },
    }
  end,
}
