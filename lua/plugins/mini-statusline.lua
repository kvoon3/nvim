local product = require 'product-icons'

--[[ Diagnostics keep their severity colour while the count next to them stays
in the devinfo colour, so each sign restores the group the section was opened
with. ]]
local function severity(name)
  return product.statusline(name, { restore = 'MiniStatuslineDevinfo' }) .. ' '
end

--[[ Prefix the project TODO count with its product icon; the count alone still
reads fine when the icon has no glyph on an image-less terminal. ]]
local function todo_section()
  local section = require('project-todos').section()
  if section == '' then
    return ''
  end
  local icon = product.statusline 'todo'
  return icon == '' and section or (icon .. ' ' .. section)
end

local function active()
  --[[ Keep mini.statusline's default layout minus the filename, swap its Nerd Font
  glyphs for product icons, and add the existing clickable shortcuts. ]]
  local statusline = require 'mini.statusline'
  local mode, mode_hl = statusline.section_mode { trunc_width = 120 }
  local git = statusline.section_git { trunc_width = 40, icon = product.statusline 'branch' }
  local diff = statusline.section_diff { trunc_width = 75, icon = product.statusline 'diff' }
  local diagnostics = statusline.section_diagnostics {
    trunc_width = 75,
    icon = '',
    signs = {
      ERROR = severity 'error',
      WARN = severity 'warning',
      INFO = severity 'info',
      HINT = severity 'hint',
    },
  }
  local lsp = statusline.section_lsp { trunc_width = 75, icon = product.statusline 'lsp' }
  local todos = todo_section()
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
    --[[ Only the mode and devinfo sit at the left now; a narrow window cuts there
    instead of dropping the fileinfo, actions and location. ]]
    '%<%=',
    { hl = 'MiniStatuslineFileinfo', strings = { fileinfo, require('statusline').actions() } },
    { hl = mode_hl, strings = { search, location } },
  }
end

return {
  'nvim-mini/mini.statusline',
  version = false,
  dependencies = { 'nvim-mini/mini.icons' },
  config = function()
    --[[ The winbar already names the buffer and the footer stays icon-free, so
    mini.statusline must not prepend a filetype icon to the fileinfo section. ]]
    require('mini.statusline').setup {
      use_icons = false,
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
