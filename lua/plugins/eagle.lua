-- Floating diagnostics + LSP hover window that opens on mouse hover (or :EagleWin).
return {
  'soulis-1256/eagle.nvim',
  event = 'VeryLazy',
  opts = {
    --[[ No keymap is bound here; reach the window via the command palette or :EagleWin. ]]
    keyboard_mode = true,
  },
  config = function(_, opts)
    require('eagle').setup(opts)

    --[[ Mouse hovering only produces <MouseMove> events when this global option is on. ]]
    vim.o.mousemoveevent = true

    require('cmdr').add {
      {
        desc = 'Toggle eagle diagnostics and LSP info window',
        cmd = '<CMD>EagleWin<CR>',
        cat = 'lsp',
      },
      {
        desc = 'Toggle eagle window headers',
        cmd = '<CMD>EagleWinToggleHeaders<CR>',
        cat = 'lsp',
      },
    }
  end,
}
