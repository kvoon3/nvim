-- define common options
local opts = {
    noremap = true, -- non-recursive
    silent = true -- do not show message
}

-----------------
-- Normal mode --
-----------------

-- Hint: see `:h vim.map.set()`
-- Better window navigation
vim.keymap.set('n', '<C-h>', '<C-w>h', opts)
vim.keymap.set('n', '<C-j>', '<C-w>j', opts)
vim.keymap.set('n', '<C-k>', '<C-w>k', opts)
vim.keymap.set('n', '<C-l>', '<C-w>l', opts)

-- Resize with arrows
-- delta: 2 lines
vim.keymap.set('n', '<C-Up>', ':resize -2<CR>', opts)
vim.keymap.set('n', '<C-Down>', ':resize +2<CR>', opts)
vim.keymap.set('n', '<C-Left>', ':vertical resize -2<CR>', opts)
vim.keymap.set('n', '<C-Right>', ':vertical resize +2<CR>', opts)

-----------------
-- Visual mode --
-----------------

-- Hint: start visual mode with the same area as the previous area and the same mode
vim.keymap.set('v', '<', '<gv', opts)
vim.keymap.set('v', '>', '>gv', opts)

-- 上下移动文本
vim.keymap.set("v", "J", ":move '>+1<CR>gv-gv", opts)
vim.keymap.set("v", "K", ":move '<-2<CR>gv-gv", opts)

vim.keymap.set('n', '<leader><BS>', ':Ex<CR>')
vim.keymap.set('n', "<c-'>", ':q')

-- nvim-tree
vim.keymap.set('n', '<C-,>', ':NvimTreeToggle<CR>', { silent = true, desc = 'Toggle file explorer' })

vim.keymap.set("n", '<c-s>', ':w<CR>')

local builtin = require('telescope.builtin')
vim.keymap.set('n', '<c-p>', builtin.find_files, { desc = 'Telescope find files' })
vim.keymap.set('n', '<leader>ff', builtin.live_grep, { desc = 'Telescope live grep' })
vim.keymap.set('n', '<leader>fb', builtin.buffers, { desc = 'Telescope buffers' })
vim.keymap.set('n', '<leader>fh', builtin.help_tags, { desc = 'Telescope help tags' })

vim.keymap.set('n', '<leader>p', '"+p')
vim.keymap.set('n', '<leader>a', 'ggVG')

----------
-- jieba
----------

vim.keymap.set({'x', 'n'}, 'B', '<cmd>lua require("jieba_nvim").wordmotion_B()<CR>', {noremap = false, silent = true})
vim.keymap.set({'x', 'n'}, 'b', '<cmd>lua require("jieba_nvim").wordmotion_b()<CR>', {noremap = false, silent = true})
vim.keymap.set({'x', 'n'}, 'w', '<cmd>lua require("jieba_nvim").wordmotion_w()<CR>', {noremap = false, silent = true})
vim.keymap.set({'x', 'n'}, 'W', '<cmd>lua require("jieba_nvim").wordmotion_W()<CR>', {noremap = false, silent = true})
vim.keymap.set({'x', 'n'}, 'E', '<cmd>lua require("jieba_nvim").wordmotion_E()<CR>', {noremap = false, silent = true})
vim.keymap.set({'x', 'n'}, 'e', '<cmd>lua require("jieba_nvim").wordmotion_e()<CR>', {noremap = false, silent = true})
vim.keymap.set({'x', 'n'}, 'ge', '<cmd>lua require("jieba_nvim").wordmotion_ge()<CR>', {noremap = false, silent = true})
vim.keymap.set({'x', 'n'}, 'gE', '<cmd>lua require("jieba_nvim").wordmotion_gE()<CR>', {noremap = false, silent = true})

-----------------
-- Terminal mode --
-----------------

-- Exit terminal mode with Escape
vim.keymap.set('t', '<Esc>', '<C-\\><C-n>', opts)


