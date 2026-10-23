local function active()
  --[[ Keep mini.statusline's default layout and add the existing clickable shortcuts. ]]
  local statusline = require 'mini.statusline'
  local mode, mode_hl = statusline.section_mode { trunc_width = 120 }
  local git = statusline.section_git { trunc_width = 40 }
  local diff = statusline.section_diff { trunc_width = 75 }
  local diagnostics = statusline.section_diagnostics { trunc_width = 75 }
  local lsp = statusline.section_lsp { trunc_width = 75 }
  local todos = require('project-todos').section()
  local filename = statusline.section_filename { trunc_width = 140 }
  local fileinfo = statusline.section_fileinfo { trunc_width = 120 }
  --[[ MiniStatusline.section_location appends `virtcol("$")`, which scans the
  whole line on every render (~13ms per keystroke on a 700KB single line). For
  pathological buffers show byte columns instead: %c is O(1), %v is not. ]]
  local winid = tonumber(vim.g.statusline_winid)
  local bufnr = winid and vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_buf(winid) or 0
  local location
  if require('bigfile').is_bigfile(bufnr) then
    location = '%l|%L│%2c'
  else
    location = statusline.section_location { trunc_width = 75 }
  end
  local search = statusline.section_searchcount { trunc_width = 75 }

  return statusline.combine_groups {
    { hl = mode_hl, strings = { mode } },
    { hl = 'MiniStatuslineDevinfo', strings = { git, diff, diagnostics, lsp, todos } },
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
