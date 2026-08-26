local config_mod = require 'eslint-codemod.config'
local trigger = require 'eslint-codemod.trigger'

local M = {}

local setup_done = false
local source_registered = false

--[[ Register the cmp source once cmp is actually loaded (lazy.nvim
  loads nvim-cmp on InsertEnter, so it is absent during startup).
  Returns false while cmp is still unavailable. ]]
local function ensure_cmp_source()
  if source_registered then
    return true
  end

  local has_cmp, cmp = pcall(require, 'cmp')
  if not has_cmp then
    return false
  end

  cmp.register_source('eslint_codemod', require('eslint-codemod.cmp-source').new())
  source_registered = true
  return true
end

--[[ InsertCharPre fires before the char lands; the scheduled check runs
  after insertion so the cursor sits right after the trigger char. ]]
function M.handle_insert_char(char)
  local cfg = config_mod.get()
  if not cfg.enable then
    return
  end

  if char ~= '/' and char ~= '@' and char ~= ':' then
    return
  end

  if not config_mod.is_language_enabled(vim.bo.filetype) then
    return
  end

  vim.schedule(function()
    local bufnr = vim.api.nvim_get_current_buf()
    local cursor = vim.api.nvim_win_get_cursor(0)
    M.complete_at(bufnr, cursor[1] - 1, cursor[2])
  end)
end

--[[ Open the codemod-only completion menu at an explicit position.
  Exposed for testing: Normal-mode cursors clamp to the last char,
  while real triggers happen in Insert mode where col == #line. ]]
function M.complete_at(bufnr, row, col)
  if not trigger.infer_trigger_char(bufnr, row, col) then
    return
  end

  if not ensure_cmp_source() then
    --[[ No cmp: fall back to built-in completefunc completion. ]]
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-x><C-u>', true, false, true), 'm', false)
    return
  end

  --[[ Restrict the menu to codemod commands, mirroring VSCode's
    provider-scoped trigger behavior. ]]
  require('cmp').complete {
    config = { sources = { { name = 'eslint_codemod' } } },
  }
end

function M.setup(opts)
  config_mod.setup(opts or {})

  if setup_done then
    return
  end

  setup_done = true
  ensure_cmp_source()

  local group = vim.api.nvim_create_augroup('EslintCodemod', { clear = true })

  --[[ Auto-trigger on / @ : like VSCode triggerCharacters. ]]
  vim.api.nvim_create_autocmd('InsertCharPre', {
    group = group,
    callback = function()
      M.handle_insert_char(vim.v.char)
    end,
  })

  --[[ cmp loads lazily on InsertEnter; retry source registration until
    it exists. Also keeps the global sources entry usable. ]]
  vim.api.nvim_create_autocmd({ 'InsertEnter', 'FileType' }, {
    group = group,
    callback = function(ev)
      if not config_mod.is_language_enabled(ev.match ~= '' and ev.match or vim.bo.filetype) then
        return
      end

      ensure_cmp_source()
    end,
  })

  --[[ Fallback omnifunc path for users without cmp:

    `completefunc` is wired but only active inside codemod comment
    regions so it does not pollute normal editing.
  ]]
  vim.api.nvim_create_autocmd('FileType', {
    callback = function(ev)
      if not config_mod.is_language_enabled(ev.match) then
        return
      end

      vim.bo[ev.buf].completefunc = "v:lua.require'eslint-codemod'.omnifunc"
    end,
  })

  --[[ Watch for eslint config changes — invalidate docs cache. ]]
  vim.api.nvim_create_autocmd('BufWritePost', {
    group = group,
    pattern = {
      'eslint.config.js',
      'eslint.config.mjs',
      'eslint.config.cjs',
      'eslint.config.ts',
      '.eslintrc',
      '.eslintrc.js',
      '.eslintrc.cjs',
      '.eslintrc.yaml',
      '.eslintrc.yml',
      '.eslintrc.json',
      'package.json',
    },
    callback = function()
      local docs = require 'eslint-codemod.docs'
      if docs then
        pcall(docs.clear)
      end
    end,
  })

  --[[ cmdr palette integration. ]]
  local has_cmdr, cmdr = pcall(require, 'cmdr')
  if has_cmdr then
    cmdr.add {
      {
        desc = 'ESLint Codemod: toggle autoFix',
        cmd = function()
          local cfg = config_mod.get()
          config_mod.setup { autocomplete = { autoFix = not cfg.autocomplete.autoFix } }
          vim.notify(
            string.format('eslint-codemod autoFix: %s', config_mod.get().autocomplete.autoFix and 'on' or 'off'),
            vim.log.levels.INFO
          )
        end,
        cat = 'eslint-codemod',
      },
      {
        desc = 'ESLint Codemod: toggle docs preview',
        cmd = function()
          local cfg = config_mod.get()
          config_mod.setup { autocomplete = { docs = not cfg.autocomplete.docs } }
          vim.notify(
            string.format('eslint-codemod docs: %s', config_mod.get().autocomplete.docs and 'on' or 'off'),
            vim.log.levels.INFO
          )
        end,
        cat = 'eslint-codemod',
      },
    }
  end
end

--[[ omnifunc fallback: vim's `completefunc` protocol.

  Called with `findstart == 1` → return column where completion starts.
  Called with `findstart == 0` → return list of words.
]]
function M.omnifunc(findstart, base)
  local completion = require 'eslint-codemod.completion'
  if findstart == 1 then
    local bufnr = vim.api.nvim_get_current_buf()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local row = cursor[1] - 1
    local col = cursor[2]
    --[[ Only activate inside a codemod comment. ]]
    local trig = trigger.infer_trigger_char(bufnr, row, col)
    local inside_line = trigger.is_inside_line_comment(bufnr, row, col)
    local inside_block = trigger.is_inside_block_comment(bufnr, row, col)
    if not trig and not inside_line and not inside_block then
      return -3 -- cancel silently
    end

    local line = vim.api.nvim_get_lines(bufnr, row, row + 1, false)[1] or ''
    local before = line:sub(1, col)
    local s = before:find '[%w%-]+$'
    if s then
      return s - 1
    end

    return col
  else
    local bufnr = vim.api.nvim_get_current_buf()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local row = cursor[1] - 1
    local col = cursor[2]
    local trig = trigger.infer_trigger_char(bufnr, row, col)
    local items = completion.get_completions {
      bufnr = bufnr,
      row = row,
      col = col,
      trigger_char = trig,
    }
    local words = {}
    for _, it in ipairs(items) do
      if base == '' or it.label:sub(1, #base) == base then
        table.insert(words, {
          word = it.insertText,
          abbr = it.label,
          menu = it.detail or it.data.command_name,
          kind = 'Text',
          dup = 0,
        })
      end
    end

    return words
  end
end

function M.reset()
  setup_done = false
  source_registered = false
  config_mod.reset()
end

return M
