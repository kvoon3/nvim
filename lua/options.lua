-- UI config
vim.opt.number = true -- show absolute number
vim.opt.relativenumber = false -- add numbers to each line on the left side
vim.opt.cursorline = false -- highlight cursor line underneath the cursor horizontally
vim.opt.splitbelow = true -- open new vertical split bottom
vim.opt.splitright = true -- open new horizontal splits right

-- Tab
vim.opt.tabstop = 2 -- number of visual spaces per TAB
vim.opt.softtabstop = 2 -- number of spacesin tab when editing
vim.opt.shiftwidth = 2 -- insert 2 spaces on a tab
vim.opt.expandtab = true -- tabs are spaces, mainly because of python

vim.opt.mouse="a"

vim.o.background = 'dark'
vim.cmd[[
  hi Normal guibg=NONE ctermbg=NONE
  hi NormalNC guibg=NONE ctermbg=NONE
  hi NormalFloat guibg=NONE ctermbg=NONE
]]

