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
    commander = {
      {
        desc = "Toggle markdown rendering",
        cmd = "<CMD>RenderMarkdown toggle<CR>",
        cat = "Markdown",
      },
      {
        desc = "Enable markdown rendering",
        cmd = "<CMD>RenderMarkdown enable<CR>",
        cat = "Markdown",
      },
      {
        desc = "Disable markdown rendering",
        cmd = "<CMD>RenderMarkdown disable<CR>",
        cat = "Markdown",
      },
    },
}
