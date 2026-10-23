--[[ Scope wordmotion/jieba to buffers that actually contain CJK text.

The jieba backend re-tokenizes the current line on every `w`/`b`/`e` press. In
code (pure ASCII) that is pure overhead: jieba adds nothing, and on single-line
minified files it is ~400k tokens per keypress. So for non-CJK buffers this
installs buffer-local maps that resolve to the builtin Vim motions, which also
keeps the lazy jieba plugin (and its Rust segmenter) from ever loading. CJK
buffers keep the wordmotion maps and warm the segmenter in the background.

Detection is a byte-range heuristic on UTF-8 lead bytes (CJK punctuation, kana,
ideographs), evaluated once per buffer.
]]

local M = {}

local MOTIONS = { 'w', 'b', 'e', 'ge', 'W', 'B', 'E', 'gE' }
local TEXT_OBJECTS = { 'iw', 'aw' }
local CJK_LEAD = '[\227-\233]' -- E3..E9
local CHUNK_LINES = 2000

--- @param bufnr integer
--- @return boolean
local function has_cjk(bufnr)
  local total = vim.api.nvim_buf_line_count(bufnr)
  for first = 0, total - 1, CHUNK_LINES do
    local lines = vim.api.nvim_buf_get_lines(bufnr, first, math.min(first + CHUNK_LINES, total), false)
    if table.concat(lines, '\n'):find(CJK_LEAD) then
      return true
    end
  end
  return false
end

--[[ Map `lhs` to itself with noremap: the rhs is not remapped, so it runs the
builtin motion, and nvim re-applies any pending count (verified: `3w` lands on
the same column as without the map). ]]
--- @param bufnr integer
local function use_builtin(bufnr)
  for _, lhs in ipairs(MOTIONS) do
    vim.keymap.set({ 'n', 'x' }, lhs, lhs, { buffer = bufnr, noremap = true })
  end
  for _, lhs in ipairs(TEXT_OBJECTS) do
    vim.keymap.set('x', lhs, lhs, { buffer = bufnr, noremap = true })
  end
end

--- @param ev table
local function scope(ev)
  local bufnr = ev.buf
  if vim.bo[bufnr].buftype ~= '' or vim.b[bufnr].wordmotion_scope ~= nil then
    return
  end

  local cjk = has_cjk(bufnr)
  vim.b[bufnr].wordmotion_scope = cjk and 'cjk' or 'builtin'
  if cjk then
    --[[ Build the segmenter ahead of the first word motion; scheduled so the
    buffer read stays cheap. ]]
    vim.schedule(function()
      require('jieba-native').prewarm { hmm = false }
    end)
  else
    use_builtin(bufnr)
  end
end

function M.setup()
  vim.api.nvim_create_autocmd({ 'BufReadPost', 'BufNewFile' }, {
    group = vim.api.nvim_create_augroup('WordmotionScope', { clear = true }),
    callback = scope,
  })
end

return M
