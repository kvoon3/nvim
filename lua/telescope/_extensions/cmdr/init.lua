local pickers = require 'telescope.pickers'
local finders = require 'telescope.finders'
local conf = require('telescope.config').values
local themes = require 'telescope.themes'
local actions = require 'telescope.actions'
local action_state = require 'telescope.actions.state'
local entry_display = require 'telescope.pickers.entry_display'
local cmdr = require 'cmdr'

local function show(commands)
  local widths = { desc = 0, keys = 0, cat = 0 }
  for _, cmd in ipairs(commands) do
    widths.desc = math.max(widths.desc, #cmd.desc)
    widths.keys = math.max(widths.keys, #(cmd.keys_str or ''))
    widths.cat = math.max(widths.cat, #cmd.cat)
  end

  local displayer = entry_display.create {
    separator = '  ',
    items = {
      { width = widths.desc },
      { width = widths.keys },
      { width = widths.cat },
    },
  }

  pickers
    .new(themes.get_dropdown(), {
      prompt_title = 'Cmdr',
      finder = finders.new_table {
        results = commands,
        entry_maker = function(entry)
          return {
            value = entry,
            ordinal = entry.desc,
            display = function(_)
              return displayer {
                entry.desc,
                entry.keys_str or '',
                entry.cat,
              }
            end,
          }
        end,
      },
      sorter = conf.generic_sorter(),
      attach_mappings = function(prompt_bufnr, _)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          if not selection then
            return
          end
          local cmd = selection.value
          cmdr.mark_used(cmd)
          if type(cmd.cmd) == 'function' then
            cmd.cmd()
          else
            local keys = vim.api.nvim_replace_termcodes(cmd.cmd, true, false, true)
            vim.api.nvim_feedkeys(keys, 't', true)
          end
        end)
        return true
      end,
    })
    :find()
end

return require('telescope').register_extension {
  exports = {
    show = show,
  },
}
