return {
  'nvim-mini/mini.test',
  version = false,
  config = function()
    require('mini.test').setup {
      collect = {
        find_files = function()
          return vim.fn.globpath('tests', '**/*_spec.lua', true, true)
        end,
      },
    }

    require('cmdr').add {
      {
        desc = 'Run tests',
        cmd = function()
          require('mini.test').run()
        end,
        cat = 'test',
      },
    }
  end,
}
