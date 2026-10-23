--[[ Detection for buffers with pathological content (very long lines).

Such a buffer breaks assumptions all over the editor: semantic tokens make
redraws quadratic in the number of ranges on one line (~200k tokens on a 700KB
single line cost ~550ms per redraw), and language servers parse the whole file
on didOpen (a 683KB single line kept a TS server busy for seconds).

Cached per buffer and recomputed only when the buffer changes.
]]

local M = {}

local LONG_LINE = 2000
local CHUNK_LINES = 2000

---@type table<integer, { tick: integer, big: boolean }>
local cache = {}

--- @param bufnr integer
--- @return boolean
function M.is_bigfile(bufnr)
  bufnr = bufnr == 0 and vim.api.nvim_get_current_buf() or bufnr
  if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
    return false
  end

  local tick = vim.api.nvim_buf_get_changedtick(bufnr)
  local hit = cache[bufnr]
  if hit and hit.tick == tick then
    return hit.big
  end

  local total = vim.api.nvim_buf_line_count(bufnr)
  local big = false
  --[[ Chunked reads: one nvim_buf_get_lines call per 2000 lines keeps this at a
  few ms even for multi-MB generated files. ]]
  for first = 0, total - 1, CHUNK_LINES do
    for _, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, first, math.min(first + CHUNK_LINES, total), false)) do
      if #line > LONG_LINE then
        big = true
        break
      end
    end
    if big then
      break
    end
  end

  cache[bufnr] = { tick = tick, big = big }
  return big
end

return M
