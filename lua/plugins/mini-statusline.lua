local function active()
  --[[ Keep mini.statusline's default layout and add the existing clickable shortcuts. ]]
  local statusline = require 'mini.statusline'
  local mode, mode_hl = statusline.section_mode { trunc_width = 120 }
  local git = statusline.section_git { trunc_width = 40 }
  local diff = statusline.section_diff { trunc_width = 75 }
  local diagnostics = statusline.section_diagnostics { trunc_width = 75 }
  local lsp = statusline.section_lsp { trunc_width = 75 }
  local filename = statusline.section_filename { trunc_width = 140 }
  local fileinfo = statusline.section_fileinfo { trunc_width = 120 }
  local location = statusline.section_location { trunc_width = 75 }
  local search = statusline.section_searchcount { trunc_width = 75 }

  return statusline.combine_groups {
    { hl = mode_hl, strings = { mode } },
    { hl = 'MiniStatuslineDevinfo', strings = { git, diff, diagnostics, lsp } },
    '%<',
    { hl = 'MiniStatuslineFilename', strings = { filename } },
    '%=',
    { hl = 'MiniStatuslineFileinfo', strings = { fileinfo, require('statusline').actions() } },
    { hl = mode_hl, strings = { search, location } },
  }
end

return {
  'nvim-mini/mini.statusline',
  version = false,
  dependencies = { 'nvim-mini/mini.icons' },
  config = function()
    require('mini.statusline').setup {
      content = { active = active },
    }

    require('cmdr').add {
      {
        desc = 'Toggle statusline',
        cmd = function()
          vim.o.laststatus = vim.o.laststatus == 0 and 2 or 0
        end,
        cat = 'view',
      },
    }
  end,
}
