return {
  'willothy/flatten.nvim',
  -- 确保尽早加载，这样从 terminal 打开文件时才能正确 flatten 到当前 nvim
  lazy = false,
  priority = 1001,
  opts = function()
    ---@type Terminal?
    local saved_terminal

    return {
      -- 在当前窗口的 alternate window 打开文件，避免覆盖 terminal
      window = {
        open = 'alternate',
      },
      -- 没有文件参数时嵌套新的 nvim（保留默认行为）
      nest_if_no_args = true,
      -- 需要阻塞等待的文件类型
      block_for = {
        gitcommit = true,
        gitrebase = true,
      },
      hooks = {
        should_block = function(argv)
          -- 支持 nvim -b file 强制阻塞
          return vim.tbl_contains(argv, '-b')
        end,
        pre_open = function()
          -- 打开文件前记录当前 focused 的 toggleterm
          local ok, term = pcall(require, 'toggleterm.terminal')
          if ok then
            local termid = term.get_focused_id()
            saved_terminal = term.get(termid)
          end
        end,
        post_open = function(opts)
          if opts.is_blocking and saved_terminal then
            -- 阻塞编辑时隐藏 terminal
            saved_terminal:close()
          elseif opts.winnr and opts.winnr > 0 then
            -- 普通文件直接切换到打开它的窗口
            vim.api.nvim_set_current_win(opts.winnr)
          end

          -- git commit / rebase 保存后自动关闭 buffer
          if opts.filetype == 'gitcommit' or opts.filetype == 'gitrebase' then
            vim.api.nvim_create_autocmd('BufWritePost', {
              buffer = opts.bufnr,
              once = true,
              callback = vim.schedule_wrap(function()
                vim.api.nvim_buf_delete(opts.bufnr, {})
              end),
            })
          end
        end,
        block_end = function()
          -- 阻塞结束后重新打开 terminal
          vim.schedule(function()
            if saved_terminal then
              saved_terminal:open()
              saved_terminal = nil
            end
          end)
        end,
      },
    }
  end,
}
