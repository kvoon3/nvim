return {
  dir = vim.fn.stdpath 'config' .. '/lua/cmdr',
  lazy = false,
  dependencies = { 'nvim-telescope/telescope.nvim' },
}
