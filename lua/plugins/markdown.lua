return {
  'MeanderingProgrammer/render-markdown.nvim',
  dependencies = { 'nvim-mini/mini.icons' },
  ---@module 'render-markdown'
  ---@type render.md.UserConfig
  opts = {
    sign = {
      enabled = false,
    },
    heading = {
      backgrounds = {},
    },
    win_options = {
      wrap = { default = false, rendered = true },
    },
  },
  config = function(_, opts)
    require('render-markdown').setup(opts)

    require('cmdr').add {
      {
        desc = 'Toggle markdown rendering',
        cmd = '<CMD>RenderMarkdown toggle<CR>',
        cat = 'markdown',
      },
      {
        desc = 'Enable markdown rendering',
        cmd = '<CMD>RenderMarkdown enable<CR>',
        cat = 'markdown',
      },
      {
        desc = 'Disable markdown rendering',
        cmd = '<CMD>RenderMarkdown disable<CR>',
        cat = 'markdown',
      },
    }
  end,
}
