return {
  -- Track master: 0.1.8 still calls nvim-treesitter.parsers.ft_to_lang,
  -- which was removed on nvim-treesitter main (preview crashes on TS/etc).
  'nvim-telescope/telescope.nvim',
  branch = 'master',
  dependencies = { 'nvim-lua/plenary.nvim' },
  config = function()
    local telescope = require 'telescope'
    local actions = require 'telescope.actions'

    telescope.setup {
      defaults = {
        -- Default horizontal preview_cutoff is 120; narrower windows
        -- hide the preview entirely (looks like "preview disappeared").
        layout_strategy = 'horizontal',
        layout_config = {
          width = 0.9,
          height = 0.9,
          horizontal = {
            preview_width = 0.55,
            preview_cutoff = 0,
          },
        },
        mappings = {
          i = {
            ['<C-j>'] = actions.move_selection_next,
            ['<C-k>'] = actions.move_selection_previous,
            ['<Esc>'] = actions.close,
          },
        },
      },
      extensions = {
        themes = {}, -- Enable telescope themes picker
      },
    }

    -- Load telescope extensions
    pcall(telescope.load_extension, 'themes')

    -- Keybinding for colorscheme switcher
    vim.keymap.set('n', '<leader>cs', ':Telescope colorscheme<CR>', { desc = 'Switch colorscheme' })
  end,
}
