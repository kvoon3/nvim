-- UI config
vim.opt.number = false -- hide line numbers by default
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
vim.opt.shortmess:append 'A' -- auto-ignore swap files from dead processes
vim.opt.confirm = true -- ask for confirmation when quitting with unsaved changes

-- Buffer management: auto-delete unchanged buffers when hidden
vim.opt.bufhidden = 'wipe' -- automatically delete buffer when abandoned if unmodified

-- Background / colorscheme is managed by auto-dark-mode.nvim; vitesse.nvim is active, everforest-nvim and olive-crt.nvim are kept as alternatives

vim.opt.wrap = false

-- Search
vim.opt.ignorecase = true -- case-insensitive search by default
vim.opt.smartcase = true -- override ignorecase when pattern contains uppercase letters

-- Winbar (header): see lua/statusline.lua. Footer is provided by mini.statusline.
vim.opt.winbar = "%!v:lua.require'statusline'.render_header()" -- relative file path and flags; click to copy
vim.opt.laststatus = 2 -- always show statusline

require('cmdr').add {
  {
    desc = 'Toggle line numbers',
    cmd = function()
      vim.wo.number = not vim.wo.number
    end,
    cat = 'view',
  },
}
