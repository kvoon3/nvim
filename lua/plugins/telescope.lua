return {
    'nvim-telescope/telescope.nvim',
    tag = '0.1.8',
    dependencies = {'nvim-lua/plenary.nvim'},
    config = function()
        local telescope = require('telescope')
        local actions = require('telescope.actions')

        telescope.setup({
            defaults = {
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
        })

        -- Load telescope extensions
        pcall(telescope.load_extension, 'themes')

        -- Keybinding for colorscheme switcher
        vim.keymap.set('n', '<leader>cs', ':Telescope colorscheme<CR>',
            { desc = 'Switch colorscheme' })
    end,
}
