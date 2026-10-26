--[[ Detection for buffers with pathological content: very long lines, or a large
total size.

Very long lines break assumptions all over the editor: semantic tokens make
redraws quadratic in the number of ranges on one line (~200k tokens on a 700KB
single line cost ~550ms per redraw), and a treesitter parse in flight re-runs
the highlight query predicates on every redraw.

Size matters on its own for language servers. tsrs holds ~1.6GB for the 684KB
`min.js`, but the blowup is not really about bytes per line: it scales
super-linearly with repeated same-name declarations (~O(n^2)), so a 512KB file
of duplicated functions already costs 731MB while a 1.4MB generated protocol
file costs 71MB. Byte size is the cheap proxy that catches all of it — small
files are cheap, and a huge one is not worth a language server's attention.

Cached per buffer and recomputed only when the buffer changes.
]]

local M = {}

local LONG_LINE = 2000
local MAX_BYTES = 256 * 1024
local CHUNK_LINES = 2000

---@type table<integer, { tick: integer, big: boolean }>
local cache = {}

--[[ Byte size from the buffer's own line index, so this is O(1) and needs no
  chunked scan. The whole-buffer offset counts every line's trailing newline,
  which overshoots a final line without one by a single byte — irrelevant for a
  size threshold. ]]
local function buffer_bytes(bufnr)
  return vim.api.nvim_buf_get_offset(bufnr, vim.api.nvim_buf_line_count(bufnr))
end

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

  local big = buffer_bytes(bufnr) > MAX_BYTES
  if not big then
    local total = vim.api.nvim_buf_line_count(bufnr)
    --[[ Chunked reads: one nvim_buf_get_lines call per 2000 lines keeps this at a
    few ms even for multi-MB generated files, and the size check above skips it
    for exactly those. ]]
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
  end

  cache[bufnr] = { tick = tick, big = big }
  return big
end

return M
