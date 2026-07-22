-- Highlight the nearest enclosing bracket pair around the cursor.
local M = {}
local ns = vim.api.nvim_create_namespace 'enclosing_brackets'
local enabled = true

local OPEN_TO_CLOSE = { ['('] = ')', ['{'] = '}', ['['] = ']' }
local CLOSE_TO_OPEN = { [')'] = '(', ['}'] = '{', [']'] = '[' }
local hl_group = 'EnclosingBrackets'

---Find the innermost valid bracket pair enclosing the cursor in one pass.
---Brackets in strings and comments are intentionally treated as plain text.
---@return { open_row: integer, open_col: integer, close_row: integer, close_col: integer }|nil
local function find_enclosing_pair(bufnr)
  local cursor_row, cursor_col = unpack(vim.api.nvim_win_get_cursor(0))
  cursor_row = cursor_row - 1

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local stack = {}

  for row, line in ipairs(lines) do
    row = row - 1
    for i = 1, #line do
      local ch = line:sub(i, i)
      local col = i - 1

      if OPEN_TO_CLOSE[ch] then
        stack[#stack + 1] = { ch = ch, row = row, col = col }
      elseif CLOSE_TO_OPEN[ch] then
        local open = stack[#stack]
        if open and open.ch == CLOSE_TO_OPEN[ch] then
          stack[#stack] = nil
          local after_open = cursor_row > open.row or (cursor_row == open.row and cursor_col > open.col)
          local before_close = cursor_row < row or (cursor_row == row and cursor_col < col)
          if after_open and before_close then
            return {
              open_row = open.row,
              open_col = open.col,
              close_row = row,
              close_col = col,
            }
          end
        else
          stack = {}
        end
      end
    end
  end

  return nil
end

local function set_highlight()
  local normal = vim.api.nvim_get_hl(0, { name = 'Normal' })
  local visual = vim.api.nvim_get_hl(0, { name = 'Visual' })
  vim.api.nvim_set_hl(0, hl_group, {
    fg = normal.fg,
    bg = visual.bg,
  })
end

function M.highlight()
  if not enabled then
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

  local pair = find_enclosing_pair(bufnr)
  if not pair then
    return
  end

  vim.api.nvim_buf_set_extmark(bufnr, ns, pair.open_row, pair.open_col, {
    end_row = pair.open_row,
    end_col = pair.open_col + 1,
    hl_group = hl_group,
    priority = 999,
  })

  vim.api.nvim_buf_set_extmark(bufnr, ns, pair.close_row, pair.close_col, {
    end_row = pair.close_row,
    end_col = pair.close_col + 1,
    hl_group = hl_group,
    priority = 999,
  })
end

function M.enable()
  enabled = true
  M.highlight()
end

function M.disable()
  enabled = false
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
    end
  end
end

function M.toggle()
  if enabled then
    M.disable()
  else
    M.enable()
  end
end

function M.setup()
  local group = vim.api.nvim_create_augroup('EnclosingBrackets', { clear = true })
  set_highlight()

  vim.api.nvim_create_autocmd('ColorScheme', {
    group = group,
    callback = set_highlight,
    desc = 'Refresh enclosing bracket highlight',
  })

  vim.api.nvim_create_autocmd({ 'BufEnter', 'CursorMoved', 'CursorMovedI', 'InsertEnter', 'InsertLeave' }, {
    group = group,
    callback = M.highlight,
    desc = 'Highlight enclosing brackets',
  })

  require('cmdr').add {
    {
      desc = 'Toggle Enclosing Brackets Highlight',
      cmd = function()
        M.toggle()
      end,
      cat = 'brackets',
    },
  }
end

return M
