local expect = require('mini.test').expect

describe('eslint-codemod', function()
  local config
  local commands
  local trigger
  local completion

  before_each(function()
    -- Fresh module state per test
    package.loaded['eslint-codemod.config'] = nil
    package.loaded['eslint-codemod.commands'] = nil
    package.loaded['eslint-codemod.trigger'] = nil
    package.loaded['eslint-codemod.completion'] = nil
    package.loaded['eslint-codemod.lint'] = nil
    package.loaded['eslint-codemod.docs'] = nil

    config = require 'eslint-codemod.config'
    commands = require 'eslint-codemod.commands'
    trigger = require 'eslint-codemod.trigger'
    completion = require 'eslint-codemod.completion'

    config.reset()
    -- Disable onlyFixable async lint gate by default for pure completion tests
    config.setup { autocomplete = { onlyFixable = false } }
  end)

  after_each(function()
    config.reset()
  end)

  describe('config', function()
    it('exposes defaults matching vscode extension', function()
      local defaults = config.defaults()
      expect.equality(true, defaults.enable)
      expect.equality({ '*' }, defaults.languageIds)
      expect.equality(true, defaults.autocomplete.autoFix)
      expect.equality(false, defaults.autocomplete.docs)
      expect.equality(true, defaults.autocomplete.diff)
      expect.equality(true, defaults.autocomplete.onlyFixable)
      expect.equality({ 'hreg' }, defaults.alias['hoist-regexp'])
      expect.equality({ '2a' }, defaults.alias['to-arrow'])
      expect.equality({ '23' }, defaults.alias['to-ternary'])
    end)

    it('toggles enable and language filter', function()
      expect.equality(true, config.is_language_enabled 'typescript')
      config.setup { languageIds = { 'lua' } }
      expect.equality(false, config.is_language_enabled 'typescript')
      expect.equality(true, config.is_language_enabled 'lua')
    end)

    it('merges alias overrides and normalizes string values', function()
      config.setup { alias = { ['to-ternary'] = '3', ['new-cmd'] = { 'nc' } } }
      local cfg = config.get()
      expect.equality({ '3' }, cfg.alias['to-ternary'])
      expect.equality({ 'nc' }, cfg.alias['new-cmd'])
    end)
  end)

  describe('commands', function()
    it('contains 21 builtin commands with commentType defaults', function()
      local all = commands.get_all()
      expect.equality(21, #all)
      local keep_sorted = commands.find 'keep-sorted'
      assert(keep_sorted, 'keep-sorted should exist')
      expect.equality('both', keep_sorted.commentType)
      local to_ternary = commands.find 'to-ternary'
      assert(to_ternary, 'to-ternary should exist')
      expect.equality('line', to_ternary.commentType)
    end)
  end)

  describe('trigger pure helpers', function()
    it('detects line comment prefix', function()
      expect.equality(true, trigger.is_inside_line_comment_str('  // hello', '//'))
      expect.equality(true, trigger.is_inside_line_comment_str('/// to-ternary', '///'))
      expect.equality(false, trigger.is_inside_line_comment_str('let x = 1 //', '///'))
      -- Even number of quotes -> heuristic treats it as inside a comment
      expect.equality(true, trigger.is_inside_line_comment_str('" // not a comment"', '//'))
      -- Odd number of quotes -> treated as an unclosed string literal
      expect.equality(false, trigger.is_inside_line_comment_str('"odd // quote', '//'))
    end)

    it('detects block comment state via open/close counting', function()
      expect.equality(true, trigger.is_inside_block_comment_str '/* @')
      expect.equality(false, trigger.is_inside_block_comment_str '/* hello */ @')
      expect.equality(true, trigger.is_inside_block_comment_str '/** @keep-sorted')
      expect.equality(false, trigger.is_inside_block_comment_str 'code /* comment */ more')
      expect.equality(true, trigger.is_inside_block_comment_str '/* outer /* inner @')
    end)

    it('exposes distinct triggerChars', function()
      local chars = trigger.trigger_chars()
      table.sort(chars)
      expect.equality({ '/', ':', '@' }, chars)
    end)
  end)

  describe('trigger with buffer', function()
    local bufnr
    before_each(function()
      bufnr = vim.api.nvim_create_buf(false, true)
      vim.bo[bufnr].filetype = 'typescript'
    end)
    after_each(function()
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end)

    it('recognizes /// line triggers at cursor', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '/// ' })
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_win_set_cursor(0, { 1, 4 }) -- after "/// "
      -- infer should pick '/' when char before cursor is '/'
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '///' })
      vim.api.nvim_win_set_cursor(0, { 1, 3 })
      local ch = trigger.infer_trigger_char(bufnr, 0, 3)
      expect.equality('/', ch)
      expect.equality(true, trigger.is_inside_line_comment(bufnr, 0, 3, '///'))
    end)

    it('recognizes // @ and // : inside line comment', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '// @' })
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_win_set_cursor(0, { 1, 4 })
      expect.equality(true, trigger.is_inside_line_comment(bufnr, 0, 4, '//'))
      local ch = trigger.infer_trigger_char(bufnr, 0, 4)
      expect.equality('@', ch)

      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '// :' })
      vim.api.nvim_win_set_cursor(0, { 1, 4 })
      expect.equality(true, trigger.is_inside_line_comment(bufnr, 0, 4, '//'))
    end)

    it('recognizes block comment @ trigger', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '/* @' })
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_win_set_cursor(0, { 1, 4 })
      expect.equality(true, trigger.is_inside_block_comment(bufnr, 0, 4))
      local ch = trigger.infer_trigger_char(bufnr, 0, 4)
      expect.equality('@', ch)
    end)

    it('returns nil trigger outside comments', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'const x = 1 /' })
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_win_set_cursor(0, { 1, 14 })
      expect.equality(false, trigger.is_inside_line_comment(bufnr, 0, 14, '//'))
      expect.equality(false, trigger.is_inside_block_comment(bufnr, 0, 14))
      expect.equality(nil, trigger.infer_trigger_char(bufnr, 0, 14))
    end)
  end)

  describe('completion: trigger-aware filtering', function()
    local bufnr
    before_each(function()
      bufnr = vim.api.nvim_create_buf(false, true)
      vim.bo[bufnr].filetype = 'typescript'
      vim.api.nvim_set_current_buf(bufnr)
    end)
    after_each(function()
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end)

    it('provides line commands for / inside ///', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '///', 'const x = 1' })
      vim.api.nvim_win_set_cursor(0, { 1, 3 })
      local items = completion.get_completions { bufnr = bufnr, row = 0, col = 3, trigger_char = '/' }
      local labels = vim.tbl_map(function(i)
        return i.label
      end, items)
      -- should include line-only commands
      expect.equality(true, vim.tbl_contains(labels, 'to-ternary'))
      expect.equality(true, vim.tbl_contains(labels, '23')) -- alias
      expect.equality(true, vim.tbl_contains(labels, 'reverse-if-else'))
      -- both-typed commands also via line triggers
      expect.equality(true, vim.tbl_contains(labels, 'keep-sorted'))
      -- block-only commands do not exist (all both), but at least line check passed
    end)

    it('provides block-able commands for @ inside /* */', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '/* @', 'const x = 1', '*/' })
      vim.api.nvim_win_set_cursor(0, { 1, 4 })
      local items = completion.get_completions { bufnr = bufnr, row = 0, col = 4, trigger_char = '@' }
      local labels = vim.tbl_map(function(i)
        return i.label
      end, items)
      expect.equality(true, vim.tbl_contains(labels, 'keep-sorted'))
      expect.equality(true, vim.tbl_contains(labels, 'keep-unique'))
      expect.equality(true, vim.tbl_contains(labels, 'regex101'))
      -- line-only command should not appear for block trigger? Actually line triggers also accept @ inside line comment, but block trigger only checks block comment. So with '/' not valid in block context, to-ternary requires '/'|':'|'@' inside line comment. At block position is_inside_line_comment is false, so @ with block should still allow both-type commands but not line-only.
      expect.equality(false, vim.tbl_contains(labels, 'to-ternary'))
    end)

    it('provides line+block commands for @ inside line comment', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '// @' })
      vim.api.nvim_win_set_cursor(0, { 1, 4 })
      local items = completion.get_completions { bufnr = bufnr, row = 0, col = 4, trigger_char = '@' }
      local labels = vim.tbl_map(function(i)
        return i.label
      end, items)
      expect.equality(true, vim.tbl_contains(labels, 'keep-sorted'))
      expect.equality(true, vim.tbl_contains(labels, 'to-ternary'))
    end)

    it('returns empty outside comments', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'const x = 1' })
      vim.api.nvim_win_set_cursor(0, { 1, 5 })
      local items = completion.get_completions { bufnr = bufnr, row = 0, col = 5, trigger_char = '/' }
      expect.equality(0, #items)
    end)

    it('respects config.enable = false', function()
      config.setup { enable = false }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '///' })
      vim.api.nvim_win_set_cursor(0, { 1, 3 })
      local items = completion.get_completions { bufnr = bufnr, row = 0, col = 3, trigger_char = '/' }
      expect.equality(0, #items)
    end)

    it('respects languageIds filter', function()
      config.setup { languageIds = { 'lua' } }
      vim.bo[bufnr].filetype = 'typescript'
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '///' })
      vim.api.nvim_win_set_cursor(0, { 1, 3 })
      local items = completion.get_completions { bufnr = bufnr, row = 0, col = 3, trigger_char = '/' }
      expect.equality(0, #items)
      config.setup { languageIds = { '*' } }
      vim.bo[bufnr].filetype = 'typescript'
      items = completion.get_completions { bufnr = bufnr, row = 0, col = 3, trigger_char = '/' }
      expect.equality(true, #items > 0)
    end)

    it('expands aliases and builds detail hints', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '///' })
      vim.api.nvim_win_set_cursor(0, { 1, 3 })
      local items = completion.get_completions { bufnr = bufnr, row = 0, col = 3, trigger_char = '/' }
      local to_arrow_alias = nil
      local to_arrow_full = nil
      for _, it in ipairs(items) do
        if it.label == '2a' then
          to_arrow_alias = it
        end
        if it.label == 'to-arrow' then
          to_arrow_full = it
        end
      end
      assert(to_arrow_alias, 'alias 2a should be present')
      assert(to_arrow_full, 'full to-arrow should be present')
      expect.equality('to-arrow', to_arrow_alias.detail) -- alias detail points to canonical
      -- full item detail should contain alias, sorted short first
      assert(to_arrow_full.detail and to_arrow_full.detail:find '2a', 'full detail should contain alias')
    end)

    it('handles manual invoke (no trigger_char) inside comment', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '/// to' })
      vim.api.nvim_win_set_cursor(0, { 1, 6 })
      -- no trigger_char, but inside line comment — should still complete
      local items = completion.get_completions { bufnr = bufnr, row = 0, col = 6, trigger_char = nil }
      expect.equality(true, #items > 0)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'let x = 1' })
      vim.api.nvim_win_set_cursor(0, { 1, 5 })
      items = completion.get_completions { bufnr = bufnr, row = 0, col = 5, trigger_char = nil }
      expect.equality(0, #items)
    end)

    it('filters via onlyFixable predicate', function()
      config.setup { autocomplete = { onlyFixable = true } }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '///' })
      vim.api.nvim_win_set_cursor(0, { 1, 3 })
      local call_log = {}
      local items = completion.get_completions {
        bufnr = bufnr,
        row = 0,
        col = 3,
        trigger_char = '/',
        check_fixable = function(name)
          table.insert(call_log, name)
          return name == 'to-ternary' -- only this is fixable
        end,
      }
      -- Only the single command (and its alias) should survive, but predicate receives canonical name per label?
      -- Current impl checks per label's command.name, so alias also checks same name.
      for _, it in ipairs(items) do
        expect.equality('to-ternary', it.data.command_name)
      end
      expect.equality(true, #items >= 1)
      expect.equality(true, #call_log > 0)
    end)

    it('async filtering returns via callback', function()
      config.setup { autocomplete = { onlyFixable = true } }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '///' })
      vim.api.nvim_win_set_cursor(0, { 1, 3 })
      local done = false
      local async_items = nil
      completion.get_completions_async({
        bufnr = bufnr,
        row = 0,
        col = 3,
        trigger_char = '/',
        check_fixable_async = function(name, cb)
          vim.schedule(function()
            cb(name == 'to-ternary')
          end)
        end,
      }, function(items)
        async_items = items
        done = true
      end)
      vim.wait(500, function()
        return done
      end)
      assert(done, 'async callback should fire')
      for _, it in ipairs(async_items) do
        expect.equality('to-ternary', it.data.command_name)
      end
    end)
  end)

  describe('integration: inferred trigger + filetype', function()
    it('end-to-end: typing /// triggers completion without explicit char', function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.bo[bufnr].filetype = 'typescript'
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '///' })
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_win_set_cursor(0, { 1, 3 })
      local inferred = trigger.infer_trigger_char(bufnr, 0, 3)
      expect.equality('/', inferred)
      local items = completion.get_completions { bufnr = bufnr, row = 0, col = 3, trigger_char = inferred }
      expect.equality(true, #items > 10)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe('auto-trigger on trigger chars', function()
    local codemod
    local bufnr
    local cmp_calls
    local registered_sources
    local fake_cmp

    before_each(function()
      package.loaded['eslint-codemod'] = nil
      codemod = require 'eslint-codemod'
      config.reset()
      config.setup { autocomplete = { onlyFixable = false } }

      bufnr = vim.api.nvim_create_buf(false, true)
      vim.bo[bufnr].filetype = 'typescript'
      vim.api.nvim_set_current_buf(bufnr)

      cmp_calls = {}
      registered_sources = {}
      fake_cmp = {
        register_source = function(name)
          table.insert(registered_sources, name)
        end,
        complete = function(request)
          --[[ Module calls cmp.complete{...} (dot call, single arg). ]]
          local sources = type(request) == 'table' and request.config and request.config.sources or {}
          table.insert(cmp_calls, sources)
        end,
      }
      package.loaded.cmp = fake_cmp
    end)

    after_each(function()
      package.loaded.cmp = nil
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end

      config.reset()
      codemod.reset()
    end)

    it('completes with the codemod source after ///', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '///' })
      --[[ Insert-mode cursor sits at col == #line; Normal-mode clamps,
        so drive complete_at with the explicit post-insert position. ]]
      codemod.complete_at(bufnr, 0, 3)
      vim.wait(200, function()
        return #cmp_calls > 0
      end)

      expect.equality(1, #cmp_calls)
      expect.equality({ { name = 'eslint_codemod' } }, cmp_calls[1])
    end)

    it('does not complete for non-trigger chars', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'const x' })
      vim.api.nvim_win_set_cursor(0, { 1, 7 })
      codemod.handle_insert_char 'x'
      vim.wait(50)
      expect.equality(0, #cmp_calls)
    end)

    it('does not complete for / outside a comment', function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'const x =' })
      vim.api.nvim_win_set_cursor(0, { 1, 9 })
      codemod.handle_insert_char '/'
      vim.wait(50)
      expect.equality(0, #cmp_calls)
    end)

    it('registers the source once cmp is available', function()
      codemod.setup {}
      expect.equality({ 'eslint_codemod' }, registered_sources)
    end)
  end)

  describe('batch fixability check', function()
    local lint
    local bufnr
    local spawns
    local orig_system

    before_each(function()
      package.loaded['eslint-codemod.lint'] = nil
      lint = require 'eslint-codemod.lint'
      bufnr = vim.api.nvim_create_buf(false, true)
      vim.bo[bufnr].filetype = 'typescript'
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        'const a = 1',
        '',
        '///',
        'if (a === 1)',
        '  console.error(1)',
        'else',
        '  console.error(2)',
      })
      spawns = {}
      orig_system = vim.system
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.system = function(cmd, _opts, cb)
        table.insert(spawns, cmd)
        --[[ Respond: only reverse-if-else is fixable. ]]
        cb {
          code = 0,
          stdout = '{"results":{"reverse-if-else":{"fixable":true},"to-arrow":{"fixable":false}}}',
          stderr = '',
        }
      end
    end)

    after_each(function()
      vim.system = orig_system
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end)

    it('spawns one worker and returns the map', function()
      local done, map = false, nil
      lint.check_fixable_batch({ 'reverse-if-else', 'to-arrow' }, { bufnr = bufnr, row = 0 }, function(m)
        map, done = m, true
      end)
      vim.wait(300, function()
        return done
      end)

      assert(done, 'callback should fire')
      expect.equality(1, #spawns)
      expect.equality('--check-all', spawns[1][3])
      expect.equality('reverse-if-else,to-arrow', spawns[1][4])
      expect.equality(true, map['reverse-if-else'])
      expect.equality(false, map['to-arrow'])
    end)

    it('caches per changedtick and skips the second spawn', function()
      local calls = 0
      local function request(cb)
        lint.check_fixable_batch({ 'reverse-if-else' }, { bufnr = bufnr, row = 0 }, cb)
      end

      request(function()
        calls = calls + 1
      end)
      request(function()
        calls = calls + 1
      end)
      vim.wait(300, function()
        return calls == 2
      end)

      expect.equality(1, #spawns) -- second call hit the cache
      expect.equality(2, calls)
    end)

    it('defaults missing names to fixable on worker failure', function()
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.system = function(_cmd, _opts, cb)
        cb { code = 1, stdout = '', stderr = 'boom' }
      end
      local done, map = false, nil
      lint.check_fixable_batch({ 'to-ternary' }, { bufnr = bufnr, row = 0 }, function(m)
        map, done = m, true
      end)
      vim.wait(300, function()
        return done
      end)

      assert(done)
      expect.equality(true, map['to-ternary'])
    end)
  end)
end)
