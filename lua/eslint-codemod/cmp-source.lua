local completion = require 'eslint-codemod.completion'
local config_mod = require 'eslint-codemod.config'
local trigger = require 'eslint-codemod.trigger'
local lint = require 'eslint-codemod.lint'

local source = {}

function source.new()
  return setmetatable({}, { __index = source })
end

function source:get_trigger_characters()
  return trigger.trigger_chars()
end

--[[ No custom keyword_pattern: nvim-cmp default keyword handles
  the typed prefix; filterText does the rest. ]]

function source:is_available()
  local cfg = config_mod.get()
  if not cfg.enable then
    return false
  end

  local ft = vim.bo.filetype
  return config_mod.is_language_enabled(ft)
end

--[[ nvim-cmp entry point.

  params.context.cursor_before_line
  params.context.cursor.col (1-indexed? cmp docs say byte col)
  params.completion_context.triggerCharacter
]]
function source:complete(params, callback)
  local cfg = config_mod.get()
  if not cfg.enable then
    callback { items = {}, isIncomplete = false }
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1
  local col = cursor[2]
  local trigger_char = params.completion_context and params.completion_context.triggerCharacter
    or trigger.infer_trigger_char(bufnr, row, col)

  local opts = {
    bufnr = bufnr,
    row = row,
    col = col,
    trigger_char = trigger_char,
  }

  --[[ Collect sync-eligible items first (no linting). ]]
  local base_items = completion.get_completions(vim.tbl_extend('force', opts, {
    check_fixable = function(_name)
      return true
    end,
  }))

  if #base_items == 0 then
    callback { items = {}, isIncomplete = false }
    return
  end

  if not cfg.autocomplete.onlyFixable then
    callback { items = base_items, isIncomplete = false }
    return
  end

  --[[ ONE batched worker call for all unique commands, cached per
    (bufnr, changedtick) inside lint.check_fixable_batch. ]]

  local seen = {}
  local names = {}
  for _, item in ipairs(base_items) do
    local name = item.data.command_name
    if not seen[name] then
      seen[name] = true
      names[#names + 1] = name
    end
  end

  lint.check_fixable_batch(names, { bufnr = bufnr, row = row }, function(map)
    local kept = {}
    for _, item in ipairs(base_items) do
      if map[item.data.command_name] then
        kept[#kept + 1] = item
      end
    end
    callback { items = kept, isIncomplete = false }
  end)
end

function source:resolve(completion_item, callback)
  local cfg = config_mod.get()
  local data = completion_item.data or {}
  local command_name = data.command_name or completion_item.label
  if not command_name then
    callback(completion_item)
    return
  end

  local docs_done = false
  local diff_done = not cfg.autocomplete.diff
  local lint_result

  local function try_finish()
    if docs_done and diff_done then
      local parts = {}
      if lint_result and lint_result.fix then
        table.insert(parts, '**✅ Fixable**')
        if lint_result.diff and cfg.autocomplete.diff then
          table.insert(parts, '```diff\n' .. lint_result.diff .. '\n```')
        end
      elseif lint_result and lint_result.error then
        table.insert(parts, '**❌ ' .. lint_result.error .. '**')
      else
        table.insert(parts, '')
      end

      if lint_result and lint_result.docs then
        table.insert(parts, lint_result.docs)
      else
        local docs_mod = require 'eslint-codemod.docs'
        table.insert(parts, docs_mod.format_fallback(command_name))
      end

      local documentation = table.concat(parts, '\n\n')
      completion_item.documentation = {
        kind = 'markdown',
        value = vim.trim(documentation),
      }
      callback(completion_item)
    end
  end

  --[[ Fetch docs if enabled. ]]
  if cfg.autocomplete.docs then
    local docs_mod = require 'eslint-codemod.docs'
    docs_mod.get(command_name, function(content, _err)
      lint_result = lint_result or {}
      if content then
        lint_result.docs = content
      end

      docs_done = true
      try_finish()
    end)
  else
    docs_done = true
  end

  if cfg.autocomplete.diff then
    local bufnr = vim.api.nvim_get_current_buf()
    local cursor = vim.api.nvim_win_get_cursor(0)
    lint.get_lint_result(command_name, { bufnr = bufnr, row = cursor[1] - 1, col = cursor[2] }, function(res, _err)
      lint_result = res or lint_result or {}
      --[[ If the worker returned a diff patch, stash it. ]]
      diff_done = true
      if not lint_result and _err then
        lint_result = { error = _err }
      end

      try_finish()
    end)

    if docs_done and not diff_done then
      -- waiting for diff only
    elseif docs_done and diff_done then
      try_finish()
    end
  else
    try_finish()
  end

  --[[ Fallback: resolve immediately if both disabled and no async. ]]
  if docs_done and diff_done then
    try_finish()
  end
end

function source:execute(completion_item, callback)
  local cfg = config_mod.get()
  if not cfg.autocomplete.autoFix then
    if callback then
      callback()
    end

    return
  end

  --[[ Trigger ESLint / Oxlint fixAll at cursor line.

    VSCode executes `eslint.executeAutofix`. In Neovim we try LSP
    code actions: `source.fixAll.eslint` then `source.fixAll.oxc`.
  ]]
  local bufnr = vim.api.nvim_get_current_buf()
  local clients = vim.lsp.get_clients { bufnr = bufnr }
  local function request_fixall(client_name, action_kind)
    for _, client in ipairs(clients) do
      if client.name == client_name then
        vim.lsp.buf.code_action {
          context = { only = { action_kind } },
          apply = true,
        }
        return true
      end
    end

    return false
  end

  if not request_fixall('eslint', 'source.fixAll.eslint') then
    request_fixall('oxlint', 'source.fixAll.oxc')
  end

  if callback then
    callback(completion_item)
  end
end

return source
