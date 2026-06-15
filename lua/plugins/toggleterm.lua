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
            local terms_module = require('toggleterm.terminal')
            local terminals = {}
            for _, term in ipairs(terms_module.get_all()) do
                table.insert(terminals, term)
            end

            if #terminals == 0 then
                vim.notify('No terminals', vim.log.levels.INFO)
                return
            end

            local ok, telescope = pcall(function()
                return {
                    pickers = require('telescope.pickers'),
                    finders = require('telescope.finders'),
                    conf = require('telescope.config').values,
                    previewers = require('telescope.previewers'),
                    actions = require('telescope.actions'),
                    action_state = require('telescope.actions.state'),
                }
            end)

            if not ok then
                -- fallback 到简单选择
                local items = vim.tbl_map(function(term)
                    return {
                        id = term.id,
                        text = 'Terminal ' .. term.id,
                        term = term,
                    }
                end, terminals)

                local origin_win = vim.api.nvim_get_current_win()
                vim.ui.select(items, {
                    prompt = 'Select terminal:',
                    format_item = function(item) return item.text end,
                }, function(item)
                    if not item then return end
                    if vim.api.nvim_win_is_valid(origin_win) then
                        vim.api.nvim_set_current_win(origin_win)
                    end
                    local term = item.term
                    if term:is_open() then term:close() end
                    term:change_direction('horizontal')
                    term:open()
                    vim.cmd('startinsert!')
                end)
                return
            end

            telescope.pickers.new({}, {
                prompt_title = 'Terminals',
                finder = telescope.finders.new_table({
                    results = terminals,
                    entry_maker = function(term)
                        return {
                            value = term,
                            display = 'Terminal ' .. term.id,
                            ordinal = 'Terminal ' .. term.id,
                            bufnr = term.bufnr,
                        }
                    end,
                }),
                sorter = telescope.conf.generic_sorter({}),
                previewer = telescope.previewers.new_buffer_previewer({
                    title = 'Terminal Preview',
                    get_buffer_by_name = function(_, entry)
                        return entry.bufnr
                    end,
                    define_preview = function(self, entry)
                        local buf = entry.bufnr
                        if not buf or not vim.api.nvim_buf_is_valid(buf) then
                            return
                        end
                        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
                        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
                        vim.bo[self.state.bufnr].filetype = 'toggleterm'
                    end,
                }),
                attach_mappings = function(prompt_bufnr)
                    telescope.actions.select_default:replace(function()
                        local selection = telescope.action_state.get_selected_entry()
                        telescope.actions.close(prompt_bufnr)
                        if selection then
                            local term = selection.value
                            if term:is_open() then
                                term:close()
                            end
                            term:change_direction('horizontal')
                            term:open()
                            vim.cmd('startinsert!')
                        end
                    end)
                    return true
                end,
            }):find()
        end

        vim.keymap.set('n', '<leader>tt', show_terminals, { desc = 'List all terminals' })

        local function toggle_terminal_fullscreen()
            local ok, terms = pcall(require, 'toggleterm.terminal')
            if not ok then
                return
            end

            -- 优先使用当前 focused terminal，否则用 terminal 1
            local term_id = terms.get_focused_id() or 1
            local term = terms.get(term_id)
            if not term then
                term = terms.get_or_create_term(term_id)
            end

            -- 切换方向：半屏 horizontal <-> 全屏 float
            local new_direction = term.direction == 'horizontal' and 'float' or 'horizontal'
            term:change_direction(new_direction)
            term:open()
            vim.cmd('startinsert!')
        end

        -- 注意：<C-m> 在 Vim 中等价于 <CR>
        vim.keymap.set('n', '<c-m>', toggle_terminal_fullscreen, { desc = 'Toggle terminal fullscreen' })

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
                {
                    desc = 'Toggle terminal fullscreen',
                    cmd = toggle_terminal_fullscreen,
                    keys = { 'n', '<c-m>' },
                    cat = 'terminal',
                },
            })
        end
    end,
}
