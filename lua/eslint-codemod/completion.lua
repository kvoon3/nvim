local commands = require 'eslint-codemod.commands'
local config_mod = require 'eslint-codemod.config'
local trigger = require 'eslint-codemod.trigger'

local M = {}

--[[ Build a single completion item mirroring VSCode's `item` shape.

  Fields kept deliberately close to nvim-cmp's `lsp.CompletionItem`:
    label      - shown in the menu
    filterText - used for fuzzy filtering
    detail     - alias / canonical name hint
    insertText - text inserted on confirm
    kind       - cmp.lsp.CompletionItemKind.Text (1)
]]
local function build_detail(label, name, alias)
  local others = {}
  for _, a in ipairs(alias) do
    if a ~= label then
      table.insert(others, a)
    end
  end

  if name ~= label then
    table.insert(others, name)
  end

  if #others == 0 then
    return nil
  end

  if label == name then
    --[[ Prefer short aliases first. ]]
    table.sort(others, function(a, b)
      return #a < #b
    end)
  else
    --[[ When the label itself is an alias, prefer the canonical name
      (longer) first — matches VSCode's `b.length - a.length`. ]]
    table.sort(others, function(a, b)
      return #a > #b
    end)
  end

  return table.concat(others, ',')
end

--[[ Core: enumerate candidates for the current cursor/trigger.

  opts:
    bufnr        - buffer id (0 = current)
    row, col     - 0-indexed cursor (col = byte column before cursor)
    trigger_char - '/' | '@' | ':' | nil (nil => also infer)
    check_fixable - async predicate `fn(command_name): boolean`
                    when provided and config.autocomplete.onlyFixable,
                    a candidate is kept only if the predicate resolves
                    truthy. In headless tests this can be stubbed;
                    in production it lint-checks via eslint.
    config_override - optional table to override config for testing
]]
local function resolve_context(opts)
  local bufnr = opts.bufnr or 0
  local row, col = opts.row, opts.col
  --[[ Infer row/col from current cursor when not supplied. ]]
  if row == nil or col == nil then
    local cursor = vim.api.nvim_win_get_cursor(0)
    row, col = cursor[1] - 1, cursor[2]
    bufnr = vim.api.nvim_get_current_buf()
  end

  return bufnr, row, col
end

--[[ Manual invoke inside comment: accept if *any* trigger condition holds. ]]
local function any_trigger_matches(cmd, bufnr, row, col)
  for _, t in ipairs(trigger.triggers_for(cmd.commentType or 'line')) do
    if t.condition(bufnr, row, col) then
      return true
    end
  end

  return false
end

local function is_label_valid(cmd, trigger_char, bufnr, row, col)
  if trigger_char then
    return trigger.is_trigger_valid(cmd, trigger_char, bufnr, row, col)
  end

  return any_trigger_matches(cmd, bufnr, row, col)
end

--[[ onlyFixable gate — defer to the provided checker; without a checker
  keep the item (static mode). ]]
local function passes_fixable_gate(cfg, name, check_fixable)
  if not cfg.autocomplete.onlyFixable or not check_fixable then
    return true
  end

  local ok, fixable = pcall(check_fixable, name)
  return ok and fixable == true
end

--[[ Resolve the effective trigger char.

  Returns:
    (char, true)  - explicit or inferred trigger
    (nil, true)   - manual invoke inside a comment region: all matching
                    triggers are eligible
    (nil, false)  - outside any comment: completion should abort
]]
local function resolve_trigger(trigger_char, bufnr, row, col)
  trigger_char = trigger_char or trigger.infer_trigger_char(bufnr, row, col)
  if trigger_char then
    return trigger_char, true
  end

  local inside_comment = trigger.is_inside_line_comment(bufnr, row, col)
    or trigger.is_inside_block_comment(bufnr, row, col)
  return nil, inside_comment
end

function M.get_completions(opts)
  opts = opts or {}
  local cfg = opts.config_override or config_mod.get()
  if not cfg.enable then
    return {}
  end

  local bufnr, row, col = resolve_context(opts)
  if not config_mod.is_language_enabled(vim.bo[bufnr].filetype) then
    return {}
  end

  local trigger_char, ok = resolve_trigger(opts.trigger_char, bufnr, row, col)
  if not ok then
    return {}
  end

  local alias_map = cfg.alias or {}
  local items = {}

  for _, cmd in ipairs(commands.get_all()) do
    local alias_list = alias_map[cmd.name] or {}
    if type(alias_list) == 'string' then
      alias_list = { alias_list }
    end

    local candidates = { cmd.name }
    for _, a in ipairs(alias_list) do
      table.insert(candidates, a)
    end

    for _, label in ipairs(candidates) do
      if
        is_label_valid(cmd, trigger_char, bufnr, row, col) and passes_fixable_gate(cfg, cmd.name, opts.check_fixable)
      then
        table.insert(items, {
          label = label,
          filterText = label,
          detail = build_detail(label, cmd.name, alias_list),
          insertText = label,
          kind = 1, -- Text
          data = { command_name = cmd.name, is_alias = label ~= cmd.name },
        })
      end
    end
  end

  return items
end

--[[ Helper used by the cmp source when `onlyFixable` is enabled with
  an async linter. Returns filtered items via callback. ]]
function M.get_completions_async(opts, callback)
  opts = opts or {}
  local cfg = opts.config_override or config_mod.get()

  if not cfg.autocomplete.onlyFixable or not opts.check_fixable_async then
    local items = M.get_completions(opts)
    callback(items)
    return
  end

  --[[ First collect sync-eligible items, then async-filter. ]]
  local check_sync = function(_name)
    return true
  end
  local base_items = M.get_completions(vim.tbl_extend('force', opts, { check_fixable = check_sync }))
  local pending = #base_items
  if pending == 0 then
    callback {}
    return
  end

  local kept = {}
  for _, item in ipairs(base_items) do
    local name = item.data.command_name
    opts.check_fixable_async(name, function(is_fixable)
      if is_fixable then
        table.insert(kept, item)
      end

      pending = pending - 1
      if pending == 0 then
        callback(kept)
      end
    end)
  end
end

--[[ Documentation / diff helpers — pure formatting, no I/O. ]]
function M.format_detail(item)
  if not item.detail or item.detail == '' then
    return nil
  end

  return item.detail
end

return M
