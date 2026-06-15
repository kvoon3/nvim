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

        local function show_terminals()
            local has_terminals = false
            for _, buf in ipairs(vim.api.nvim_list_bufs()) do
                if vim.bo[buf].filetype == 'toggleterm' then
                    has_terminals = true
                    break
                end
            end

            if not has_terminals then
                vim.notify('No terminals', vim.log.levels.INFO)
                return
            end

            local ok = pcall(function()
                Snacks.picker({
                    source = 'terminals',
                    title = 'Terminals',
                    finder = function(opts, ctx)
                        local items = {}
                        for _, buf in ipairs(vim.api.nvim_list_bufs()) do
                            if vim.bo[buf].filetype == 'toggleterm' then
                                local id = vim.b[buf].toggle_number
                                local text = id and ('Terminal ' .. id) or 'Terminal'
                                table.insert(items, {
                                    buf = buf,
                                    id = id,
                                    text = text,
                                    name = text,
                                    file = text,
                                })
                            end
                        end
                        return ctx.filter:filter(items)
                    end,
                    preview = function(ctx)
                        local buf = ctx.item.buf
                        if not buf or not vim.api.nvim_buf_is_valid(buf) then
                            return false
                        end
                        ctx.preview:reset()
                        ctx.preview:set_title(ctx.item.text)
                        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
                        -- preview buffer 默认是 scratch 且不可修改，需临时解锁
                        vim.bo[ctx.buf].modifiable = true
                        vim.api.nvim_buf_set_lines(ctx.buf, 0, -1, false, lines)
                        vim.bo[ctx.buf].modifiable = false
                        vim.bo[ctx.buf].filetype = 'toggleterm'
                        return true
                    end,
                    actions = {
                        confirm = function(picker, item)
                            picker:close()
                            if item and item.id then
                                vim.cmd(item.id .. 'ToggleTerm')
                            end
                        end,
                    },
                })
            end)

            if not ok then
                vim.notify('Failed to open terminal picker', vim.log.levels.ERROR)
            end
        end

        vim.keymap.set('n', '<leader>tt', show_terminals, { desc = 'List all terminals' })

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
                {
                    desc = 'List all terminals',
                    cmd = show_terminals,
                    keys = { 'n', '<leader>tt' },
                    cat = 'terminal',
                },
            })
        end
    end,
}
