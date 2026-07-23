local function recent_projects()
  return vim.tbl_map(function(project)
    return {
      name = vim.fn.fnamemodify(project.file, ':~'):gsub('^~/', ''),
      action = function()
        vim.fn.chdir(project.file)
        Snacks.picker.explorer { cwd = project.file }
      end,
      section = 'Recent projects',
    }
  end, Snacks.dashboard.sections.projects { limit = 5, session = false, pick = false })
end

local function recent_file_path(path)
  return (' (%s)'):format(vim.fn.fnamemodify(path, ':~:.'):gsub('^~/', ''))
end

return {
  'nvim-mini/mini.starter',
  version = false,
  config = function()
    local starter = require 'mini.starter'
    starter.setup {
      items = {
        starter.sections.builtin_actions(),
        recent_projects,
        starter.sections.recent_files(10, false, recent_file_path),
      },
    }

    require('cmdr').add {
      {
        desc = 'Open start screen',
        cmd = function()
          require('mini.starter').open()
        end,
        cat = 'view',
      },
    }
  end,
}
