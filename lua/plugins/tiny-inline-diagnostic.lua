return {
  'rachartier/tiny-inline-diagnostic.nvim',
  event = 'VeryLazy',
  priority = 1000,
  opts = {
    preset = 'modern',
    --[[ Keep the message background see-through, matching the transparent look used for other
      floating UI instead of painting a solid block over the code. ]]
    transparent_bg = true,
    options = {
      --[[ Only name the server when one line carries diagnostics from more than one source. ]]
      show_source = { enabled = true, if_many = true },
      --[[ <leader>df opens the diagnostic float; hide the inline copy underneath it. ]]
      override_open_float = true,
    },
  },
  config = function(_, opts)
    local inline_diag = require 'tiny-inline-diagnostic'
    inline_diag.setup(opts)

    require('cmdr').add {
      {
        desc = 'Toggle inline diagnostics',
        cmd = inline_diag.toggle,
        cat = 'lsp',
      },
      {
        desc = 'Toggle inline diagnostics cursor-only mode',
        cmd = inline_diag.toggle_cursor_only,
        cat = 'lsp',
      },
      {
        desc = 'Show all inline diagnostics on the cursor line',
        cmd = inline_diag.toggle_all_diags_on_cursorline,
        cat = 'lsp',
      },
      {
        desc = 'Reset inline diagnostics to defaults',
        cmd = inline_diag.reset,
        cat = 'lsp',
      },
    }
  end,
}
