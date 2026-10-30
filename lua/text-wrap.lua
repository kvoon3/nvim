--[[
Wrap text on word boundaries using display width, so CJK counts as two cells
and a long token hard-breaks instead of overflowing the window.
]]
local M = {}

local UTF8_CHAR = '[%z\1-\127\194-\244][\128-\191]*'

local function utf8_chars(text)
  local chars = {}
  for char in text:gmatch(UTF8_CHAR) do
    chars[#chars + 1] = char
  end
  return chars
end

---@param text string
---@param width integer
---@return string[]
function M.wrap(text, width)
  width = math.max(10, width)

  local lines = {}
  local line, line_w = '', 0

  local function flush()
    if line_w > 0 then
      lines[#lines + 1] = line
      line, line_w = '', 0
    end
  end

  local function add_word(word)
    local word_w = vim.fn.strdisplaywidth(word)
    if word_w > width then
      for _, char in ipairs(utf8_chars(word)) do
        local char_w = vim.fn.strdisplaywidth(char)
        if line_w + char_w > width then
          flush()
        end
        line = line .. char
        line_w = line_w + char_w
      end
      return
    end

    local sep = line_w > 0 and 1 or 0
    if line_w + sep + word_w > width then
      flush()
      sep = 0
    end
    if sep == 1 then
      line = line .. ' '
    end
    line = line .. word
    line_w = line_w + sep + word_w
  end

  for word in text:gmatch '%S+' do
    add_word(word)
  end
  flush()

  if #lines == 0 then
    lines[1] = text
  end
  return lines
end

return M
