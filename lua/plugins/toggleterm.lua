return {
  'akinsho/toggleterm.nvim',
  version = '*',
  event = 'VeryLazy',
  config = function()
    require('toggleterm').setup {
      size = function(term)
        if term.direction == 'horizontal' then
          return 20
        elseif term.direction == 'vertical' then
          return vim.o.columns * 0.4
        end
      end,

      direction = 'horizontal',

      float_opts = {
        border = 'rounded',
        winblend = 0,
      },

      start_in_insert = true,
      insert_mappings = true,
      terminal_mappings = true,
      persist_size = true,
      persist_mode = false,
      close_on_exit = true,
      shell = vim.o.shell,
      auto_scroll = true,
      shade_terminals = true,
      shading_factor = 2,
    }

    local function toggle_terminal_fullscreen()
      local ok, terms = pcall(require, 'toggleterm.terminal')
      if not ok then
        return
      end

      local term_id = terms.get_focused_id() or 1
      local term = terms.get(term_id)
      if not term then
        term = terms.get_or_create_term(term_id)
      end

      local new_direction = term.direction == 'horizontal' and 'float' or 'horizontal'
      term:change_direction(new_direction)
      term:open()
      vim.cmd 'startinsert!'
    end

    vim.keymap.set('n', '<C-S-t>', toggle_terminal_fullscreen, { desc = 'Toggle terminal fullscreen' })

    require('cmdr').add {
      {
        desc = 'Toggle terminal (toggleterm)',
        cmd = function()
          vim.cmd 'ToggleTerm'
        end,
        keys = { 'n', '<C-t>' },
        cat = 'terminal',
      },
      {
        desc = 'Toggle floating terminal',
        cmd = function()
          vim.cmd 'ToggleTerm direction=float'
        end,
        keys = { 'n', '<leader>tf' },
        cat = 'terminal',
      },
      {
        desc = 'Toggle vertical terminal',
        cmd = function()
          vim.cmd 'ToggleTerm direction=vertical'
        end,
        keys = { 'n', '<leader>tv' },
        cat = 'terminal',
      },
      {
        desc = 'Toggle terminal fullscreen',
        cmd = toggle_terminal_fullscreen,
        keys = { 'n', '<C-S-t>' },
        cat = 'terminal',
      },
    }
  end,
}
