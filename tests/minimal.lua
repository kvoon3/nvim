-- Minimal init for running plenary tests headlessly.
-- The project root is inferred from this file's location.
local root = vim.fn.fnamemodify(vim.fn.resolve(vim.fn.expand '<sfile>:p'), ':h:h')

vim.opt.runtimepath:prepend(root)
vim.opt.packpath:prepend(root)

-- Add lazy-installed dependencies that tests need.
local lazy_root = vim.env.NVIM_TEST_PLUGIN_DATA or vim.fn.stdpath 'data'
lazy_root = lazy_root .. '/lazy'
vim.opt.runtimepath:append(lazy_root .. '/plenary.nvim')
vim.opt.runtimepath:append(lazy_root .. '/telescope.nvim')
vim.opt.runtimepath:append(lazy_root .. '/LuaSnip')

vim.cmd 'runtime! plugin/**/*.vim plugin/**/*.lua'
