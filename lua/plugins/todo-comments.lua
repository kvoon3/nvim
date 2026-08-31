return {
  'folke/todo-comments.nvim',
  dependencies = { 'nvim-lua/plenary.nvim' },
  event = 'VeryLazy',
  opts = {},
  config = function(_, opts)
    require('todo-comments').setup(opts)

    require('cmdr').add {
      {
        desc = 'Search TODO comments',
        cmd = function()
          Snacks.picker.todo_comments()
        end,
        cat = 'search',
      },
      {
        desc = 'Search TODO/FIX/FIXME comments',
        cmd = function()
          Snacks.picker.todo_comments { keywords = { 'TODO', 'FIX', 'FIXME' } }
        end,
        cat = 'search',
      },
      {
        desc = 'Go to next TODO comment',
        cmd = function()
          require('todo-comments').jump_next()
        end,
        cat = 'search',
      },
      {
        desc = 'Go to previous TODO comment',
        cmd = function()
          require('todo-comments').jump_prev()
        end,
        cat = 'search',
      },
      {
        desc = 'Toggle TODO comment highlighting',
        cmd = function()
          local tc = require 'todo-comments'
          if vim.b.todo_comments_disabled then
            tc.enable()
            vim.b.todo_comments_disabled = false
          else
            tc.disable()
            vim.b.todo_comments_disabled = true
          end
        end,
        cat = 'search',
      },
    }
  end,
}
