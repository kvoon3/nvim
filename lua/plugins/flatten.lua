return {
  'willothy/flatten.nvim',
  -- Load early so files opened from a terminal flatten into the current nvim.
  lazy = false,
  priority = 1001,
  opts = function()
    ---@class ToggleTerm
    ---@field close fun(self: ToggleTerm)
    ---@field open fun(self: ToggleTerm)
    ---@type ToggleTerm?
    local saved_terminal

    return {
      -- Open files in the current window's alternate window instead of replacing the terminal.
      window = {
        open = 'alternate',
      },
      -- Nest a new nvim when no file argument is provided (preserve the default behavior).
      nest_if_no_args = true,
      -- File types that require blocking until the nested editor exits.
      block_for = {
        gitcommit = true,
        gitrebase = true,
      },
      hooks = {
        should_block = function(argv)
          -- Support forcing blocking behavior with `nvim -b file`.
          return vim.tbl_contains(argv, '-b')
        end,
        pre_open = function()
          -- Save the currently focused ToggleTerm before opening the file.
          local ok, term = pcall(require, 'toggleterm.terminal')
          if ok then
            local termid = term.get_focused_id()
            saved_terminal = term.get(termid)
          end
        end,
        post_open = function(opts)
          if opts.is_blocking and saved_terminal then
            -- Hide the terminal while blocking.
            saved_terminal:close()
          elseif opts.winnr and opts.winnr > 0 then
            -- Switch directly to the window that opened a regular file.
            vim.api.nvim_set_current_win(opts.winnr)
          end

          -- Close the buffer automatically after saving a git commit or rebase message.
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
          -- Reopen the terminal after blocking ends.
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
