--[[
Bilingual reading aid: translate prose paragraphs into Chinese and render the
translation as virtual lines under each source paragraph.

Only paragraphs in the visible part of the window are requested, so opening a
long document costs nothing until the reader scrolls to it. Nothing is written
to the buffer. Translations are cached in memory and on disk, which also makes
edits and reloads free as long as the paragraph text is unchanged.
]]
local M = {}

local NS = vim.api.nvim_create_namespace 'inline-translate'
local AUGROUP = vim.api.nvim_create_augroup('InlineTranslate', { clear = true })

local PROMPT_VERSION = 'v1'
local PREFIX = '  ▍ '
local PREFIX_WIDTH = vim.fn.strdisplaywidth(PREFIX)
local UTF8_CHAR = '[%z\1-\127\194-\244][\128-\191]*'
local CACHE_DIR = 'inline-translate'

local DEFAULT_MODEL = 'google/gemini-2.5-flash-lite'
local DEFAULT_ENDPOINT = 'https://openrouter.ai/api/v1/chat/completions'

local SYSTEM_PROMPT = table.concat({
  'You are a professional translator for a developer reading technical documents.',
  'Translate the text the user sends into Simplified Chinese.',
  'Auto-detect the source language.',
  'Preserve code identifiers, API names, file paths, URLs and numbers exactly as written.',
  'Do not add explanations, notes, quotes or markdown formatting.',
  'Reply with the translation only.',
}, ' ')

local model_env = vim.env.INLINE_TRANSLATE_MODEL
local config = {
  model = model_env ~= nil and model_env ~= '' and model_env or DEFAULT_MODEL,
  endpoint = DEFAULT_ENDPOINT,
  -- nil falls back to $OPENROUTER_API_KEY, then to Pi's OpenRouter token.
  api_key = nil,
  concurrency = 3,
  debounce_ms = 120,
  max_chars = 6000,
}

local states = {}
local cache = {}
local queue = {}
local queue_keys = {}
local inflight = 0
local inflight_keys = {}
local timer = nil
local last_error = nil
local missing_key_notified = false
local key_checked = false
local cached_key = nil

local refresh
local pump

local function utf8_chars(text)
  local chars = {}
  for char in text:gmatch(UTF8_CHAR) do
    chars[#chars + 1] = char
  end
  return chars
end

local function is_blank(line)
  return line:match '^%s*$' ~= nil
end

local function is_rule(line)
  return line:match '^%s*%-%-%-+%s*$' ~= nil or line:match '^%s*%*%*%*+%s*$' ~= nil or line:match '^%s*___+%s*$' ~= nil
end

local function is_table(line)
  return line:match '^%s*|' ~= nil
end

local function is_html(line)
  return line:match '^%s*</?%a[^>]*>%s*$' ~= nil
end

local function is_definition(line)
  return line:match '^%s*%[[^%]]+%]:%s*%S' ~= nil
end

local function is_heading(line)
  return line:match '^%s*#+%s' ~= nil
end

local function is_list_item(line)
  return line:match '^%s*[-*+]%s' ~= nil or line:match '^%s*%d+[.)]%s' ~= nil
end

local function fence_start(line)
  local mark = line:match '^%s*(```+)' or line:match '^%s*(~~~+)'
  return mark and mark:sub(1, 1) or nil
end

local function fence_close(line, char)
  return line:match('^%s*' .. char .. char .. char .. '+%s*$') ~= nil
end

--[[ Strip markdown decoration that only makes sense in the source rendering:
list bullets, blockquote markers, heading hashes, task checkboxes, and link
targets (the visible label is enough context for the translator). ]]
local function clean_line(line)
  local out = line:gsub('^%s*>%s?', '')
  out = out:gsub('^%s*[-*+]%s+', '')
  out = out:gsub('^%s*%d+[.)]%s+', '')
  out = out:gsub('^%s*#+%s+', '')
  out = out:gsub('%s+#+%s*$', '')
  out = out:gsub('!%[([^%]]*)%]%([^%)]*%)', '%1')
  out = out:gsub('%[([^%]]*)%]%([^%)]*%)', '%1')
  out = out:gsub('%[([^%]]*)%]%[[^%]]*%]', '%1')
  return vim.trim(out)
end

local function normalize(text)
  return vim.trim((text:gsub('%s+', ' ')))
end

local function skip_frontmatter(lines)
  if #lines == 0 or lines[1]:match '^%-%-%-%s*$' == nil then
    return 1
  end
  for i = 2, math.min(#lines, 60) do
    if lines[i]:match '^%-%-%-%s*$' or lines[i]:match '^%.%.%.%s*$' then
      return i + 1
    end
  end
  return 1
end

local function skip_html_comment(lines, start)
  for i = start, #lines do
    if lines[i]:find('-->', 1, true) then
      return i + 1
    end
  end
  return #lines + 1
end

local function starts_prose(line)
  return not (
    is_blank(line)
    or is_rule(line)
    or is_table(line)
    or is_html(line)
    or is_definition(line)
    or is_heading(line)
    or is_list_item(line)
    or fence_start(line)
  )
end

local function collect_block(lines, start)
  local last = start
  local text = clean_line(lines[start])
  local i = start + 1
  while i <= #lines and starts_prose(lines[i]) do
    text = text .. ' ' .. clean_line(lines[i])
    last = i
    i = i + 1
  end
  return { s = start - 1, e = last - 1, text = normalize(text) }, i
end

---Split a buffer into translatable blocks of 0-indexed line ranges.
---Fenced code, tables, frontmatter, rules and link definitions are skipped;
---list items and headings become their own blocks so each gets one translation.
---@param lines string[]
---@param filetype string|nil
---@return { s: integer, e: integer, text: string }[]
function M.split_blocks(lines, filetype)
  local blocks = {}
  local i = 1
  local fence = nil
  if filetype == 'markdown' then
    i = skip_frontmatter(lines)
  end

  while i <= #lines do
    local line = lines[i]
    if fence then
      if fence_close(line, fence) then
        fence = nil
      end
      i = i + 1
    elseif fence_start(line) then
      fence = fence_start(line)
      i = i + 1
    elseif line:match '^%s*<!%-%-' then
      i = skip_html_comment(lines, i)
    elseif is_blank(line) or is_rule(line) or is_table(line) or is_html(line) or is_definition(line) then
      i = i + 1
    elseif is_heading(line) then
      blocks[#blocks + 1] = { s = i - 1, e = i - 1, text = clean_line(line) }
      i = i + 1
    else
      local block, next_line = collect_block(lines, i)
      if block.text ~= '' then
        blocks[#blocks + 1] = block
      end
      i = next_line
    end
  end

  return blocks
end

local function cjk_share(text)
  local cjk, visible = 0, 0
  for _, cp in ipairs(vim.fn.str2list(text)) do
    if cp > 32 then
      visible = visible + 1
      if (cp >= 0x3400 and cp <= 0x4dbf) or (cp >= 0x4e00 and cp <= 0x9fff) or (cp >= 0xf900 and cp <= 0xfaff) then
        cjk = cjk + 1
      end
    end
  end
  return visible == 0 and 1 or cjk / visible
end

local function looks_like_identifier(text)
  local stripped = text:gsub('%s+', '')
  if stripped:match '^[%d%p]+$' or text:find('://', 1, true) then
    return true
  end
  -- Bare paths and identifiers are not prose; a lone English word is.
  return not text:find '%s' and stripped:match '^[%w_./:%-#@]+$' ~= nil and stripped:find '[%_./:#]' ~= nil
end

---Translate only blocks whose non-Chinese content is actually worth sending.
---@param text string
---@return boolean
function M.translatable(text)
  text = vim.trim(text)
  if text == '' or #text > config.max_chars or cjk_share(text) >= 0.5 then
    return false
  end
  if vim.fn.strchars((text:gsub('%s+', ''))) < 2 then
    return false
  end
  return not looks_like_identifier(text)
end

---Wrap text on word boundaries using display width (CJK counts as two cells).
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

---Extract the assistant message from an OpenAI-compatible chat completion body.
---@param body string
---@return string|nil
function M.extract_completion(body)
  local ok, data = pcall(vim.json.decode, body)
  if not ok or type(data) ~= 'table' then
    return nil
  end
  local choices = data.choices
  local choice = type(choices) == 'table' and choices[1]
  local content = type(choice) == 'table' and type(choice.message) == 'table' and choice.message.content
  if type(content) ~= 'string' then
    return nil
  end

  content = vim.trim(content)
  content = content:gsub('^```[%w%-_]*%s*', ''):gsub('%s*```$', '')
  content = content:gsub('^"(.*)"$', '%1')
  content = normalize(content)
  return content ~= '' and content or nil
end

local function cache_dir()
  return vim.fs.joinpath(vim.fn.stdpath 'cache', CACHE_DIR)
end

local function cache_key(text)
  return vim.fn.sha256(table.concat({ config.model, PROMPT_VERSION, text }, '\0'))
end

local function read_disk(key)
  local path = vim.fs.joinpath(cache_dir(), key .. '.txt')
  if vim.fn.filereadable(path) == 0 then
    return nil
  end
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or #lines == 0 then
    return nil
  end
  local text = vim.trim(table.concat(lines, '\n'))
  return text ~= '' and text or nil
end

local function write_disk(key, text)
  local dir = cache_dir()
  if vim.fn.isdirectory(dir) == 0 then
    pcall(vim.fn.mkdir, dir, 'p')
  end
  local ok = pcall(vim.fn.writefile, vim.split(text, '\n', { plain = true }), vim.fs.joinpath(dir, key .. '.txt'))
  return ok
end

local function lookup(text)
  local key = cache_key(text)
  if cache[key] then
    return cache[key]
  end
  local disk = read_disk(key)
  if disk then
    cache[key] = disk
  end
  return disk
end

local function pi_openrouter_key()
  local home = vim.env.HOME
  if not home or home == '' then
    return nil
  end
  local path = vim.fs.joinpath(home, '.pi', 'agent', 'auth.json')
  local ok, data = pcall(function()
    return vim.json.decode(table.concat(vim.fn.readfile(path), '\n'))
  end)
  if not ok or type(data) ~= 'table' then
    return nil
  end
  local provider = data.openrouter
  if type(provider) == 'table' and type(provider.access) == 'string' then
    return provider.access
  end
  return nil
end

local function api_key()
  if type(config.api_key) == 'string' and config.api_key ~= '' then
    return config.api_key
  end
  if key_checked then
    return cached_key
  end
  key_checked = true
  cached_key = vim.env.OPENROUTER_API_KEY
  if cached_key == '' then
    cached_key = nil
  end
  if not cached_key then
    cached_key = pi_openrouter_key()
  end
  if cached_key then
    return cached_key
  end
  if not missing_key_notified then
    missing_key_notified = true
    vim.notify(
      'Inline translate: set OPENROUTER_API_KEY (or add an openrouter token to ~/.pi/agent/auth.json)',
      vim.log.levels.WARN
    )
  end
  return nil
end

local function report_error(message)
  if message == last_error then
    return
  end
  last_error = message
  vim.notify('Inline translate: ' .. message, vim.log.levels.WARN)
end

local function request(text, callback)
  local key = api_key()
  if not key then
    vim.schedule(function()
      callback(nil, 'missing OpenRouter API key')
    end)
    return
  end

  local payload = vim.json.encode {
    model = config.model,
    temperature = 0.2,
    max_tokens = 4000,
    messages = {
      { role = 'system', content = SYSTEM_PROMPT },
      { role = 'user', content = text },
    },
  }
  local cmd = {
    'curl',
    '-sS',
    '--max-time',
    '60',
    '-H',
    'authorization: Bearer ' .. key,
    '-H',
    'content-type: application/json',
    '--data-binary',
    '@-',
    '-w',
    '\n%{http_code}',
    config.endpoint,
  }

  -- Always deliver the result from a scheduled callback so the queue never
  -- recurses out of pump() when curl cannot even start.
  local function finish(value, message)
    vim.schedule(function()
      callback(value, message)
    end)
  end

  local ok, err = pcall(vim.system, cmd, { stdin = payload, text = true }, function(res)
    if res.code ~= 0 then
      finish(nil, ('request failed (%s): %s'):format(res.code, vim.trim(res.stderr or '')))
      return
    end
    local body, status = (res.stdout or ''):match '^(.*)\n(%d%d%d)\n?$'
    if not status then
      finish(nil, 'unexpected response from translation service')
      return
    end
    if status ~= '200' then
      finish(nil, ('request failed (HTTP %s): %s'):format(status, body:sub(1, 300)))
      return
    end
    local translation = M.extract_completion(body)
    if not translation then
      finish(nil, 'translation response had no content')
      return
    end
    finish(translation)
  end)
  if not ok then
    finish(nil, 'failed to run curl: ' .. tostring(err))
  end
end

local function state(buf)
  local st = states[buf]
  if not st then
    st = {
      enabled = false,
      marks = {},
      width = 0,
      blocks_tick = -1,
      blocks = {},
    }
    states[buf] = st
  end
  return st
end

local function windows_for(buf)
  local wins = {}
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_buf(win) == buf then
      wins[#wins + 1] = win
    end
  end
  return wins
end

--[[ Virtual lines start at the text column, so subtract number/sign/fold
columns from the window width; otherwise the right edge of each line is clipped. ]]
local function text_width(wins)
  local best = nil
  for _, win in ipairs(wins) do
    local info = vim.fn.getwininfo(win)[1]
    local width = info and info.width - info.textoff or vim.o.columns
    if not best or width < best then
      best = width
    end
  end
  return math.max(10, (best or vim.o.columns) - PREFIX_WIDTH - 2)
end

local function visible_range(win)
  local info = vim.fn.getwininfo(win)[1]
  if not info then
    return nil
  end
  return info.topline - 1, info.botline - 1
end

local function virt_lines(text, width)
  local lines = {}
  for _, line in ipairs(M.wrap(text, width)) do
    lines[#lines + 1] = {
      { PREFIX, 'InlineTranslateMarker' },
      { line, 'InlineTranslateText' },
    }
  end
  return lines
end

local function set_mark(buf, st, block, translation, width)
  local mark = st.marks[block.s]
  if mark and mark.text == translation then
    return
  end
  local opts = { virt_lines = virt_lines(translation, width) }
  if mark then
    opts.id = mark.id
  end
  local ok, id = pcall(vim.api.nvim_buf_set_extmark, buf, NS, block.e, 0, opts)
  if ok then
    st.marks[block.s] = { id = id, text = translation, e = block.e }
  end
end

--[[ A pending paragraph gets a dim ellipsis at the end of its line instead of
a whole virtual line, so queueing many paragraphs does not reflow the viewport
before any translation has arrived. ]]
local function set_pending(buf, st, block)
  if st.marks[block.s] then
    return
  end
  local ok, id = pcall(vim.api.nvim_buf_set_extmark, buf, NS, block.e, 0, {
    virt_text = { { ' …', 'InlineTranslatePending' } },
  })
  if ok then
    st.marks[block.s] = { id = id, e = block.e }
  end
end

local function rerender(buf, st, width)
  for key, mark in pairs(st.marks) do
    if mark.text then
      local ok = pcall(vim.api.nvim_buf_set_extmark, buf, NS, mark.e, 0, {
        id = mark.id,
        virt_lines = virt_lines(mark.text, width),
      })
      if not ok then
        st.marks[key] = nil
      end
    end
  end
end

local function clear_marks(buf, st)
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
  end
  st.marks = {}
end

local function blocks_for(buf, st)
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  if st.blocks_tick ~= tick then
    st.blocks = M.split_blocks(vim.api.nvim_buf_get_lines(buf, 0, -1, false), vim.bo[buf].filetype)
    st.blocks_tick = tick
  end
  return st.blocks
end

local function enqueue(buf, text)
  local key = cache_key(text)
  if queue_keys[key] or inflight_keys[key] then
    return
  end
  queue[#queue + 1] = { buf = buf, key = key, text = text }
  queue_keys[key] = true
end

local function drop_stale(buf, keep)
  local kept = {}
  queue_keys = {}
  for _, item in ipairs(queue) do
    if item.buf ~= buf or keep[item.key] then
      kept[#kept + 1] = item
    end
  end
  queue = kept
  for _, item in ipairs(queue) do
    queue_keys[item.key] = true
  end
end

local function update_buffer(buf, st, wins)
  local width = text_width(wins)
  if st.width ~= width then
    rerender(buf, st, width)
    st.width = width
  end

  local top, bottom
  for _, win in ipairs(wins) do
    local first, last = visible_range(win)
    if first then
      top = top and math.min(top, first) or first
      bottom = bottom and math.max(bottom, last) or last
    end
  end
  if not top then
    return
  end

  top = math.max(0, top - 1)
  bottom = math.min(bottom + 1, vim.api.nvim_buf_line_count(buf) - 1)
  local visible = {}
  for _, block in ipairs(blocks_for(buf, st)) do
    if block.e >= top and block.s <= bottom then
      visible[cache_key(block.text)] = true
      local translation = lookup(block.text)
      if translation then
        set_mark(buf, st, block, translation, width)
      elseif M.translatable(block.text) then
        set_pending(buf, st, block)
        enqueue(buf, block.text)
      end
    end
  end
  drop_stale(buf, visible)
end

local function is_transient(message)
  return message:find('HTTP 429', 1, true) ~= nil
    or message:find('HTTP 5', 1, true) ~= nil
    or message:find('(28)', 1, true) ~= nil
end

--[[ Retries keep the cache key marked as in flight until the item is back in the
queue, otherwise a viewport refresh would enqueue a duplicate request. ]]
local function retry(item)
  item.attempts = item.attempts + 1
  vim.defer_fn(function()
    inflight_keys[item.key] = nil
    queue[#queue + 1] = item
    queue_keys[item.key] = true
    pump()
  end, 2000 * item.attempts)
end

pump = function()
  while inflight < config.concurrency and #queue > 0 do
    local item = table.remove(queue, 1)
    queue_keys[item.key] = nil
    local st = states[item.buf]
    if st and st.enabled and vim.api.nvim_buf_is_valid(item.buf) then
      item.attempts = item.attempts or 0
      inflight_keys[item.key] = true
      inflight = inflight + 1
      request(item.text, function(translation, err)
        inflight = inflight - 1
        if translation then
          inflight_keys[item.key] = nil
          cache[item.key] = translation
          write_disk(item.key, translation)
          refresh()
        elseif err and item.attempts < 2 and is_transient(err) then
          retry(item)
        else
          inflight_keys[item.key] = nil
          if err then
            report_error(err)
          end
        end
        pump()
      end)
    end
  end
end

refresh = function()
  for buf, st in pairs(states) do
    if st.enabled and vim.api.nvim_buf_is_valid(buf) then
      local wins = windows_for(buf)
      if #wins > 0 then
        update_buffer(buf, st, wins)
      end
    end
  end
  pump()
end

local function schedule_refresh()
  if timer then
    timer:stop()
  end
  timer = vim.defer_fn(function()
    timer = nil
    refresh()
  end, config.debounce_ms)
end

--[[ Drop rendered marks after the text (or the filetype) changed. Cached
translations survive, so the next refresh re-renders without new requests. ]]
local function invalidate(buf)
  local st = states[buf]
  if not st then
    return
  end
  clear_marks(buf, st)
  st.blocks_tick = -1
  schedule_refresh()
end

local function define_highlights()
  vim.api.nvim_set_hl(0, 'InlineTranslateText', { link = 'Comment' })
  vim.api.nvim_set_hl(0, 'InlineTranslateMarker', { link = 'DiagnosticInfo' })
  vim.api.nvim_set_hl(0, 'InlineTranslatePending', { link = 'DiagnosticHint' })
end

---Toggle bilingual inline translation for the current buffer.
function M.toggle()
  local buf = vim.api.nvim_get_current_buf()
  if vim.bo[buf].buftype ~= '' then
    vim.notify('Inline translate only works in normal file buffers', vim.log.levels.WARN)
    return
  end

  local st = state(buf)
  if st.enabled then
    st.enabled = false
    clear_marks(buf, st)
    vim.notify 'Inline translate: off'
    return
  end

  last_error = nil
  st.enabled = true
  vim.notify 'Inline translate: on (translating visible paragraphs)'
  refresh()
end

---Delete every cached translation so the next render hits the network again.
function M.clear_cache()
  cache = {}
  local files = vim.fn.globpath(cache_dir(), '*.txt', false, true)
  for _, file in ipairs(files) do
    vim.fn.delete(file)
  end
  vim.notify(('Inline translate: cleared %d cached translations'):format(#files))
end

function M.setup(opts)
  if opts then
    for key, value in pairs(opts) do
      config[key] = value
    end
  end
  define_highlights()

  vim.api.nvim_create_autocmd('ColorScheme', { group = AUGROUP, callback = define_highlights })
  vim.api.nvim_create_autocmd({ 'WinScrolled', 'WinResized', 'WinEnter', 'TabEnter', 'BufEnter', 'BufWinEnter' }, {
    group = AUGROUP,
    callback = schedule_refresh,
  })
  vim.api.nvim_create_autocmd({ 'TextChanged', 'BufReadPost', 'FileType' }, {
    group = AUGROUP,
    callback = function(args)
      invalidate(args.buf)
    end,
  })
  vim.api.nvim_create_autocmd('BufWipeout', {
    group = AUGROUP,
    callback = function(args)
      states[args.buf] = nil
    end,
  })

  vim.api.nvim_create_user_command('InlineTranslate', M.toggle, { desc = 'Toggle inline bilingual translation' })

  require('cmdr').add {
    {
      desc = 'Translate: toggle inline translation',
      cmd = M.toggle,
      cat = 'translate',
    },
    {
      desc = 'Translate: clear translation cache',
      cmd = M.clear_cache,
      cat = 'translate',
    },
  }
end

return M
