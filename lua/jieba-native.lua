--[[ Rust-backed jieba segmentation (`jieba-rs`) exposed to wordmotion.

The shared library is built from `lua/jieba-native/rust` and installed by
`just build-native` into `stdpath('data')/jieba-native/`. `new()` returns nil
plus a reason when the library is missing or LuaJIT FFI is unavailable, so the
plugin can fall back to the pure-Lua jieba dictionary.

Only the slice of the `jieba.jieba` API that wordmotion uses is implemented: an
object with `:cut(str)` returning the words of `str` as byte-exact tokens.
]]

local M = {}

local ffi, lib, loaded, load_error

local function lib_name()
  return vim.uv.os_uname().sysname == 'Darwin' and 'libjieba_native.dylib' or 'libjieba_native.so'
end

local function cdll()
  ffi.cdef [[
    void *jieba_native_new(void);
    void jieba_native_free(void *handle);
    size_t jieba_native_cut(const void *handle, const char *text, size_t len,
                            uint32_t *out, size_t cap, int use_hmm);
  ]]
end

--[[ Load the shared library once; every later call reuses it.
Returns false plus the reason string when the native path is unavailable. ]]
local function ensure()
  if loaded ~= nil then
    return loaded, load_error
  end
  loaded = false

  local ok_ffi, mod = pcall(require, 'ffi')
  if not ok_ffi then
    load_error = 'LuaJIT FFI unavailable'
    return false, load_error
  end
  ffi = mod

  local path = vim.env.NVIM_JIEBA_NATIVE_LIB or vim.fs.joinpath(vim.fn.stdpath 'data', 'jieba-native', lib_name())
  if vim.fn.filereadable(path) == 0 then
    load_error = path .. ' not found (run `just build-native`)'
    return false, load_error
  end

  local ok_load, res = pcall(function()
    cdll()
    return ffi.load(path)
  end)
  if not ok_load then
    load_error = tostring(res)
    return false, load_error
  end

  lib = res
  loaded = true
  return true
end

local Segmenter = {}
Segmenter.__index = Segmenter

--[[ Cut `text` into word tokens. The result is always an exact partition of the
input: separators that jieba drops (spaces, punctuation gaps) are emitted as
their own tokens, which wordmotion relies on to compute byte offsets. ]]
function Segmenter:cut(text)
  local len = #text
  if len == 0 then
    return {}
  end

  local needed = tonumber(lib.jieba_native_cut(self._handle, text, len, nil, 0, self._hmm))
  if needed == 0 then
    return { text }
  end
  if needed > self._cap then
    self._offsets = ffi.new('uint32_t[?]', needed)
    self._cap = needed
  end

  local written = tonumber(lib.jieba_native_cut(self._handle, text, len, self._offsets, self._cap, self._hmm))
  local tokens, prev = {}, 0
  for i = 0, math.floor(written / 2) - 1 do
    local s, e = self._offsets[i * 2], self._offsets[i * 2 + 1]
    if s > prev then
      tokens[#tokens + 1] = text:sub(prev + 1, s)
    end
    tokens[#tokens + 1] = text:sub(s + 1, e)
    prev = e
  end
  if prev < len then
    tokens[#tokens + 1] = text:sub(prev + 1)
  end
  return tokens
end

--- Creates a segmenter, or returns nil plus the reason it is unavailable.
--- @param opts {hmm: boolean}? HMM mode, enabled by default like the Lua jieba.
--- @return table?
function M.new(opts)
  local ok, reason = ensure()
  if not ok then
    return nil, reason
  end

  local handle = lib.jieba_native_new()
  if handle == nil then
    return nil, 'jieba_native_new returned NULL'
  end
  ffi.gc(handle, function(ptr)
    lib.jieba_native_free(ptr)
  end)

  local hmm = opts == nil or opts.hmm == nil or opts.hmm
  return setmetatable({
    _handle = handle,
    _hmm = hmm and 1 or 0,
    _cap = 0,
  }, Segmenter)
end

local shared, shared_error

--- Shared segmenter, built on first use (or by `prewarm`).
--- Options only apply to the call that creates it; later calls reuse it.
--- @return table? segmenter, string? reason
function M.get(opts)
  if shared == nil then
    shared, shared_error = M.new(opts)
    shared = shared or false
  end
  return shared or nil, shared_error
end

--- Builds the shared segmenter ahead of time, so the background cost lands
--- before the first word motion instead of inside it. Safe no-op when the
--- library is not built.
function M.prewarm(opts)
  return M.get(opts)
end

--- Why the native segmenter is unavailable; nil when it loads.
function M.reason()
  local ok, reason = ensure()
  return ok and nil or reason
end

return M
