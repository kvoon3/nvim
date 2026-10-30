-- Headless mini.test spec for lua/selection-translate.lua.
-- Run all specs with: just test

local expect = require('mini.test').expect

package.loaded.cmdr = { add = function() end }
local translate = require 'selection-translate'

local function card_buffer()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype == 'translate-card' then
      return buf
    end
  end
end

local function card_text()
  local buf = card_buffer()
  return buf and table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n') or nil
end

local function card_win()
  local buf = card_buffer()
  if not buf then
    return nil
  end
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == buf then
      return win
    end
  end
end

local function footer_text()
  local win = card_win()
  if not win then
    return nil
  end
  local chunks = vim.api.nvim_win_get_config(win).footer or {}
  local parts = {}
  for _, chunk in ipairs(chunks) do
    parts[#parts + 1] = chunk[1]
  end
  return table.concat(parts, '')
end

local function row_with(rows, needle)
  for _, row in ipairs(rows) do
    if row.text:find(needle, 1, true) then
      return row
    end
  end
end

local function snapshot(overrides)
  return vim.tbl_deep_extend('force', {
    phase = 'pending',
    source = 'Bonjour le monde',
    text = '',
    error = nil,
    error_text = nil,
    model = 'remote-magpie/auto/deepseek-v4-pro',
    elapsed_ms = nil,
    truncated = false,
    thinking = false,
  }, overrides)
end

local function fake_client()
  local fake = { calls = {}, handlers = {}, canceled = 0 }
  function fake.stream(request, handlers)
    fake.calls[#fake.calls + 1] = request
    fake.handlers = handlers
    return {
      cancel = function()
        fake.canceled = fake.canceled + 1
      end,
    }
  end
  return fake
end

local function select_line(buf, text)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { text })
  vim.api.nvim_buf_set_mark(buf, '<', 1, 0, {})
  vim.api.nvim_buf_set_mark(buf, '>', 1, #text, {})
end

describe('selection-translate', function()
  describe('build_prompt', function()
    it('asks for Chinese and preserves identifiers', function()
      local messages = translate.build_prompt('When calling `foo()`, the id must not conflict.', 'lua')
      expect.equality('system', messages[1].role)
      expect.equality(true, messages[1].content:find('Chinese', 1, true) ~= nil)
      expect.equality(true, messages[1].content:find('identifiers', 1, true) ~= nil)
      expect.equality(true, messages[1].content:find('lua buffer', 1, true) ~= nil)
      expect.equality({ role = 'user', content = 'When calling `foo()`, the id must not conflict.' }, messages[2])
    end)

    it('omits the filetype sentence for an empty filetype', function()
      local messages = translate.build_prompt('hello', '')
      expect.equality(nil, messages[1].content:find('buffer', 1, true))
    end)
  end)

  describe('normalize', function()
    it('strips fences and one wrapping quote pair', function()
      expect.equality('Hello', translate.normalize '```text\nHello\n```')
      expect.equality('Hello', translate.normalize '"Hello"')
    end)

    it('keeps internal newlines and trims blank edges', function()
      expect.equality('one\ntwo', translate.normalize '\n one\ntwo \n')
    end)

    it('returns an empty string for blank input', function()
      expect.equality('', translate.normalize '   ')
    end)
  end)

  describe('partial', function()
    it('reveals whole UTF-8 characters', function()
      expect.equality('', translate.partial('中文', 0))
      expect.equality('中', translate.partial('中文', 1))
      expect.equality('中文', translate.partial('中文', 2))
      expect.equality('中文', translate.partial('中文', 99))
      expect.equality('a', translate.partial('ab', 1))
      expect.equality('ab', translate.partial('ab', 2))
    end)
  end)

  describe('endpoint_label', function()
    it('keeps the host and port', function()
      expect.equality('127.0.0.1:3425', translate.endpoint_label 'http://127.0.0.1:3425/v1/chat/completions')
      expect.equality('gw.example', translate.endpoint_label 'https://gw.example')
    end)
  end)

  describe('error_text', function()
    it('names the unreachable gateway and the retry key', function()
      local text = translate.error_text({ kind = 'gateway_down' }, '127.0.0.1:3425')
      expect.equality(true, text:find('not reachable at 127.0.0.1:3425', 1, true) ~= nil)
      expect.equality(true, text:find('press r to retry', 1, true) ~= nil)
    end)

    it('includes the HTTP status and detail', function()
      local text = translate.error_text({ kind = 'http', status = 404, detail = 'no model' }, nil)
      expect.equality('Magpie returned HTTP 404: no model', text)
    end)

    it('has a fallback for an unknown kind', function()
      expect.equality('The request to Magpie failed. Press r to retry.', translate.error_text({ kind = 'other' }, nil))
    end)
  end)

  describe('status_text and footer_text', function()
    it('shows translating, done and error states', function()
      expect.equality('translating · deepseek-v4-pro', translate.status_text(snapshot { phase = 'streaming' }))
      expect.equality(
        'done · 1.2s · deepseek-v4-pro',
        translate.status_text(snapshot { phase = 'done', elapsed_ms = 1200 })
      )
      expect.equality(
        'error · gateway down',
        translate.status_text(snapshot { phase = 'error', error = { kind = 'gateway_down' } })
      )
      expect.equality(
        'error · HTTP 404',
        translate.status_text(snapshot { phase = 'error', error = { kind = 'http', status = 404 } })
      )
    end)

    it('shows the thinking state with a spinner and elapsed time', function()
      local text = translate.footer_text(snapshot { phase = 'pending', thinking = true }, 1400, '⠹')
      expect.equality(true, text:find('⠹ thinking · 1.4s', 1, true) ~= nil)
      expect.equality(true, text:find('q close', 1, true) ~= nil)
    end)

    it('advertises only the keys that work in that phase', function()
      expect.equality(true, translate.footer_text(snapshot {}):find('q close', 1, true) ~= nil)
      expect.equality(true, translate.footer_text(snapshot {}):find('y copy', 1, true) == nil)
      expect.equality(true, translate.footer_text(snapshot { phase = 'done' }):find('y copy', 1, true) ~= nil)
      expect.equality(
        true,
        translate.footer_text(snapshot { phase = 'error', error = { kind = 'timeout' } }):find('r retry', 1, true)
          ~= nil
      )
    end)
  end)

  describe('card_lines', function()
    it('renders the source, a rule and a pending row', function()
      local rows, measure = translate.card_lines(snapshot {}, 76)
      expect.equality(70, measure)
      expect.equality('TranslateCardSource', row_with(rows, 'Bonjour').group)
      expect.equality('TranslateCardRule', row_with(rows, '──────').group)
      expect.equality('TranslateCardPending', row_with(rows, 'Translating').group)
      expect.equality(nil, row_with(rows, 'q close'))
    end)

    it('switches the pending row to Thinking while the model reasons', function()
      local rows = translate.card_lines(snapshot { phase = 'pending', thinking = true }, 76)
      expect.equality('TranslateCardPending', row_with(rows, 'Thinking…').group)
    end)

    it('renders the translation with an accent bar', function()
      local rows = translate.card_lines(snapshot { phase = 'done', text = 'Hello world', elapsed_ms = 1000 }, 76)
      local row = row_with(rows, 'Hello world')
      expect.equality('TranslateCardText', row.group)
      expect.equality('TranslateCardTranslationBar', row.bar.group)
      expect.equality('  ▍ Hello world', row.text)
    end)

    it('wraps every row inside the window', function()
      local text = string.rep('A sentence that wraps across the measure. ', 12) .. string.rep('中文', 40)
      local rows = translate.card_lines(snapshot { phase = 'done', text = text, source = text }, 68)
      for _, row in ipairs(rows) do
        expect.equality(true, vim.fn.strdisplaywidth(row.text) <= 66)
      end
    end)

    it('caps the source preview and reports the rest', function()
      local source = table.concat(
        vim.tbl_map(function(i)
          return 'line ' .. i
        end, vim.fn.range(1, 30)),
        '\n'
      )
      local rows = translate.card_lines(snapshot { source = source }, 76)
      local source_rows = #vim.tbl_filter(function(row)
        return row.bar ~= nil and row.group == 'TranslateCardSource'
      end, rows)
      expect.equality(4, source_rows)
      expect.equality(true, row_with(rows, 'more lines') ~= nil)
    end)

    it('keeps a partial translation above an error', function()
      local rows = translate.card_lines(
        snapshot {
          phase = 'error',
          text = 'Partial answer',
          error = { kind = 'timeout' },
          error_text = 'Magpie did not answer in time.',
        },
        76
      )
      expect.equality('TranslateCardText', row_with(rows, 'Partial answer').group)
      expect.equality('DiagnosticError', row_with(rows, 'did not answer').group)
    end)
  end)

  describe('lifecycle', function()
    local fake

    before_each(function()
      fake = fake_client()
      translate.setup { client = fake }
      vim.cmd 'normal! \27'
      vim.cmd 'silent! delmarks <>'
    end)

    after_each(function()
      translate.close()
      vim.cmd 'normal! \27'
    end)

    it('captures the last visual selection and streams into the card', function()
      local source_buf = vim.api.nvim_get_current_buf()
      select_line(source_buf, 'Bonjour le monde')
      translate.translate_selection()

      expect.equality(1, #fake.calls)
      expect.equality({ role = 'user', content = 'Bonjour le monde' }, fake.calls[1].messages[2])
      expect.equality(true, card_text():find('Translating', 1, true) ~= nil)

      fake.handlers.on_delta 'Hello'
      vim.wait(200, function()
        return card_text():find('Hello', 1, true) ~= nil
      end, 10)
      expect.equality(true, card_text():find('Hello', 1, true) ~= nil)

      fake.handlers.on_done('Hello', { model = 'deepseek-v4-pro', elapsed_ms = 1200 })
      expect.equality(true, card_text():find('Hello', 1, true) ~= nil)
      expect.equality(true, footer_text():find('done · 1.2s', 1, true) ~= nil)
      expect.equality(true, footer_text():find('y copy', 1, true) ~= nil)
    end)

    it('shows live thinking feedback before content arrives', function()
      select_line(vim.api.nvim_get_current_buf(), 'Bonjour')
      translate.translate_selection()
      fake.handlers.on_reasoning()
      vim.wait(300, function()
        local text = footer_text()
        return text ~= nil and text:find('thinking', 1, true) ~= nil
      end, 20)
      expect.equality(true, footer_text():find('thinking', 1, true) ~= nil)
    end)

    it('captures a live visual selection', function()
      local buf = vim.api.nvim_get_current_buf()
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'alpha beta gamma' })
      vim.api.nvim_win_set_cursor(0, { 1, 6 })
      vim.cmd 'normal! v'
      vim.api.nvim_win_set_cursor(0, { 1, 9 })
      translate.translate_selection()
      expect.equality('beta', fake.calls[1].messages[2].content)
    end)

    it('types the translation out instead of revealing the whole chunk', function()
      select_line(vim.api.nvim_get_current_buf(), 'Bonjour')
      translate.translate_selection()
      fake.handlers.on_delta 'Hello world'
      expect.equality(nil, card_text():find('Hello world', 1, true))
      local ok = vim.wait(800, function()
        return card_text():find('Hello world', 1, true) ~= nil
      end, 20)
      expect.equality(true, ok)
    end)

    it('opens a visible and focused card', function()
      select_line(vim.api.nvim_get_current_buf(), 'Bonjour')
      translate.translate_selection()
      local win = card_win()
      expect.equality(true, win ~= nil)
      expect.equality(true, vim.api.nvim_win_get_config(win).hide ~= true)
      expect.equality(win, vim.api.nvim_get_current_win())
    end)

    it('closes the window, the buffer and the stream', function()
      select_line(vim.api.nvim_get_current_buf(), 'Bonjour')
      translate.translate_selection()
      local win = card_win()
      expect.equality(true, win ~= nil)

      translate.close()
      expect.equality(nil, card_buffer())
      expect.equality(true, fake.canceled >= 1)
      expect.equality(false, vim.api.nvim_win_is_valid(win))
    end)

    it('shows a readable error and keeps the partial text', function()
      select_line(vim.api.nvim_get_current_buf(), 'Bonjour')
      translate.translate_selection()
      fake.handlers.on_delta 'Part'
      vim.wait(200, function()
        return card_text():find('Part', 1, true) ~= nil
      end, 10)
      fake.handlers.on_error { kind = 'gateway_down' }

      expect.equality(true, card_text():find('Part', 1, true) ~= nil)
      expect.equality(true, card_text():find('not reachable', 1, true) ~= nil)
      expect.equality(true, footer_text():find('r retry', 1, true) ~= nil)
    end)

    it('retries the same source after an error', function()
      select_line(vim.api.nvim_get_current_buf(), 'Bonjour')
      translate.translate_selection()
      fake.handlers.on_error { kind = 'timeout' }

      translate.retry()
      expect.equality(2, #fake.calls)
      expect.equality('Bonjour', fake.calls[2].messages[2].content)
      expect.equality(true, card_text():find('Translating', 1, true) ~= nil)
    end)

    it('does nothing without a selection', function()
      vim.api.nvim_buf_set_lines(vim.api.nvim_get_current_buf(), 0, -1, false, { 'no selection' })
      vim.cmd 'silent! delmarks <>'
      translate.translate_selection()
      expect.equality(nil, card_buffer())
      expect.equality(0, #fake.calls)
    end)

    it('replaces an open card instead of stacking a second one', function()
      local source_buf = vim.api.nvim_get_current_buf()
      local source_win = vim.api.nvim_get_current_win()
      select_line(source_buf, 'First')
      translate.translate_selection()
      local first = card_win()

      vim.api.nvim_set_current_win(source_win)
      select_line(source_buf, 'Second')
      translate.translate_selection()
      expect.equality(false, vim.api.nvim_win_is_valid(first))
      expect.equality(2, #fake.calls)
      expect.equality(true, card_text():find('Second', 1, true) ~= nil)
    end)
  end)
end)
