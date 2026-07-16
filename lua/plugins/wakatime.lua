return {
  'wakatime/vim-wakatime',
  lazy = false,
  config = function()
    require('cmdr').add {
      {
        desc = 'Show WakaTime today',
        cmd = '<CMD>WakatimeToday<CR>',
        cat = 'wakatime',
      },
      {
        desc = 'Open WakaTime dashboard',
        cmd = '<CMD>WakatimeOpenDashboard<CR>',
        cat = 'wakatime',
      },
      {
        desc = 'Show WakaTime URL for current file',
        cmd = '<CMD>WakaTimeUrl<CR>',
        cat = 'wakatime',
      },
    }
  end,
}
