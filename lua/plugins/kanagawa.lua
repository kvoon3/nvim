return {
  'rebelot/kanagawa.nvim',
  lazy = true,
  config = function()
    require('cmdr').add {
      {
        desc = 'Compile Kanagawa',
        cmd = function()
          vim.cmd 'KanagawaCompile'
        end,
        cat = 'theme',
      },
      {
        desc = 'Switch Kanagawa variant',
        cmd = function()
          vim.ui.select({ 'wave', 'dragon', 'lotus' }, { prompt = 'Kanagawa variant:' }, function(variant)
            if variant then
              vim.cmd('colorscheme kanagawa-' .. variant)
            end
          end)
        end,
        cat = 'theme',
      },
    }
  end,
}
