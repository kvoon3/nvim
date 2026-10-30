-- Headless mini.test spec for lua/magpie.lua.
-- Run all specs with: just test

local expect = require('mini.test').expect
local magpie = require 'magpie'

describe('magpie', function()
  describe('resolve', function()
    it('prefers options over the environment over the default', function()
      local resolved = magpie.resolve(
        { base_url = 'http://opts:1', api_key = 'opts-key', timeout_ms = 1000 },
        { MAGPIE_BASE_URL = 'http://env:2', ANTHROPIC_BASE_URL = 'http://anthropic:3', MAGPIE_API_KEY = 'env-key' }
      )
      expect.equality('http://opts:1/v1/chat/completions', resolved.endpoint)
      expect.equality('opts-key', resolved.api_key)
      expect.equality(1000, resolved.timeout_ms)
    end)

    it('falls back through MAGPIE then ANTHROPIC then the default', function()
      expect.equality(
        'http://env:2/v1/chat/completions',
        magpie.resolve(nil, { MAGPIE_BASE_URL = 'http://env:2' }).endpoint
      )
      expect.equality(
        'http://anthropic:3/v1/chat/completions',
        magpie.resolve(nil, { ANTHROPIC_BASE_URL = 'http://anthropic:3' }).endpoint
      )
      expect.equality('http://127.0.0.1:3425/v1/chat/completions', magpie.resolve(nil, {}).endpoint)
      expect.equality('env-key', magpie.resolve(nil, { MAGPIE_API_KEY = 'env-key' }).api_key)
      expect.equality('anthropic-key', magpie.resolve(nil, { ANTHROPIC_AUTH_TOKEN = 'anthropic-key' }).api_key)
      expect.equality(nil, magpie.resolve(nil, {}).api_key)
    end)

    it('treats empty strings as absent', function()
      local resolved = magpie.resolve({ api_key = '' }, { MAGPIE_BASE_URL = '', ANTHROPIC_BASE_URL = '' })
      expect.equality('http://127.0.0.1:3425/v1/chat/completions', resolved.endpoint)
      expect.equality(nil, resolved.api_key)
    end)

    it('normalizes every accepted base form', function()
      local function endpoint(base)
        return magpie.resolve({ base_url = base }, {}).endpoint
      end
      expect.equality('http://h:1/v1/chat/completions', endpoint 'http://h:1')
      expect.equality('http://h:1/v1/chat/completions', endpoint 'http://h:1/')
      expect.equality('http://h:1/v1/chat/completions', endpoint 'http://h:1/v1')
      expect.equality('http://h:1/v1/chat/completions', endpoint 'http://h:1/v1/')
      expect.equality('http://h:1/v1/chat/completions', endpoint 'http://h:1/v1/chat/completions')
      expect.equality('https://h:1/relay/v1/chat/completions', endpoint 'https://h:1/relay')
    end)

    it('defaults the timeout', function()
      expect.equality(45000, magpie.resolve(nil, {}).timeout_ms)
    end)
  end)

  describe('parse_line', function()
    local function parse(line)
      return magpie.parse_line(line)
    end

    it('reads content deltas', function()
      expect.equality(
        { event = 'delta', text = 'Hello' },
        parse 'data: {"choices":[{"delta":{"content":"Hello"},"finish_reason":null}]}'
      )
    end)

    it('ignores reasoning content but reports it', function()
      expect.equality({ event = 'reasoning' }, parse 'data: {"choices":[{"delta":{"reasoning_content":"Think"}}]}')
    end)

    it('reads a finish reason and the model that answered', function()
      expect.equality(
        { event = 'finish', reason = 'length', model = 'deepseek-v4-pro' },
        parse 'data: {"model":"deepseek-v4-pro","choices":[{"delta":{},"finish_reason":"length"}]}'
      )
    end)

    it('reads [DONE]', function()
      expect.equality({ event = 'finish', reason = 'stop' }, parse 'data: [DONE]')
    end)

    it('reads an in-band error', function()
      expect.equality({ event = 'error', message = 'boom' }, parse 'data: {"error":{"message":"boom"}}')
    end)

    it('ignores heartbeats, comments, empty lines and the status trailer', function()
      expect.equality(nil, parse ': heartbeat')
      expect.equality(nil, parse '')
      expect.equality(nil, parse '200')
      expect.equality(nil, parse 'data: {"choices":[]}')
      expect.equality(nil, parse 'data: {"choices":[{"delta":{},"finish_reason":null}]}')
    end)

    it('marks malformed JSON instead of throwing', function()
      expect.equality({ event = 'invalid' }, parse 'data: {not json')
      expect.equality({ event = 'invalid' }, parse 'data: null')
    end)

    it('accepts data: without a space', function()
      expect.equality({ event = 'delta', text = 'Hi' }, parse 'data:{"choices":[{"delta":{"content":"Hi"}}]}')
    end)
  end)

  describe('feed', function()
    it('returns only complete lines and keeps the remainder', function()
      local events, rest = magpie.feed('', 'data: {"choices":[{"delta":{"content":"Hel')
      expect.equality({}, events)
      expect.equality('data: {"choices":[{"delta":{"content":"Hel', rest)

      local more, final = magpie.feed(rest, 'lo"}}]}\n')
      expect.equality({ { event = 'delta', text = 'Hello' } }, more)
      expect.equality('', final)
    end)

    it('reads multiple lines from one chunk, including CRLF', function()
      local chunk =
        'data: {"choices":[{"delta":{"content":"a"}}]}\r\n: heartbeat\ndata: {"choices":[{"delta":{"content":"b"}}]}\n'
      local events, rest, lines = magpie.feed('', chunk)
      expect.equality({ { event = 'delta', text = 'a' }, { event = 'delta', text = 'b' } }, events)
      expect.equality('', rest)
      expect.equality(3, #lines)
      expect.equality(': heartbeat', lines[2])
    end)

    it('keeps the raw line list for status and error parsing', function()
      local _, _, lines = magpie.feed('', '{"error":{"message":"nope"}}\n404\n')
      expect.equality({ '{"error":{"message":"nope"}}', '404' }, lines)
    end)

    it('handles an empty chunk', function()
      local events, rest, lines = magpie.feed('partial', '')
      expect.equality({}, events)
      expect.equality('partial', rest)
      expect.equality({}, lines)
    end)
  end)

  describe('status_of', function()
    it('reads the last status line curl appended', function()
      expect.equality(200, magpie.status_of 'data: {}\n200\n')
      expect.equality(500, magpie.status_of '{"error":{"message":"x"}}\n500\n')
    end)

    it('returns nil when there is no status', function()
      expect.equality(nil, magpie.status_of 'data: {}\n')
      expect.equality(nil, magpie.status_of '')
    end)
  end)

  describe('error_message', function()
    it('reads an OpenAI error body and ignores the status trailer', function()
      expect.equality('model not found', magpie.error_message '{"error":{"message":"model not found"}}\n404\n')
    end)

    it('returns a plain body excerpt', function()
      expect.equality('upstream unavailable', magpie.error_message 'upstream unavailable\n502\n')
    end)

    it('returns nil for an empty body', function()
      expect.equality(nil, magpie.error_message '\n500\n')
    end)
  end)

  describe('completion_of', function()
    it('reads a non-streaming completion body', function()
      expect.equality(
        'Hello',
        (magpie.completion_of '{"model":"m","choices":[{"message":{"content":"Hello"},"finish_reason":"stop"}]}\n200\n')
      )
    end)

    it('returns nil for a body without a message', function()
      expect.equality(nil, (magpie.completion_of '{"choices":[]}\n200\n'))
    end)
  end)

  describe('classify_exit', function()
    local function classify(code, raw, stderr)
      return magpie.classify_exit({ code = code }, raw or '', stderr)
    end

    it('classifies unreachable gateways', function()
      expect.equality({ kind = 'gateway_down' }, classify(7))
      expect.equality({ kind = 'gateway_down' }, classify(52))
    end)

    it('classifies timeouts from curl and vim.system', function()
      expect.equality({ kind = 'timeout' }, classify(28))
      expect.equality({ kind = 'timeout' }, classify(124))
    end)

    it('classifies HTTP errors with the status and body message', function()
      expect.equality(
        { kind = 'http', status = 404, detail = 'model not found' },
        classify(22, '{"error":{"message":"model not found"}}\n404\n')
      )
    end)

    it('classifies other nonzero exits as transport errors', function()
      expect.equality({ kind = 'transport', detail = 'boom' }, classify(3, '', 'boom'))
    end)

    it('returns nil on a clean exit', function()
      expect.equality(nil, classify(0, 'data: {}\n200\n'))
    end)
  end)
end)
