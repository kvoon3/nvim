--[[
Streaming chat client for the local magpie gateway.

The gateway speaks the OpenAI chat-completions protocol. Requests go through
curl so the feature needs no HTTP library, and the response is Server-Sent
Events, which curl hands over in arbitrary chunks. The client reassembles
those chunks into lines before parsing them.

Each request owns one curl process. Cancelling kills it and suppresses every
later callback, so a closed card can never be written by a late chunk. Every
callback is scheduled onto the main loop; the stdout callback runs in a fast
event where touching a buffer would raise E5560.
]]
local M = {}

local DEFAULT_BASE = 'http://127.0.0.1:3425'
local DEFAULT_TIMEOUT_MS = 45000
local DEFAULT_MAX_TOKENS = 4096

local config

--[[ `ipairs` stops at the first nil, so iterate with `select` to keep
precedence working when the preferred value is absent. ]]
local function first_string(...)
  for i = 1, select('#', ...) do
    local value = select(i, ...)
    if type(value) == 'string' and value ~= '' then
      return value
    end
  end
  return nil
end

local function endpoint_of(base)
  base = base:gsub('/+$', '')
  if base:match '/chat/completions$' then
    return base
  end
  if base:match '/v1$' then
    return base .. '/chat/completions'
  end
  return base .. '/v1/chat/completions'
end

---Resolve gateway settings from explicit options, then the environment.
---An empty string counts as absent so `export FOO=` does not win over a fallback.
---@param opts? { base_url?: string, api_key?: string, timeout_ms?: integer }
---@param env? table
---@return { endpoint: string, api_key: string|nil, timeout_ms: integer }
function M.resolve(opts, env)
  opts = opts or {}
  env = env or vim.env
  local base = first_string(opts.base_url, env.MAGPIE_BASE_URL, env.ANTHROPIC_BASE_URL, DEFAULT_BASE)
  return {
    endpoint = endpoint_of(base),
    api_key = first_string(opts.api_key, env.MAGPIE_API_KEY, env.ANTHROPIC_AUTH_TOKEN),
    timeout_ms = opts.timeout_ms or DEFAULT_TIMEOUT_MS,
  }
end

---Resolve once, at setup. A later environment change needs another setup call.
---@param opts? table
function M.setup(opts)
  config = M.resolve(opts)
end

local function settings()
  if not config then
    config = M.resolve()
  end
  return config
end

local function choice_event(obj)
  local choice = type(obj.choices) == 'table' and obj.choices[1]
  if type(choice) ~= 'table' then
    return nil
  end

  local reason = choice.finish_reason
  if type(reason) == 'string' and reason ~= '' then
    return {
      event = 'finish',
      reason = reason,
      model = type(obj.model) == 'string' and obj.model or nil,
    }
  end

  local delta = choice.delta
  if type(delta) ~= 'table' then
    return nil
  end
  if type(delta.content) == 'string' and delta.content ~= '' then
    return { event = 'delta', text = delta.content }
  end
  if type(delta.reasoning_content) == 'string' and delta.reasoning_content ~= '' then
    return { event = 'reasoning' }
  end
  return nil
end

local function data_event(data)
  if data == '[DONE]' then
    return { event = 'finish', reason = 'stop' }
  end

  local ok, obj = pcall(vim.json.decode, data)
  if not ok or type(obj) ~= 'table' then
    return { event = 'invalid' }
  end
  if type(obj.error) == 'table' and type(obj.error.message) == 'string' then
    return { event = 'error', message = obj.error.message }
  end
  return choice_event(obj)
end

---Parse one complete SSE line into a domain event.
---JSON nulls decode to `vim.NIL`, so every field is checked by type, never truthiness.
---@param line string
---@return table|nil
function M.parse_line(line)
  if line == '' or line:sub(1, 1) == ':' then
    return nil
  end

  local data = line:match '^data:%s?(.*)$'
  if not data then
    return nil
  end
  return data_event(data)
end

---Split a chunk into complete SSE lines and their events.
---@param buffer string
---@param chunk string
---@return table[] events, string buffer, string[] lines
function M.feed(buffer, chunk)
  buffer = buffer .. chunk
  local events, lines = {}, {}
  while true do
    local newline = buffer:find('\n', 1, true)
    if not newline then
      break
    end
    local line = buffer:sub(1, newline - 1):gsub('\r$', '')
    buffer = buffer:sub(newline + 1)
    lines[#lines + 1] = line
    local event = M.parse_line(line)
    if event then
      events[#events + 1] = event
    end
  end
  return events, buffer, lines
end

---The HTTP status curl appends with `-w '\n%{http_code}'`.
---@param raw string
---@return integer|nil
function M.status_of(raw)
  local status
  for line in raw:gmatch '[^\n]+' do
    status = tonumber(line:match '^%s*(%d%d%d)%s*$') or status
  end
  return status
end

local function strip_status(raw)
  return (raw:gsub('%s*%d%d%d%s*$', ''))
end

---The message from an OpenAI-shaped error body, or the body itself.
---@param raw string
---@return string|nil
function M.error_message(raw)
  local body = strip_status(raw)
  local ok, obj = pcall(vim.json.decode, body)
  if ok and type(obj) == 'table' and type(obj.error) == 'table' and type(obj.error.message) == 'string' then
    return vim.trim(obj.error.message)
  end
  local trimmed = vim.trim(body)
  return trimmed ~= '' and trimmed:sub(1, 300) or nil
end

---A plain chat completion, for a gateway that ignores `stream = true`.
---@param raw string
---@return string|nil content, string|nil model, string|nil reason
function M.completion_of(raw)
  local ok, obj = pcall(vim.json.decode, strip_status(raw))
  if not ok or type(obj) ~= 'table' then
    return nil
  end
  local choice = type(obj.choices) == 'table' and obj.choices[1]
  local message = type(choice) == 'table' and choice.message
  if type(message) ~= 'table' or type(message.content) ~= 'string' then
    return nil
  end
  local content = vim.trim(message.content)
  return content ~= '' and content or nil, obj.model, choice.finish_reason
end

---Turn a finished process into a typed error, or nil when the process succeeded.
---Kinds are a closed set so callers write one branch per kind.
---@param result table vim.system result
---@param raw string
---@param stderr string|nil
---@return table|nil
function M.classify_exit(result, raw, stderr)
  local code = result.code
  -- 6, 7, 52: could not resolve, connect, or an empty reply. 28: curl timeout. 124: vim.system timeout.
  if code == 6 or code == 7 or code == 52 then
    return { kind = 'gateway_down' }
  end
  if code == 28 or code == 124 then
    return { kind = 'timeout' }
  end

  local status = M.status_of(raw)
  if status and status >= 400 then
    return { kind = 'http', status = status, detail = M.error_message(raw) }
  end
  if code ~= 0 then
    local detail = vim.trim(stderr or '')
    return { kind = 'transport', detail = detail ~= '' and detail or nil }
  end
  return nil
end

---Start a streaming chat request.
---@param request { model: string, messages: table[], temperature?: number, max_tokens?: integer }
---@param handlers { on_delta: fun(text: string), on_reasoning: fun()|nil, on_done: fun(text: string, meta: table), on_error: fun(err: table) }
---@return { cancel: fun() }
function M.stream(request, handlers)
  local cfg = settings()

  local payload = vim.json.encode {
    model = request.model,
    messages = request.messages,
    temperature = request.temperature or 0.2,
    max_tokens = request.max_tokens or DEFAULT_MAX_TOKENS,
    stream = true,
  }

  local argv = {
    'curl',
    '-sS',
    '-N',
    '--connect-timeout',
    '5',
    '--fail-with-body',
    '-H',
    'content-type: application/json',
    '-H',
    'accept: text/event-stream',
  }
  if cfg.api_key then
    vim.list_extend(argv, { '-H', 'authorization: Bearer ' .. cfg.api_key })
  end
  vim.list_extend(argv, { '-w', '\n%{http_code}', '--data-binary', '@-', cfg.endpoint })

  local cancelled, terminal_sent = false, false
  local line_buffer, raw, content = '', '', ''
  local reason, actual_model, inband_error = nil, nil, nil
  local reasoning_started = false

  local function emit(fn, ...)
    if not fn then
      return
    end
    local args = { n = select('#', ...), ... }
    vim.schedule(function()
      if cancelled then
        return
      end
      fn(unpack(args, 1, args.n))
    end)
  end

  local function terminal(fn, ...)
    if cancelled or terminal_sent then
      return
    end
    terminal_sent = true
    emit(fn, ...)
  end

  local function handle(event)
    if event.event == 'delta' then
      content = content .. event.text
      emit(handlers.on_delta, event.text)
    elseif event.event == 'finish' then
      reason = event.reason
      actual_model = event.model or actual_model
    elseif event.event == 'reasoning' then
      --[[ The first reasoning token is the one that tells the card to switch
      from "translating" to "thinking"; later tokens would only repaint it. ]]
      if not reasoning_started then
        reasoning_started = true
        emit(handlers.on_reasoning)
      end
    elseif event.event == 'error' then
      inband_error = event.message
    end
  end

  local function consume(chunk)
    local events, rest, lines = M.feed(line_buffer, chunk)
    line_buffer = rest
    for _, line in ipairs(lines) do
      raw = raw .. line .. '\n'
    end
    for _, event in ipairs(events) do
      handle(event)
    end
  end

  local started = vim.uv.now()
  local function on_exit(result)
    if cancelled then
      return
    end
    if line_buffer ~= '' then
      consume '\n'
      line_buffer = ''
    end
    if terminal_sent then
      return
    end

    if inband_error then
      terminal(handlers.on_error, { kind = 'transport', detail = inband_error })
      return
    end

    local err = M.classify_exit(result, raw, result.stderr)
    if err then
      terminal(handlers.on_error, err)
      return
    end

    if content == '' then
      local completed, model, finish = M.completion_of(raw)
      if completed then
        content = completed
        actual_model = actual_model or model
        reason = reason or finish
      end
    end
    if content == '' then
      terminal(handlers.on_error, { kind = 'empty' })
      return
    end

    terminal(handlers.on_done, content, {
      model = actual_model or request.model,
      elapsed_ms = vim.uv.now() - started,
      truncated = reason == 'length',
    })
  end

  local ok, process = pcall(vim.system, argv, {
    stdin = payload,
    text = true,
    timeout = cfg.timeout_ms,
    stdout = function(_, data)
      if data and data ~= '' then
        consume(data)
      end
    end,
  }, on_exit)

  if not ok then
    terminal(handlers.on_error, { kind = 'transport', detail = tostring(process) })
    return { cancel = function() end }
  end

  return {
    cancel = function()
      if cancelled then
        return
      end
      cancelled = true
      pcall(process.kill, process, 15)
    end,
  }
end

return M
