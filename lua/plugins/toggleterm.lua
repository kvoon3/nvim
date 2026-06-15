return {
    'akinsho/toggleterm.nvim',
    version = '*',
    event = 'VeryLazy',
    config = function()
        require('toggleterm').setup({
            size = function(term)
                if term.direction == 'horizontal' then
                    return 20
                elseif term.direction == 'vertical' then
                    return vim.o.columns * 0.4
                end
            end,
            -- 不在这里设置 open_mapping，避免和 Snacks 的 <C-t> 冲突
            -- 我们在 keymaps.lua 里手动绑定
            direction = 'horizontal',
            float_opts = {
                border = 'rounded',
                winblend = 0,
            },
            start_in_insert = true,
            insert_mappings = true,
            terminal_mappings = true,
            persist_size = true,
            persist_mode = true,
            close_on_exit = true,
            shell = vim.o.shell,
            auto_scroll = true,
            shade_terminals = true,
            shading_factor = 2,
        })

        local Terminal = require('toggleterm.terminal').Terminal

        -- 创建专用的 terminal 实例
        local lazygit = Terminal:new({
            cmd = 'lazygit',
            dir = 'git_dir',
            direction = 'float',
            hidden = true,
            float_opts = {
                border = 'rounded',
            },
            on_open = function(term)
                vim.cmd('startinsert!')
                vim.api.nvim_buf_set_keymap(term.bufnr, 't', '<esc>', '<cmd>close<CR>', { noremap = true, silent = true })
            end,
        })

        local function lazygit_toggle()
            lazygit:toggle()
        end

        -- 注册 commander 命令
        local ok, commander = pcall(require, 'commander')
        if ok then
            commander.add({
                {
                    desc = 'Toggle terminal (toggleterm)',
                    cmd = function()
                        vim.cmd('ToggleTerm')
                    end,
                    keys = { 'n', '<C-t>' },
                    cat = 'terminal',
                },
                {
                    desc = 'Toggle floating terminal',
                    cmd = function()
                        vim.cmd('ToggleTerm direction=float')
                    end,
                    keys = { 'n', '<leader>tf' },
                    cat = 'terminal',
                },
                {
                    desc = 'Toggle vertical terminal',
                    cmd = function()
                        vim.cmd('ToggleTerm direction=vertical')
                    end,
                    keys = { 'n', '<leader>tv' },
                    cat = 'terminal',
                },
                {
                    desc = 'Open lazygit in terminal',
                    cmd = lazygit_toggle,
                    keys = { 'n', '<leader>tg' },
                    cat = 'terminal',
                },
            })
        end
    end,
}
