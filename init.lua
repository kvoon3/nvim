vim = vim or {}

vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

require('config.lazy')
require('options')
require('keymaps')
require('coc-config')
require('vue-config')

if vim.g.vscode then
    -- VSCode extension
else
    -- ordinary Neovim
end

