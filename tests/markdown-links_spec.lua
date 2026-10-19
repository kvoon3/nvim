-- Headless mini.test spec for lua/markdown-links.lua.
-- Run all specs with: just test

local expect = require('mini.test').expect
local links = require 'markdown-links'

describe('markdown-links', function()
  describe('link_at', function()
    it('finds inline links from label through destination', function()
      local line = 'See [notes](notes/a.md#hello-world "Title") now.'
      local label_col = line:find('notes', 1, true) - 1
      local link = links.link_at(line, label_col)
      expect.equality('notes/a.md#hello-world', link.target)
      expect.equality('link', link.kind)

      local target_col = line:find('a.md', 1, true) - 1
      expect.equality('notes/a.md#hello-world', links.link_at(line, target_col).target)
    end)

    it('ignores the cursor outside the link', function()
      local line = 'See [notes](notes/a.md) now.'
      expect.equality(nil, links.link_at(line, 0))
      expect.equality(nil, links.link_at(line, #line - 1))
    end)

    it('recognizes images and autolinks', function()
      local image = '![alt](img/pic.png)'
      local image_link = links.link_at(image, 2)
      expect.equality('image', image_link.kind)
      expect.equality('img/pic.png', image_link.target)

      local autolink = '<https://example.com/a#b>'
      local url_link = links.link_at(autolink, 4)
      expect.equality('url', url_link.kind)
      expect.equality('https://example.com/a#b', url_link.target)
    end)

    it('recognizes wiki links with aliases and headings', function()
      local line = 'See [[Note Name#Heading|alias]] now.'
      local link = links.link_at(line, line:find('Note', 1, true) - 1)
      expect.equality('Note Name#Heading', link.target)
      expect.equality(true, link.wiki)
      expect.equality(nil, links.link_at(line, #line - 1))
    end)

    it('resolves reference definitions and reference links', function()
      local line = '[label][ref] and [ref]'
      local refs = { ref = '../target.md' }
      expect.equality('../target.md', links.link_at(line, 2, refs).target)
      expect.equality('../target.md', links.link_at(line, line:find '%[ref%]$' - 1, refs).target)
    end)

    it('uses the definition line target', function()
      local line = '  [ref]: <my notes/target.md> "Title"'
      local link = links.link_at(line, 12)
      expect.equality('my notes/target.md', link.target)
      expect.equality('reference', link.kind)
      expect.equality(nil, links.link_at('prose [ref]: target', 10))
    end)
  end)

  describe('parse_target', function()
    it('splits paths and anchors and decodes percent escapes', function()
      local path, anchor = links.parse_target 'notes/My%20Note.md#Hello%20World'
      expect.equality('notes/My Note.md', path)
      expect.equality('Hello World', anchor)
    end)

    it('handles anchors without a path and angle brackets', function()
      local path, anchor = links.parse_target '#local-heading'
      expect.equality('', path)
      expect.equality('local-heading', anchor)
      expect.equality('notes/a.md', (links.parse_target '<notes/a.md>'))
    end)
  end)

  describe('reference_targets', function()
    it('collects definitions case-insensitively', function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        '[Foo Bar]: notes/foo.md',
        '[other]: <notes/other.md>',
      })
      local refs = links.reference_targets(bufnr)
      expect.equality('notes/foo.md', refs['foo bar'])
      expect.equality('notes/other.md', refs.other)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe('resolve_path', function()
    it('resolves relative markdown links and extensionless targets', function()
      local dir = vim.fn.tempname()
      vim.fn.mkdir(dir .. '/notes', 'p')
      vim.fn.writefile({ '# Note' }, dir .. '/notes/a.md')
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(bufnr, dir .. '/README.md')
      local expected = vim.fs.normalize(vim.fs.joinpath(links.buffer_dir(bufnr), 'notes/a.md'))

      expect.equality(expected, links.resolve_path('notes/a.md', bufnr))
      expect.equality(expected, links.resolve_path('notes/a', bufnr))

      vim.fn.mkdir(dir .. '/docs', 'p')
      expect.equality(
        vim.fs.normalize(vim.fs.joinpath(links.buffer_dir(bufnr), 'docs')),
        links.resolve_path('docs', bufnr)
      )

      vim.api.nvim_buf_delete(bufnr, { force = true })
      vim.fn.delete(dir, 'rf')
    end)
  end)

  describe('jump_to_anchor', function()
    it('matches slugged headings and block ids', function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '# Top', '## Hello, World!', 'text ^block1' })

      expect.equality(true, links.jump_to_anchor 'hello-world')
      expect.equality(2, vim.api.nvim_win_get_cursor(0)[1])
      expect.equality(true, links.jump_to_anchor '^block1')
      expect.equality(3, vim.api.nvim_win_get_cursor(0)[1])

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe('slug', function()
    it('matches GitHub-style anchors and keeps unicode', function()
      expect.equality('hello-world', links.slug 'Hello, World!')
      expect.equality('hello-world', links.slug '**Hello** World')
      expect.equality('中文-标题', links.slug '中文 标题')
    end)
  end)
end)
