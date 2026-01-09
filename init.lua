vim = vim or {}

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

