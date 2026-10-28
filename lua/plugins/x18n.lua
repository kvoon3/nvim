-- x18n (https://x18n.dev) language server + editor UI, dogfooded from the local checkout.
return {
  {
    'kvoon3/x18n.nvim',
    dir = '~/i/x18n.nvim',
    opts = function()
      return {
        lsp = {
          capabilities = require('blink.cmp').get_lsp_capabilities(),
          --[[ Only start in projects that actually use x18n; the plugin default roots
            (package.json/.git) would spawn the Node server in every JS project. ]]
          root_markers = { 'x18n.config.ts', 'x18n.config.yml', 'x18n.config.json' },
          workspace_required = true,
        },
      }
    end,
    config = function(_, opts)
      require('x18n').setup(opts)

      require('cmdr').add {
        {
          desc = 'x18n: open the web UI',
          cat = 'lsp',
          cmd = function()
            require('x18n.actions').open_ui()
          end,
        },
        {
          desc = 'x18n: extract hard strings in this file',
          cat = 'lsp',
          cmd = function()
            require('x18n.actions').extract()
          end,
        },
      }
    end,
  },
}
