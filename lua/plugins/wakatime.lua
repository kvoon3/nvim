return {
  'wakatime/vim-wakatime',
  lazy = false,
  config = function()
    require('cmdr').add {
      {
        desc = 'Show WakaTime today',
        cmd = '<CMD>WakaTimeToday<CR>',
        cat = 'wakatime',
      },
      {
        desc = 'Open WakaTime dashboard',
        cmd = function()
          vim.ui.open 'https://wakatime.com/dashboard'
        end,
        cat = 'wakatime',
      },
      {
        desc = 'Show WakaTime file experts',
        cmd = '<CMD>WakaTimeFileExpert<CR>',
        cat = 'wakatime',
      },
    }
  end,
}
