return {
  'nvim-mini/mini.clue',
  version = false,
  config = function()
    local clue = require 'mini.clue'
    clue.setup {
      triggers = {
        { mode = { 'n', 'x' }, keys = '<Leader>' },
        { mode = 'n', keys = '[' },
        { mode = 'n', keys = ']' },
        { mode = 'i', keys = '<C-x>' },
        { mode = { 'n', 'x' }, keys = 'g' },
        { mode = { 'n', 'x' }, keys = "'" },
        { mode = { 'n', 'x' }, keys = '`' },
        { mode = { 'n', 'x' }, keys = '"' },
        { mode = { 'i', 'c' }, keys = '<C-r>' },
        { mode = 'n', keys = '<C-w>' },
        { mode = { 'n', 'x' }, keys = 'z' },
      },
      clues = {
        clue.gen_clues.square_brackets(),
        clue.gen_clues.builtin_completion(),
        clue.gen_clues.g(),
        clue.gen_clues.marks(),
        clue.gen_clues.registers(),
        clue.gen_clues.windows(),
        clue.gen_clues.z(),
      },
    }

    require('cmdr').add {
      { desc = 'Enable key clues', cmd = clue.enable_all_triggers, cat = 'view' },
      { desc = 'Disable key clues', cmd = clue.disable_all_triggers, cat = 'view' },
    }
  end,
}
