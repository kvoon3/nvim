-- define common options
local opts = {
    noremap = true, -- non-recursive
    silent = true -- do not show message
}

-----------------
-- Normal mode --
-----------------

-- Hint: see `:h vim.map.set()`
-- Better window navigation (use :wincmd to avoid recursive mappings)
vim.keymap.set('n', '<C-h>', '<Cmd>wincmd h<CR>', opts)
vim.keymap.set('n', '<C-j>', '<Cmd>wincmd j<CR>', opts)
vim.keymap.set('n', '<C-k>', '<Cmd>wincmd k<CR>', opts)
vim.keymap.set('n', '<C-l>', '<Cmd>wincmd l<CR>', opts)

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

-- File explorer - using Snacks as primary
vim.keymap.set('n', '<C-,>', function() Snacks.picker.explorer() end, { desc = 'Toggle file explorer' })
vim.keymap.set('n', '<leader>fb', function() require('telescope').extensions.file_browser.file_browser({ path = vim.fn.expand('%:p:h'), select_buffer = true }) end, { desc = 'File browser in current directory' })

-- Create new file
vim.keymap.set('n', '%', ':call mkdir(expand("%:p:h"), "p")<CR>:e %<CR>', { desc = 'Create new file and its parent directories' })

vim.keymap.set('n', "<c-'>", ':q')

vim.keymap.set("n", '<c-s>', ':w<CR>')
local builtin = require('telescope.builtin')
vim.keymap.set('n', '<c-p>', builtin.find_files, { desc = 'Telescope find files' })
vim.keymap.set('n', '<leader>ff', builtin.live_grep, { desc = 'Telescope live grep' })
vim.keymap.set('n', '<leader>fb', builtin.buffers, { desc = 'Telescope buffers' })
vim.keymap.set('n', '<leader>fh', builtin.help_tags, { desc = 'Telescope help tags' })
vim.keymap.set('n', '<leader>lg', function() Snacks.lazygit() end, { desc = 'Open lazygit' })

vim.api.nvim_create_user_command('Lazygit', function() Snacks.lazygit() end, { desc = 'Open lazygit' })
vim.cmd([[cnoreabbrev <expr> lg getcmdtype() ==# ':' && getcmdline() ==# 'lg' ? 'Lazygit' : 'lg']])

-----------------
-- Command palette --
-----------------

-- VSCode-style Command Center (Ctrl+Shift+P)
vim.keymap.set('n', '<C-S-p>', function() require('commander').show() end, { desc = 'Command palette' })

vim.keymap.set('n', '<leader>p', '"+p')
vim.keymap.set('n', '<leader>a', 'ggVG', { desc = 'Select all' })

-----------------
-- Comments --
-----------------

-- Toggle comment with Ctrl+/
vim.keymap.set('n', '<C-/>', 'gcc', { remap = true, desc = 'Toggle comment' })
vim.keymap.set('v', '<C-/>', 'gc', { remap = true, desc = 'Toggle comment' })

----------
-- jieba
----------

local function jieba_motion(begin, forward)
  return function()
    local jieba = require('wordmotion.nvim.jieba')
    jieba.init()
    jieba.motion:keymap(begin, forward)
  end
end

vim.keymap.set({ 'x', 'n' }, 'B', jieba_motion(true, false), { silent = true })
vim.keymap.set({ 'x', 'n' }, 'b', jieba_motion(true, false), { silent = true })
vim.keymap.set({ 'x', 'n' }, 'w', jieba_motion(true, true), { silent = true })
vim.keymap.set({ 'x', 'n' }, 'W', jieba_motion(true, true), { silent = true })
vim.keymap.set({ 'x', 'n' }, 'E', jieba_motion(false, true), { silent = true })
vim.keymap.set({ 'x', 'n' }, 'e', jieba_motion(false, true), { silent = true })
vim.keymap.set({ 'x', 'n' }, 'ge', jieba_motion(false, false), { silent = true })
vim.keymap.set({ 'x', 'n' }, 'gE', jieba_motion(false, false), { silent = true })

-----------------
-- Panel helpers --
-----------------

local function is_explorer_win(winid)
    local buf = vim.api.nvim_win_get_buf(winid or 0)
    local ft = vim.bo[buf].filetype
    return ft == 'snacks_picker_list'
        or ft == 'snacks_picker_input'
        or ft == 'snacks_picker_preview'
end

local function is_terminal_win(winid)
    local buf = vim.api.nvim_win_get_buf(winid or 0)
    return vim.bo[buf].filetype == 'toggleterm'
end

local function close_explorer()
    local ok = pcall(function()
        for _, picker in ipairs(Snacks.picker.get({ source = 'explorer' })) do
            picker:close()
        end
    end)
    return ok
end

local function close_terminal()
    vim.cmd('ToggleTerm')
end

-----------------
-- Panel toggles --
-----------------

local function toggle_right_panel()
    if is_explorer_win() then
        close_explorer()
        return
    end

    local start_win = vim.api.nvim_get_current_win()
    vim.cmd('wincmd l')
    if vim.api.nvim_get_current_win() ~= start_win then
        return
    end

    if not is_terminal_win() then
        Snacks.picker.explorer()
    end
end

local function toggle_bottom_panel()
    if is_terminal_win() then
        close_terminal()
        return
    end

    local start_win = vim.api.nvim_get_current_win()
    vim.cmd('wincmd j')
    if vim.api.nvim_get_current_win() ~= start_win then
        return
    end

    if is_explorer_win() then
        close_explorer()
    end

    -- 简洁逻辑：<c-w>j 就是 toggle 底部 terminal panel（smart toggle 保存/恢复视图）
    vim.cmd('ToggleTerm')
end

local picker_fts = {
    snacks_picker_list = true,
    snacks_picker_input = true,
    snacks_picker_preview = true,
}

--[[
Focus the main editor window when pressing <C-w>h from a Snacks picker window.
This is needed because the file explorer preview is shown in the main editor,
so the user expects <C-w>h to jump to the currently previewed file.
]]
local function focus_main_editor()
    local current_win = vim.api.nvim_get_current_win()
    local current_buf = vim.api.nvim_win_get_buf(current_win)
    local current_ft = vim.bo[current_buf].filetype

    if not picker_fts[current_ft] then
        vim.cmd('wincmd h')
        return
    end

    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if win ~= current_win then
            local buf = vim.api.nvim_win_get_buf(win)
            local ft = vim.bo[buf].filetype
            if not picker_fts[ft] and ft ~= 'toggleterm' then
                vim.api.nvim_set_current_win(win)
                return
            end
        end
    end
end

-- <C-w>l / <C-w><C-l>: toggle right panel (file explorer)
vim.keymap.set('n', '<c-w>l', toggle_right_panel, { desc = 'Toggle right panel (file explorer)' })
vim.keymap.set('n', '<c-w><c-l>', toggle_right_panel, { desc = 'Toggle right panel (file explorer)' })

-- <C-w>j / <C-w><C-j>: toggle bottom panel (terminal)
vim.keymap.set('n', '<c-w>j', toggle_bottom_panel, { desc = 'Toggle bottom panel (terminal)' })
vim.keymap.set('n', '<c-w><c-j>', toggle_bottom_panel, { desc = 'Toggle bottom panel (terminal)' })

-- <C-w>h / <C-w><C-h>: focus main editor from explorer preview
vim.keymap.set('n', '<c-w>h', focus_main_editor, { desc = 'Focus main editor from explorer preview' })
vim.keymap.set('n', '<c-w><c-h>', focus_main_editor, { desc = 'Focus main editor from explorer preview' })

-----------------
-- Terminal mode --
-----------------

-- Exit terminal mode with Escape
vim.keymap.set('t', '<Esc>', '<C-\\><C-n>', opts)

-- Toggle terminal (toggleterm)
vim.keymap.set('n', '<C-t>', '<Cmd>ToggleTerm<CR>', { desc = 'Toggle terminal' })
vim.keymap.set('t', '<C-t>', '<C-\\><C-n><Cmd>ToggleTerm<CR>', { desc = 'Toggle terminal' })

-- Open numbered terminals
vim.keymap.set('n', '<leader>1', '<Cmd>1ToggleTerm<CR>', { desc = 'Toggle terminal 1' })
vim.keymap.set('n', '<leader>2', '<Cmd>2ToggleTerm<CR>', { desc = 'Toggle terminal 2' })
vim.keymap.set('n', '<leader>3', '<Cmd>3ToggleTerm<CR>', { desc = 'Toggle terminal 3' })

-- Terminal window navigation
vim.keymap.set('t', '<C-h>', '<C-\\><C-n><C-w>h', opts)
vim.keymap.set('t', '<C-j>', '<C-\\><C-n><C-w>j', opts)
vim.keymap.set('t', '<C-k>', '<C-\\><C-n><C-w>k', opts)
vim.keymap.set('t', '<C-l>', '<C-\\><C-n><C-w>l', opts)

local toggleterm_auto_hide_group = vim.api.nvim_create_augroup('ToggleTermAutoHide', { clear = true })

-- Save terminal view before leaving a terminal window, so smart-toggle can restore it later
vim.api.nvim_create_autocmd('WinLeave', {
    group = toggleterm_auto_hide_group,
    callback = function()
        if vim.bo.filetype ~= 'toggleterm' then
            return
        end
        local ok_ui, ui = pcall(require, 'toggleterm.ui')
        local ok_terms, terms = pcall(require, 'toggleterm.terminal')
        if not ok_ui or not ok_terms then
            return
        end

        local open_terms = {}
        local focus_id = terms.get_focused_id()
        for _, term in ipairs(terms.get_all()) do
            if term:is_open() then
                table.insert(open_terms, term.id)
            end
        end
        if #open_terms > 0 then
            ui.save_terminal_view(open_terms, focus_id)
        end
    end,
})

-- Auto-hide terminal when focus moves back to the main editor
vim.api.nvim_create_autocmd('WinEnter', {
    group = toggleterm_auto_hide_group,
    callback = function()
        if vim.bo.filetype == 'toggleterm' then
            return
        end
        local ok, terms = pcall(function()
            return require('toggleterm.terminal').get_all()
        end)
        if not ok then
            return
        end
        for _, term in ipairs(terms) do
            if term:is_open() then
                term:close()
            end
        end
    end,
})

-----------------
-- Open in GitHub --
-----------------

local open_in_github = require('open-in-github')
vim.keymap.set('n', '<leader>go', open_in_github.open_in_github, { desc = 'Open in GitHub' })
vim.keymap.set('v', '<leader>go', open_in_github.open_in_github, { desc = 'Open in GitHub' })

require('commander').add({
  {
    desc = 'Open in GitHub',
    cmd = open_in_github.open_in_github,
    keys = { 'n', '<leader>go' },
    cat = 'git',
  },
  {
    desc = 'Open plugin in GitHub',
    cmd = open_in_github.open_plugin_in_github,
    keys = { 'n', '<leader>gO' },
    cat = 'git',
  },
  {
    desc = 'Open current file plugin in GitHub',
    cmd = open_in_github.open_current_plugin_in_github,
    cat = 'git',
  },
})
