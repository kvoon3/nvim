-- Format the markdown table around the cursor by aligning all columns.
local M = {}

---Split a table row into trimmed cell values, ignoring leading/trailing pipes.
---@return string[]
local function split_row(line)
  local cells = {}
  local inner = line:gsub('^%s*|', ''):gsub('|%s*$', '')
  for cell in (inner .. '|'):gmatch '(.-)|' do
    cells[#cells + 1] = vim.trim(cell)
  end
  return cells
end

local function is_separator(cells)
  for _, c in ipairs(cells) do
    if not c:match '^:?-+:?$' then
      return false
    end
  end
  return #cells > 0
end

local function format_table()
  local bufnr = 0
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  if not lines[row + 1]:find '|' then
    vim.notify('no table here', vim.log.levels.INFO)
    return
  end

  local first, last = row, row
  while first > 0 and lines[first]:find '|' do
    first = first - 1
  end
  while last < #lines - 1 and lines[last + 2]:find '|' do
    last = last + 1
  end

  local rows = {}
  local widths = {}
  for i = first, last do
    local cells = split_row(lines[i + 1])
    rows[#rows + 1] = cells
    if not is_separator(cells) then
      for c, cell in ipairs(cells) do
        widths[c] = math.max(widths[c] or 0, vim.fn.strdisplaywidth(cell))
      end
    end
  end

  local out = {}
  for _, cells in ipairs(rows) do
    local parts = {}
    if is_separator(cells) then
      for c = 1, #widths do
        parts[c] = string.rep('-', widths[c])
      end
    else
      for c, cell in ipairs(cells) do
        parts[c] = cell .. string.rep(' ', widths[c] - vim.fn.strdisplaywidth(cell))
      end
    end
    out[#out + 1] = '| ' .. table.concat(parts, ' | ') .. ' |'
  end

  vim.api.nvim_buf_set_lines(bufnr, first, last + 1, false, out)
end

function M.setup()
  require('cmdr').add {
    { desc = 'Markdown: format table', cmd = format_table, cat = 'markdown' },
  }
end

return M
