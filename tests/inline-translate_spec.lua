-- Headless mini.test spec for lua/inline-translate.lua.
-- Run all specs with: just test

local expect = require('mini.test').expect
local translate = require 'inline-translate'

describe('inline-translate', function()
  describe('split_blocks', function()
    local doc = {
      '---',
      'title: notes',
      '---',
      '',
      '# Heading',
      '',
      'First paragraph line one',
      'continues here.',
      '',
      '- item one',
      '- item two',
      '',
      '```lua',
      'local x = 1',
      '```',
      '',
      '| a | b |',
      '| - | - |',
      '',
      '> quoted text',
      '> continues',
      '',
      '[ref]: https://example.com',
      '',
      'Last.',
    }

    it('skips frontmatter, code, tables and link definitions', function()
      local blocks = translate.split_blocks(doc, 'markdown')
      local texts = vim.tbl_map(function(block)
        return block.text
      end, blocks)
      expect.equality({
        'Heading',
        'First paragraph line one continues here.',
        'item one',
        'item two',
        'quoted text continues',
        'Last.',
      }, texts)
    end)

    it('returns 0-indexed inclusive line ranges', function()
      local blocks = translate.split_blocks(doc, 'markdown')
      expect.equality(4, blocks[1].s)
      expect.equality(4, blocks[1].e)
      expect.equality(6, blocks[2].s)
      expect.equality(7, blocks[2].e)
    end)

    it('keeps list continuation lines in the item block', function()
      local blocks = translate.split_blocks({ '- an item that', '  wraps' }, 'markdown')
      expect.equality(1, #blocks)
      expect.equality('an item that wraps', blocks[1].text)
    end)

    it('keeps link labels and image alt text without their targets', function()
      local blocks =
        translate.split_blocks({ 'See [the docs](https://example.com/a) and ![diagram](x.png).' }, 'markdown')
      expect.equality('See the docs and diagram.', blocks[1].text)
    end)

    it('treats a lone rule line as a skipped setext underline', function()
      local blocks = translate.split_blocks({ 'Setext title', '---', '', 'Body.' }, 'markdown')
      expect.equality(2, #blocks)
      expect.equality('Setext title', blocks[1].text)
      expect.equality('Body.', blocks[2].text)
    end)
  end)

  describe('translatable', function()
    it('accepts English prose', function()
      expect.equality(true, translate.translatable 'The quick brown fox jumps over the lazy dog.')
    end)

    it('accepts a lone English word', function()
      expect.equality(true, translate.translatable 'Serendipity')
    end)

    it('rejects paragraphs that are already Chinese', function()
      expect.equality(false, translate.translatable '这是一段已经翻译好的中文，不需要再次翻译。')
    end)

    it('rejects URLs, paths and bare identifiers', function()
      expect.equality(false, translate.translatable 'https://example.com/docs')
      expect.equality(false, translate.translatable 'lua/config/lsp.lua')
      expect.equality(false, translate.translatable 'inline_translate')
    end)

    it('rejects empty, punctuation-only and oversized blocks', function()
      expect.equality(false, translate.translatable '   ')
      expect.equality(false, translate.translatable '--- ... ---')
      expect.equality(false, translate.translatable(string.rep('a ', 4000)))
    end)
  end)

  describe('wrap', function()
    it('breaks at word boundaries', function()
      expect.equality({ 'hello', 'world' }, translate.wrap('hello world', 10))
      expect.equality({ 'hello world' }, translate.wrap('hello world', 11))
    end)

    it('counts CJK characters as two cells', function()
      local lines = translate.wrap(string.rep('中', 10), 10)
      expect.equality({ '中中中中中', '中中中中中' }, lines)
    end)

    it('hard-breaks tokens wider than the window', function()
      local lines = translate.wrap('supercalifragilistic', 10)
      for _, line in ipairs(lines) do
        expect.equality(true, vim.fn.strdisplaywidth(line) <= 10)
      end
    end)

    it('never exceeds the requested display width', function()
      local text =
        'Serialize the request body, stream the response, and coalesce chunks that arrive faster than the render loop.'
      for _, width in ipairs { 10, 20, 33, 80 } do
        for _, line in ipairs(translate.wrap(text, width)) do
          expect.equality(true, vim.fn.strdisplaywidth(line) <= width)
        end
      end
    end)
  end)

  describe('extract_completion', function()
    local function completion(content)
      return vim.json.encode {
        choices = { { message = { content = content } } },
      }
    end

    it('reads the assistant message', function()
      expect.equality('你好', translate.extract_completion(completion '你好'))
    end)

    it('strips code fences and wrapping quotes', function()
      expect.equality('你好', translate.extract_completion(completion '```text\n你好\n```'))
      expect.equality('你好', translate.extract_completion(completion '"你好"'))
    end)

    it('flattens newlines and rejects empty answers', function()
      expect.equality('第一行 第二行', translate.extract_completion(completion '第一行\n第二行'))
      expect.equality(nil, translate.extract_completion(completion '  '))
    end)

    it('returns nil for malformed payloads', function()
      expect.equality(nil, translate.extract_completion 'not json')
      expect.equality(nil, translate.extract_completion '{"choices":[]}')
    end)
  end)
end)
