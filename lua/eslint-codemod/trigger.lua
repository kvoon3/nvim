local M = {}

--[[ Port of VSCode's isInsideLineComment / isInsideBlockComment.

  VSCode variant uses the active editor's document + selection.
  Here we operate on a Neovim buffer + cursor (row, col) and expose
  both buffer-aware helpers and pure-string helpers for headless
  testing.
]]

--[[ Pure: whether `line_before_cursor` is considered inside a line
  comment prefixed with `comment_text` (default "//").

  Mirrors:
    lineBeforeCursor = currentLineText.substring(0, character)
    openStringLiterals = (lineBeforeCursor.match(/"/g)||[]).length %2 !==0
    lastIdx = lineBeforeCursor.lastIndexOf(commentText)
    return lastIdx !== -1 && !openStringLiterals
]]
function M.is_inside_line_comment_str(line_before_cursor, comment_text)
  comment_text = comment_text or '//'
  local count = 0
  for _ in line_before_cursor:gmatch '"' do
    count = count + 1
  end

  local open_string = (count % 2) == 1
  if open_string then
    return false
  end

  return line_before_cursor:find(comment_text, 1, true) ~= nil
end

--[[ Pure: whether `text_before_cursor` is inside a block comment.

  Mirrors VSCode's counting:
    open = (text.match(/\/\*/g)||[]).length + (text.match(/\/\*\*/g)||[]).length
    close = (text.match(/\*\//g)||[]).length
    return open > close

  Note: VSCode double counts `/**` (it matches both patterns). We
  replicate the exact count for parity, but the bug is harmless for
  the `>` comparison.
]]
function M.is_inside_block_comment_str(text_before_cursor)
  local open_a = 0
  for _ in text_before_cursor:gmatch '/%*' do
    open_a = open_a + 1
  end

  local open_b = 0
  for _ in text_before_cursor:gmatch '/%*%*' do
    open_b = open_b + 1
  end

  local close = 0
  for _ in text_before_cursor:gmatch '%*/' do
    close = close + 1
  end

  return (open_a + open_b) > close
end

function M.get_line_before_cursor(bufnr, row, col)
  bufnr = bufnr or 0
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ''
  -- `col` is 0-indexed byte column (nvim_win_get_cursor col)
  return line:sub(1, col)
end

function M.get_text_before_cursor(bufnr, row, col)
  bufnr = bufnr or 0
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, row + 1, false)
  local before = {}

  for i = 1, row do
    table.insert(before, lines[i] or '')
  end

  local cur = lines[row + 1] or ''
  table.insert(before, cur:sub(1, col))

  return table.concat(before, '\n')
end

function M.is_inside_line_comment(bufnr, row, col, comment_text)
  local line_before = M.get_line_before_cursor(bufnr, row, col)
  return M.is_inside_line_comment_str(line_before, comment_text)
end

function M.is_inside_block_comment(bufnr, row, col)
  local text_before = M.get_text_before_cursor(bufnr, row, col)
  return M.is_inside_block_comment_str(text_before)
end

--[[ Trigger tables mirroring vscode's `commentTriggerMap`.

  The `condition` closures capture buffer/cursor and delegate to the
  helpers above. We expose the raw table for inspection and provide
  `triggers_for(commentType)` and `is_trigger_valid(...)` for
  completion.
]]
M.line_triggers = {
  {
    char = '/',
    condition = function(bufnr, row, col)
      return M.is_inside_line_comment(bufnr, row, col, '///')
    end,
  },
  {
    char = ':',
    condition = function(bufnr, row, col)
      return M.is_inside_line_comment(bufnr, row, col, '//')
    end,
  },
  {
    char = '@',
    condition = function(bufnr, row, col)
      return M.is_inside_line_comment(bufnr, row, col, '//')
    end,
  },
}

M.block_triggers = {
  {
    char = '@',
    condition = function(bufnr, row, col)
      return M.is_inside_block_comment(bufnr, row, col)
    end,
  },
}

M.comment_trigger_map = {
  line = M.line_triggers,
  block = M.block_triggers,
  both = (function()
    local both = {}
    for _, t in ipairs(M.line_triggers) do
      table.insert(both, t)
    end

    for _, t in ipairs(M.block_triggers) do
      table.insert(both, t)
    end

    return both
  end)(),
}

function M.triggers_for(comment_type)
  comment_type = comment_type or 'line'
  return M.comment_trigger_map[comment_type] or M.comment_trigger_map.line
end

function M.trigger_chars()
  local seen = {}
  local chars = {}
  for _, triggers in pairs(M.comment_trigger_map) do
    for _, t in ipairs(triggers) do
      if not seen[t.char] then
        seen[t.char] = true
        table.insert(chars, t.char)
      end
    end
  end

  table.sort(chars)
  return chars
end

--[[ Whether `trigger_char` is valid for `command` at `(bufnr,row,col)`. ]]
function M.is_trigger_valid(command, trigger_char, bufnr, row, col)
  local comment_type = command.commentType or 'line'
  local triggers = M.triggers_for(comment_type)
  for _, t in ipairs(triggers) do
    if t.char == trigger_char and t.condition(bufnr, row, col) then
      return true
    end
  end

  return false
end

--[[ Heuristic: infer trigger_char from buffer context.

  Returns the char immediately before the cursor if it is one of the
  known triggers `/`, `@`, `:` and the cursor sits inside the matching
  comment kind; otherwise nil.
]]
function M.infer_trigger_char(bufnr, row, col)
  bufnr = bufnr or 0
  if col == 0 then
    return nil
  end

  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ''
  local char_before = line:sub(col, col)
  if char_before ~= '/' and char_before ~= '@' and char_before ~= ':' then
    return nil
  end

  --[[ Validate that this char would be accepted for *some* command
    (i.e., there exists at least one line/both/block command where
    the condition holds). This avoids spurious triggers on naked
    division operators outside comments. ]]
  local dummy_line = { commentType = 'line' }
  local dummy_block = { commentType = 'block' }
  local dummy_both = { commentType = 'both' }
  if M.is_trigger_valid(dummy_line, char_before, bufnr, row, col) then
    return char_before
  end

  if M.is_trigger_valid(dummy_block, char_before, bufnr, row, col) then
    return char_before
  end

  if M.is_trigger_valid(dummy_both, char_before, bufnr, row, col) then
    return char_before
  end

  return nil
end

return M
