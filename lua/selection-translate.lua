--[[
Translate the visual selection into Chinese in a floating reading card.

The card opens before the request finishes and fills as tokens arrive. One
card exists at a time: opening another cancels the first stream and closes its
window, so a late chunk can never write into a reused buffer. The selection is
captured from the live visual mode before the float takes focus; closing a
card that came from visual mode restores the window and the selection.
]]
local M = {}

local magpie = require 'magpie'
local wrap = require('text-wrap').wrap

local NS = vim.api.nvim_create_namespace 'selection-translate'
local AUGROUP = vim.api.nvim_create_augroup('SelectionTranslate', { clear = true })

local DEFAULT_MODEL = 'remote-magpie/group/deepseek-flash'
local MAX_SOURCE_ROWS = 4
local TICK_MS = 120
local TYPE_INTERVAL_MS = 30
local SPINNER = { '⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏' }

local SYSTEM_PROMPT = table.concat({
  'You translate text into Simplified Chinese for a developer reading in Neovim.',
  "Translate accurately into natural, idiomatic Chinese and keep the author's tone.",
  'Preserve code identifiers, API names, file paths, URLs, numbers, and inline code exactly.',
  'If the text is already Chinese, return it unchanged.',
  'If the text is code, reproduce it unchanged.',
  'Do not add notes, explanations, quotes, or markdown fences.',
  'Reply with the translation only.',
}, ' ')

local config = {
  model = nil,
  width = 76,
  max_chars = 8000,
  max_tokens = 4096,
  temperature = 0.2,
  endpoint_label = nil,
}

local client = magpie
local card = nil

--[[ One transition table owns the lifecycle; no pair of booleans can disagree. ]]
local NEXT = {
  pending = { delta = 'streaming', done = 'done', error = 'error' },
  streaming = { delta = 'streaming', done = 'done', error = 'error' },
  done = {},
  error = { retry = 'pending' },
}

local function transition(target, event)
  local next_phase = (NEXT[target.phase] or {})[event]
  if not next_phase then
    return false
  end
  target.phase = next_phase
  return true
end

local function expand(line)
  return (line:gsub('\t', '  '):gsub('%s+$', ''))
end

local function common_indent(lines)
  local common
  for _, line in ipairs(lines) do
    if vim.trim(line) ~= '' then
      local lead = line:match '^( *)' or ''
      if common == nil or #lead < #common then
        common = lead
      end
    end
  end
  return common or ''
end

--[[ Wrapped rows keep a line's indentation so code keeps its shape, and cap an
extreme indent so the text column never collapses at the card edge. ]]
local function display_lines(text, width)
  local lines = vim.tbl_map(expand, vim.split(text or '', '\n', { plain = true }))
  local indent = common_indent(lines)
  local rows = {}
  for _, line in ipairs(lines) do
    local lead, rest = line:match '^( *)(.*)$'
    lead = lead:sub(#indent + 1):sub(1, 20)
    local available = math.max(10, width - vim.fn.strdisplaywidth(lead))
    for _, wrapped in ipairs(wrap(rest, available)) do
      rows[#rows + 1] = lead .. wrapped
    end
  end

  while rows[1] == '' do
    table.remove(rows, 1)
  end
  while rows[#rows] == '' do
    table.remove(rows)
  end

  local collapsed = {}
  for _, row in ipairs(rows) do
    if row ~= '' or collapsed[#collapsed] ~= '' then
      collapsed[#collapsed + 1] = row
    end
  end
  return collapsed
end

local function bar_row(bar, bar_group, text, body_group)
  return {
    text = '  ' .. bar .. ' ' .. text,
    group = body_group,
    bar = { start = 2, stop = 2 + #bar, group = bar_group },
  }
end

local function source_block(source, width)
  local lines = display_lines(source, width)
  local shown = math.min(#lines, MAX_SOURCE_ROWS)
  local rows = {}
  for i = 1, shown do
    rows[#rows + 1] = bar_row('│', 'TranslateCardSourceBar', lines[i], 'TranslateCardSource')
  end
  if #lines > shown then
    rows[#rows + 1] = { text = '  │ … ' .. (#lines - shown) .. ' more lines', group = 'TranslateCardSource' }
  end
  return rows
end

local function body_block(snapshot, width)
  local rows = {}
  local has_text = type(snapshot.text) == 'string' and snapshot.text ~= ''

  if has_text then
    for _, line in ipairs(display_lines(snapshot.text, width)) do
      rows[#rows + 1] = bar_row('▍', 'TranslateCardTranslationBar', line, 'TranslateCardText')
    end
    if snapshot.truncated then
      rows[#rows + 1] = { text = '  … (truncated)', group = 'TranslateCardMeta' }
    end
    if snapshot.phase == 'error' then
      rows[#rows + 1] = { text = '', group = '' }
    end
  end

  if snapshot.phase == 'error' then
    for _, line in ipairs(display_lines(snapshot.error_text or 'Translation failed', width)) do
      rows[#rows + 1] = bar_row('▍', 'DiagnosticError', line, 'DiagnosticError')
    end
  elseif not has_text then
    local label = snapshot.thinking and 'Thinking…' or 'Translating…'
    rows[#rows + 1] = bar_row('▍', 'TranslateCardPending', label, 'TranslateCardPending')
  end
  return rows
end

---Build the card body. `outer` is the bordered width in display cells.
---@param snapshot table
---@param outer integer
---@return table[] rows, integer measure
function M.card_lines(snapshot, outer)
  local win_w = math.max(20, outer - 2)
  local measure = math.max(10, win_w - 4)
  local body_w = math.max(10, measure - 2)

  local rows = { { text = '', group = '' } }
  vim.list_extend(rows, source_block(snapshot.source or '', body_w))
  rows[#rows + 1] = { text = '', group = '' }
  rows[#rows + 1] = { text = '  ' .. string.rep('─', measure), group = 'TranslateCardRule' }
  rows[#rows + 1] = { text = '', group = '' }
  vim.list_extend(rows, body_block(snapshot, body_w))
  rows[#rows + 1] = { text = '', group = '' }
  return rows, measure
end

local ERROR_LABELS = {
  gateway_down = 'gateway down',
  timeout = 'timeout',
  http = 'HTTP error',
  empty = 'empty answer',
  transport = 'request failed',
  protocol = 'bad response',
}

local function short_model(model)
  return (model or ''):match '([^/]+)$' or model or 'model'
end

---@param snapshot table
---@return string
function M.status_text(snapshot)
  if snapshot.phase == 'error' then
    local failure = type(snapshot.error) == 'table' and snapshot.error or {}
    if failure.kind == 'http' and type(failure.status) == 'number' then
      return 'error · HTTP ' .. failure.status
    end
    return 'error · ' .. (ERROR_LABELS[failure.kind] or 'request failed')
  end
  if snapshot.phase == 'done' then
    return ('done · %.1fs · %s'):format((snapshot.elapsed_ms or 0) / 1000, short_model(snapshot.model))
  end
  local label = snapshot.thinking and 'thinking' or 'translating'
  return label .. ' · ' .. short_model(snapshot.model)
end

---@param snapshot table
---@param elapsed_ms integer|nil
---@param frame string|nil
---@return string
function M.footer_text(snapshot, elapsed_ms, frame)
  local status = M.status_text(snapshot)
  if elapsed_ms and (snapshot.phase == 'pending' or snapshot.phase == 'streaming') then
    local label = snapshot.thinking and 'thinking' or 'translating'
    local spin = frame and (frame .. ' ') or ''
    status = ('%s%s · %.1fs · %s'):format(spin, label, elapsed_ms / 1000, short_model(snapshot.model))
  end
  local keys = 'q close'
  if snapshot.phase == 'done' then
    keys = 'q close · y copy'
  elseif snapshot.phase == 'error' then
    keys = 'q close · r retry'
  end
  return status .. '  ' .. keys
end

---@param err table
---@param endpoint string|nil
---@return string
function M.error_text(err, endpoint)
  local kind = type(err) == 'table' and err.kind or nil
  if kind == 'gateway_down' then
    return ('Magpie is not reachable at %s. Start it, then press r to retry.'):format(endpoint or 'the gateway')
  end
  if kind == 'timeout' then
    return 'Magpie did not answer in time. Press r to retry.'
  end
  if kind == 'http' then
    local detail = type(err.detail) == 'string' and (': ' .. err.detail) or '.'
    return ('Magpie returned HTTP %s%s'):format(err.status or 'error', detail)
  end
  if kind == 'empty' then
    return 'Magpie returned an empty answer. Press r to retry.'
  end
  if kind == 'protocol' then
    return 'The gateway sent a response this card could not read.'
  end
  return 'The request to Magpie failed. Press r to retry.'
end

---@param endpoint string|nil
---@return string
function M.endpoint_label(endpoint)
  local host = (endpoint or ''):gsub('^%a+://', '')
  return (host:gsub('/.*$', ''))
end

---@param text string
---@return table[]
function M.build_prompt(text, filetype)
  local system = SYSTEM_PROMPT
  if type(filetype) == 'string' and filetype ~= '' then
    system = system .. ' The text comes from a ' .. filetype .. ' buffer.'
  end
  return {
    { role = 'system', content = system },
    { role = 'user', content = text },
  }
end

---Strip a wrapping fence or quotes the model sometimes adds anyway.
---@param text string
---@return string
function M.normalize(text)
  text = vim.trim(text or '')
  text = text:gsub('^```[%w_%-]*%s*', ''):gsub('%s*```$', '')
  text = text:gsub('^"(.*)"$', '%1')
  return vim.trim(text)
end

---Reveal the first `visible` characters, never half of a UTF-8 character.
---@param text string
---@param visible integer
---@return string
function M.partial(text, visible)
  if type(text) ~= 'string' or visible <= 0 then
    return ''
  end
  return vim.fn.strcharpart(text, 0, visible)
end

local function snapshot(target)
  return {
    phase = target.phase,
    source = target.source,
    text = M.partial(target.text, target.visible),
    error = target.error,
    error_text = target.error and M.error_text(target.error, config.endpoint_label) or nil,
    model = target.model,
    elapsed_ms = target.elapsed_ms,
    truncated = target.truncated,
    thinking = target.thinking,
  }
end

local function footer_for(target)
  return M.footer_text(snapshot(target), vim.uv.now() - target.started_at, SPINNER[target.frame])
end

local function update_footer(target)
  if not target.win or not vim.api.nvim_win_is_valid(target.win) then
    return
  end
  local footer = ' ' .. footer_for(target) .. ' '
  target.footer = footer
  vim.api.nvim_win_set_config(target.win, {
    height = target.height,
    footer = { { footer, 'TranslateCardFooter' } },
    footer_pos = 'right',
  })
end

local function start_ticker(target)
  target.started_at = vim.uv.now()
  target.frame = 1
  local function tick()
    if card ~= target or target.phase == 'done' or target.phase == 'error' then
      return
    end
    target.frame = target.frame % #SPINNER + 1
    update_footer(target)
    vim.defer_fn(tick, TICK_MS)
  end
  vim.defer_fn(tick, TICK_MS)
end

local function layout(target)
  target.outer = math.min(config.width, math.max(30, vim.o.columns - 8))
  target.max_height = math.max(8, math.min(30, math.floor((vim.o.lines - 1) * 0.7)))
  target.row = math.max(0, math.floor((vim.o.lines - (target.max_height + 2)) / 2))
  target.col = math.max(0, math.floor((vim.o.columns - target.outer) / 2))
end

local render

render = function()
  local target = card
  if not target or not target.buf or not vim.api.nvim_buf_is_valid(target.buf) then
    return
  end

  local snap = snapshot(target)
  local rows = M.card_lines(snap, target.outer)
  local height = math.min(#rows, target.max_height)
  local footer = ' ' .. footer_for(target) .. ' '

  vim.bo[target.buf].modifiable = true
  vim.api.nvim_buf_set_lines(
    target.buf,
    0,
    -1,
    false,
    vim.tbl_map(function(row)
      return row.text
    end, rows)
  )
  vim.bo[target.buf].modifiable = false
  vim.bo[target.buf].modified = false

  vim.api.nvim_buf_clear_namespace(target.buf, NS, 0, -1)
  for i, row in ipairs(rows) do
    if row.text ~= '' and row.group then
      vim.api.nvim_buf_set_extmark(target.buf, NS, i - 1, 0, {
        end_col = #row.text,
        hl_group = row.group,
      })
    end
    if row.bar then
      vim.api.nvim_buf_set_extmark(target.buf, NS, i - 1, row.bar.start, {
        end_col = row.bar.stop,
        hl_group = row.bar.group,
        priority = 10,
      })
    end
  end

  if target.win and vim.api.nvim_win_is_valid(target.win) and (height ~= target.height or footer ~= target.footer) then
    target.height = height
    target.footer = footer
    vim.api.nvim_win_set_config(target.win, {
      relative = 'editor',
      row = target.row,
      col = target.col,
      width = target.outer - 2,
      height = height,
      footer = { { footer, 'TranslateCardFooter' } },
      footer_pos = 'right',
    })
  end
end

local function render_now()
  if card then
    render()
  end
end

local function finish_typing(target)
  if not target.received_done or target.visible < target.total_chars then
    return
  end
  if not transition(target, 'done') then
    return
  end
  local meta = target.pending_meta
  target.model = meta and meta.model or target.model
  target.elapsed_ms = math.max(meta and meta.elapsed_ms or 0, vim.uv.now() - target.started_at)
  target.truncated = target.pending_truncated or false
  target.received_done = false
  render()
end

local function type_step(pending)
  if pending > 260 then
    return 4
  end
  if pending > 120 then
    return 2
  end
  return 1
end

--[[ One timer advances the visible prefix of the answer. It stops when the
card is caught up and restarts on the next delta, so a burst from the gateway
still types out instead of appearing all at once. ]]
local function ensure_typing(target, run)
  if card ~= target or target.run ~= run or target.phase == 'error' then
    return
  end
  if target.visible >= target.total_chars then
    target.type_running = false
    finish_typing(target)
    return
  end
  if target.type_running then
    return
  end
  target.type_running = true
  local function tick()
    if card ~= target or target.run ~= run or target.phase == 'error' then
      target.type_running = false
      return
    end
    if target.visible >= target.total_chars then
      target.type_running = false
      finish_typing(target)
      return
    end
    target.visible = math.min(target.total_chars, target.visible + type_step(target.total_chars - target.visible))
    render()
    vim.defer_fn(tick, TYPE_INTERVAL_MS)
  end
  vim.defer_fn(tick, TYPE_INTERVAL_MS)
end

local function start_stream(target)
  target.run = target.run + 1
  local run = target.run
  target.stream = client.stream({
    model = config.model or DEFAULT_MODEL,
    messages = M.build_prompt(target.source, target.filetype),
    temperature = config.temperature,
    max_tokens = config.max_tokens,
  }, {
    on_delta = function(text)
      if card ~= target or target.run ~= run or not transition(target, 'delta') then
        return
      end
      target.thinking = false
      target.text = target.text .. text
      target.total_chars = vim.fn.strchars(target.text)
      ensure_typing(target, run)
    end,
    on_reasoning = function()
      if card ~= target or target.run ~= run or target.thinking then
        return
      end
      target.thinking = true
      render_now()
    end,
    on_done = function(text, meta)
      if card ~= target or target.run ~= run then
        return
      end
      local cleaned = M.normalize(text)
      if cleaned == '' then
        if transition(target, 'error') then
          target.error = { kind = 'empty' }
          target.elapsed_ms = meta and meta.elapsed_ms or nil
          target.visible = target.total_chars
          render_now()
        end
        return
      end
      target.text = cleaned
      target.total_chars = vim.fn.strchars(target.text)
      target.received_done = true
      target.pending_meta = meta
      target.pending_truncated = meta and meta.truncated or false
      ensure_typing(target, run)
    end,
    on_error = function(err)
      if card ~= target or target.run ~= run or not transition(target, 'error') then
        return
      end
      target.error = err
      target.elapsed_ms = nil
      target.visible = target.total_chars
      target.type_running = false
      render_now()
    end,
  })
end

local close_card

---Copy the finished translation. The card stays open so the reader can compare.
function M.copy()
  local target = card
  if not target or target.phase ~= 'done' or target.text == '' then
    return
  end
  local copied = pcall(vim.fn.setreg, '+', target.text)
  if not copied then
    vim.fn.setreg('"', target.text)
  end
  vim.notify(copied and 'Translation copied' or 'Translation copied to the unnamed register', vim.log.levels.INFO)
end

---Retry the same selection after an error.
function M.retry()
  local target = card
  if not target or target.phase ~= 'error' or not transition(target, 'retry') then
    return
  end
  if target.stream then
    pcall(target.stream.cancel)
  end
  target.text = ''
  target.error = nil
  target.elapsed_ms = nil
  target.truncated = false
  target.thinking = false
  target.visible = 0
  target.total_chars = 0
  target.received_done = false
  target.pending_meta = nil
  target.pending_truncated = false
  target.type_running = false
  start_ticker(target)
  render_now()
  start_stream(target)
end

---Close the card. The public path restores the window and selection it came from.
function M.close()
  close_card(true)
end

close_card = function(restore)
  local target = card
  if not target then
    return
  end
  card = nil
  if target.stream then
    pcall(target.stream.cancel)
  end
  if target.win and vim.api.nvim_win_is_valid(target.win) then
    pcall(vim.api.nvim_win_close, target.win, true)
  end
  if target.buf and vim.api.nvim_buf_is_valid(target.buf) then
    pcall(vim.api.nvim_buf_delete, target.buf, { force = true })
  end
  if restore and target.restore and target.origin_win and vim.api.nvim_win_is_valid(target.origin_win) then
    pcall(vim.api.nvim_set_current_win, target.origin_win)
    pcall(vim.cmd, 'normal! gv')
  end
end

local function open(source, filetype, restore)
  close_card(false)

  local target = {
    phase = 'pending',
    source = source,
    filetype = filetype,
    text = '',
    error = nil,
    model = config.model,
    elapsed_ms = nil,
    truncated = false,
    restore = restore,
    origin_win = vim.api.nvim_get_current_win(),
    run = 0,
    thinking = false,
    visible = 0,
    total_chars = 0,
    received_done = false,
    pending_meta = nil,
    pending_truncated = false,
    type_running = false,
    footer = nil,
    frame = 1,
    started_at = vim.uv.now(),
    buf = nil,
    win = nil,
    stream = nil,
  }
  card = target
  layout(target)

  local snap = snapshot(target)
  local rows = M.card_lines(snap, target.outer)
  target.height = math.min(#rows, target.max_height)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false
  vim.bo[buf].undolevels = -1
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = 'translate-card'

  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    row = target.row,
    col = target.col,
    width = target.outer - 2,
    height = target.height,
    style = 'minimal',
    border = 'rounded',
    title = ' Translate → Chinese ',
    title_pos = 'center',
    footer = { { ' ' .. footer_for(target) .. ' ', 'TranslateCardFooter' } },
    footer_pos = 'right',
    mouse = true,
    noautocmd = true,
    zindex = 60,
  })
  target.buf, target.win = buf, win

  --[[ `hide = true` hides the whole float, not just its cursor, so the cursor is
made invisible by painting it with the card's own colours instead. ]]
  vim.wo[win].winhl =
    'NormalFloat:TranslateCardNormal,FloatBorder:TranslateCardBorder,FloatTitle:TranslateCardTitle,FloatFooter:TranslateCardFooter,Cursor:TranslateCardNormal'
  vim.wo[win].wrap = false
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].cursorline = false
  vim.wo[win].spell = false
  vim.wo[win].list = false
  vim.wo[win].signcolumn = 'no'
  vim.wo[win].foldcolumn = '0'
  vim.wo[win].scrolloff = 0
  vim.wo[win].winbar = ''

  local bindings = {
    q = { M.close, 'Close translation' },
    ['<Esc>'] = { M.close, 'Close translation' },
    ['<C-c>'] = { M.close, 'Close translation' },
    y = { M.copy, 'Copy translation' },
    r = { M.retry, 'Retry translation' },
  }
  for key, binding in pairs(bindings) do
    vim.keymap.set('n', key, binding[1], { buffer = buf, silent = true, nowait = true, desc = binding[2] })
  end

  vim.api.nvim_create_autocmd('WinClosed', {
    group = AUGROUP,
    pattern = tostring(win),
    once = true,
    callback = function()
      if card == target then
        close_card(false)
      end
    end,
  })

  render()
  start_ticker(target)
  start_stream(target)
end

local function capture()
  local mode = vim.fn.mode()
  if mode == 's' then
    mode = 'v'
  elseif mode == 'S' then
    mode = 'V'
  elseif mode == '\19' then
    mode = '\22'
  end
  local visual = mode == 'v' or mode == 'V' or mode == '\22'

  local pos1, pos2, kind
  if visual then
    pos1, pos2, kind = vim.fn.getpos 'v', vim.fn.getpos '.', mode
  else
    pos1, pos2 = vim.fn.getpos "'<", vim.fn.getpos "'>"
    kind = vim.fn.visualmode()
    if kind == '' then
      kind = 'v'
    end
  end
  if pos1[2] == 0 or pos2[2] == 0 then
    return nil, 'empty'
  end

  local ok, lines = pcall(vim.fn.getregion, pos1, pos2, { type = kind, exclusive = false })
  if not ok then
    return nil, 'unreadable'
  end
  local text = vim.trim(table.concat(lines, '\n'))
  if text == '' then
    return nil, 'empty'
  end
  local count = vim.fn.strchars(text)
  if count > config.max_chars then
    return nil, 'large', count
  end
  return { text = text, filetype = vim.bo.filetype, restore = visual }, nil, count
end

---Capture the live visual selection, or the last one when called from the palette.
function M.translate_selection()
  local selection, reason, count = capture()
  if not selection then
    if reason == 'large' then
      vim.notify(
        ('Selection is too long to translate (%d characters, max %d)'):format(count, config.max_chars),
        vim.log.levels.WARN
      )
    elseif reason == 'unreadable' then
      vim.notify('Could not read the selection', vim.log.levels.WARN)
    else
      vim.notify('Select text first', vim.log.levels.WARN)
    end
    return
  end
  open(selection.text, selection.filetype, selection.restore)
end

local function define_highlights()
  vim.api.nvim_set_hl(0, 'TranslateCardNormal', { link = 'NormalFloat' })
  vim.api.nvim_set_hl(0, 'TranslateCardBorder', { link = 'FloatBorder' })
  vim.api.nvim_set_hl(0, 'TranslateCardTitle', { link = 'Title' })
  vim.api.nvim_set_hl(0, 'TranslateCardFooter', { link = 'Comment' })
  vim.api.nvim_set_hl(0, 'TranslateCardSource', { link = 'Comment' })
  vim.api.nvim_set_hl(0, 'TranslateCardSourceBar', { link = 'DiagnosticHint' })
  vim.api.nvim_set_hl(0, 'TranslateCardTranslationBar', { link = 'DiagnosticInfo' })
  vim.api.nvim_set_hl(0, 'TranslateCardRule', { link = 'FloatBorder' })
  vim.api.nvim_set_hl(0, 'TranslateCardText', { link = 'NormalFloat' })
  vim.api.nvim_set_hl(0, 'TranslateCardPending', { link = 'DiagnosticHint' })
  vim.api.nvim_set_hl(0, 'TranslateCardMeta', { link = 'Comment' })
end

---@param opts? table
function M.setup(opts)
  opts = opts or {}
  for key, value in pairs(opts) do
    if key ~= 'client' then
      config[key] = value
    end
  end
  client = opts.client or magpie
  if client.setup then
    client.setup(opts)
  end

  config.model = config.model or vim.env.TRANSLATE_MODEL
  if config.model == '' then
    config.model = nil
  end
  config.model = config.model or DEFAULT_MODEL
  config.endpoint_label = M.endpoint_label(magpie.resolve(opts).endpoint)

  define_highlights()
  vim.api.nvim_create_autocmd('ColorScheme', { group = AUGROUP, callback = define_highlights })
  vim.api.nvim_create_autocmd('VimResized', {
    group = AUGROUP,
    callback = function()
      if card and card.win and vim.api.nvim_win_is_valid(card.win) then
        layout(card)
        render()
      end
    end,
  })

  vim.api.nvim_create_user_command('Translate', M.translate_selection, {
    desc = 'Translate the selection into Chinese',
    force = true,
  })

  require('cmdr').add {
    {
      desc = 'Translate: selection to Chinese',
      cmd = M.translate_selection,
      keys = { 'x', '<leader>t' },
      cat = 'translate',
    },
  }
end

return M
