-- UI config
vim.opt.number = true -- show absolute number
vim.opt.relativenumber = false -- add numbers to each line on the left side
vim.opt.cursorline = false -- highlight cursor line underneath the cursor horizontally
vim.opt.guicursor = 'n-v-c-sm:block,i-ci-ve:ver25,r-cr-o:hor20,t:ver25'
-- Cursor style: block for normal/visual/command, vertical line for insert, horizontal for replace/operator, line for terminal mode
vim.opt.splitbelow = true -- open new vertical split bottom
vim.opt.splitright = true -- open new horizontal splits right

-- Tab
vim.opt.tabstop = 2 -- number of visual spaces per TAB
vim.opt.softtabstop = 2 -- number of spaces in tab when editing
vim.opt.shiftwidth = 2 -- insert 2 spaces on a tab
vim.opt.expandtab = true -- always use spaces instead of tab characters
vim.opt.smarttab = true -- use shiftwidth when inserting tabs at the beginning of a line
vim.opt.autoindent = true -- copy indent from current line when starting a new line

vim.opt.mouse = 'a'
vim.opt.mousescroll = 'ver:1,hor:1' -- scroll one line/column per mouse wheel tick

-- Safety
vim.opt.confirm = true -- ask for confirmation when quitting with unsaved changes

-- Buffer management: auto-delete unchanged buffers when hidden
vim.opt.bufhidden = 'wipe' -- automatically delete buffer when abandoned if unmodified

-- Background / colorscheme is managed by auto-dark-mode.nvim; vitesse.nvim is active, everforest-nvim and olive-crt.nvim are kept as alternatives

vim.opt.wrap = false

-- Search
vim.opt.ignorecase = true -- case-insensitive search by default
vim.opt.smartcase = true -- override ignorecase when pattern contains uppercase letters

-- Statusline: display current file name and info
vim.opt.laststatus = 2 -- always show statusline
vim.opt.statusline = '%f %m%r%h%w %= [%l,%c] [%p%%] [%L lines]'
-- Format: filename modified-flag readonly help-flag preview-flag | line,column | percentage | total-lines
