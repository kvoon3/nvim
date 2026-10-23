--[[ Token adapter for wordmotion's jieba backend.

wordmotion re-tokenizes the whole current line on every `w`/`b`/`e` press, and
only then reads the token under the cursor. A single-line minified file is
~700KB, which jieba splits into ~420k tokens; building that token table cost
~120-150ms per keypress. Segmentation itself is not the problem (28ms), the
per-token Lua tables are.

So for very long lines the tokens are merged into at most MAX_TOKENS chunks
(always on the original token boundaries, so the result still covers the input
exactly) and the last big line is memoized. Normal lines pass through untouched.
]]

local M = {}

local PASSTHROUGH_BYTES = 8192 -- shorter lines are cheap, leave them alone
local MAX_TOKENS = 4096 -- per-press ceiling for pathological lines

--- @param tokens string[]
--- @param limit integer
--- @return string[]
local function merge(tokens, limit)
  if #tokens <= limit then
    return tokens
  end

  local step = math.ceil(#tokens / limit)
  local merged = {}
  for i = 1, #tokens, step do
    merged[#merged + 1] = table.concat(tokens, '', i, math.min(i + step - 1, #tokens))
  end
  return merged
end

local Adapter = {}
Adapter.__index = Adapter

--[[ Cut `text` for wordmotion: same partition of the input, but bounded token
count and memoized for the current big line. ]]
function Adapter:cut(text)
  if self._line == text then
    return self._tokens
  end

  local tokens = self._inner:cut(text)
  local result = #text > PASSTHROUGH_BYTES and merge(tokens, MAX_TOKENS) or tokens
  if #text > PASSTHROUGH_BYTES then
    --[[ Single-entry cache: the line is usually unchanged across presses, and
    keeping only one entry bounds memory for huge buffers. ]]
    self._line, self._tokens = text, result
  end
  return result
end

--- Wraps a jieba backend (native or Lua) with the token cap and cache.
--- @param inner table object exposing `:cut(text)`
--- @return table
function M.wrap(inner)
  return setmetatable({ _inner = inner }, Adapter)
end

return M
