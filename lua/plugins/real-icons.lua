local icons = require 'catppuccin-icons'

local function pack_for(background)
  local packs, ready = icons.packs()
  if not ready then
    -- Pack specs exist but the build step has not produced PNGs yet: glyph fallback until then.
    return 'builtin', packs
  end
  return 'catppuccin_' .. (background == 'light' and 'latte' or 'mocha'), packs
end

return {
  'Mirsmog/real-icons.nvim',
  lazy = false,
  dependencies = { 'nvim-mini/mini.icons' },
  build = function()
    icons.build { notify = true }
  end,
  opts = {
    integrations = {
      snacks_picker = true,
      mini_statusline = true,
    },
  },
  config = function(_, opts)
    local pack, packs = pack_for(vim.o.background)
    opts.packs = vim.tbl_extend('force', opts.packs or {}, packs or {})
    opts.pack = pack

    require('real-icons').setup(opts)

    vim.api.nvim_create_autocmd('OptionSet', {
      pattern = 'background',
      callback = function()
        local next_pack = pack_for(vim.o.background)
        if require('real-icons').pack() ~= next_pack then
          require('real-icons').use_pack(next_pack, { notify = false })
        end
      end,
    })

    require('cmdr').add {
      {
        desc = 'Choose icon pack',
        cmd = function()
          require('real-icons').select_pack()
        end,
        cat = 'icons',
      },
      {
        desc = 'Preview icons',
        cmd = function()
          require('real-icons').demo()
        end,
        cat = 'icons',
      },
      {
        desc = 'Rebuild icon files',
        cmd = function()
          icons.build { force = true, notify = true }
        end,
        cat = 'icons',
      },
      {
        desc = 'Check icon setup',
        cmd = function()
          vim.cmd 'checkhealth real-icons'
        end,
        cat = 'icons',
      },
    }
  end,
}
