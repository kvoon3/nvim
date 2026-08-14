-- Show resolved pnpm catalog versions inline next to `catalog:` entries in package.json.
-- Catalogs are read from the nearest pnpm-workspace.yaml above the current file.
local M = {}
local ns = vim.api.nvim_create_namespace 'pnpm_catalog_lens'
local hl_group = 'PnpmCatalogLens'
local enabled = true

--[[
Parse a `pkg: version` line, tolerating quoted keys/values.
Returns pkg, version or nil when the line is not a catalog entry.
]]
local function parse_entry(trimmed)
  local pkg, version = trimmed:match '^["\']?([%w@/%._%-]+)["\']?:%s*(%S+)'
  if not pkg then
    return nil
  end
  return pkg, (version:gsub('^["\']', ''):gsub('["\']$', ''))
end

local function apply_entry(catalogs, mode, current_named, trimmed)
  local pkg, version = parse_entry(trimmed)
  local key = pkg and (mode == 'default' and 'default' or current_named)
  if key then
    catalogs[key] = catalogs[key] or {}
    catalogs[key][pkg] = version
  end
end

--[[
Parse catalog entries from a pnpm-workspace.yaml using indentation only.
Returns { default = { pkg = version }, <catalog-name> = { pkg = version } }.
]]
local function parse_catalogs(path)
  local catalogs = {}
  local mode = nil -- 'default' | 'named'
  local base_indent = 0
  local current_named = nil

  for line in io.lines(path) do
    local indent = #(line:match '^%s*')
    local trimmed = line:match '^%s*(.-)%s*$'

    if trimmed ~= '' and trimmed:sub(1, 1) ~= '#' then
      if indent <= base_indent then
        mode = nil
        current_named = nil
      end

      if trimmed == 'catalog:' then
        mode = 'default'
        base_indent = indent
      elseif trimmed == 'catalogs:' then
        mode = 'named'
        base_indent = indent
      elseif mode == 'named' and indent == base_indent + 2 and trimmed:match '^[%w%._%-]+:$' then
        current_named = trimmed:sub(1, -2)
      elseif mode and indent > base_indent then
        apply_entry(catalogs, mode, current_named, trimmed)
      end
    end
  end

  return catalogs
end

local function set_highlight()
  vim.api.nvim_set_hl(0, hl_group, { link = 'Comment' })
end

function M.refresh(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  if not enabled then
    return
  end

  local name = vim.api.nvim_buf_get_name(bufnr)
  if not name:match 'package%.json$' then
    return
  end

  local workspace = vim.fs.find('pnpm-workspace.yaml', { upward = true, path = vim.fs.dirname(name) })[1]
  if not workspace then
    return
  end

  local catalogs = parse_catalogs(workspace)

  for row, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
    local pkg, catalog = line:match '^%s*"([^"]+)"%s*:%s*"catalog:([^"]*)"'
    if pkg then
      local entry = catalogs[catalog ~= '' and catalog or 'default']
      local version = entry and entry[pkg]
      if version then
        -- Insert the hint right after the closing quote of the catalog string.
        local _, close_col = line:find '"catalog:[^"]*"'
        local label = catalog ~= '' and (catalog .. ': ' .. version) or version
        vim.api.nvim_buf_set_extmark(bufnr, ns, row - 1, close_col, {
          virt_text = { { '  ' .. label, hl_group } },
          virt_text_pos = 'inline',
        })
      end
    end
  end
end

function M.toggle()
  enabled = not enabled
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      M.refresh(bufnr)
    end
  end
end

function M.setup()
  local group = vim.api.nvim_create_augroup('PnpmCatalogLens', { clear = true })
  set_highlight()

  vim.api.nvim_create_autocmd('ColorScheme', {
    group = group,
    callback = set_highlight,
    desc = 'Refresh pnpm catalog lens highlight',
  })

  vim.api.nvim_create_autocmd({ 'BufEnter', 'BufWritePost', 'TextChanged', 'TextChangedI' }, {
    group = group,
    pattern = 'package.json',
    callback = function(args)
      M.refresh(args.buf)
    end,
    desc = 'Update pnpm catalog version hints',
  })

  require('cmdr').add {
    {
      desc = 'Toggle pnpm Catalog Lens',
      cmd = function()
        M.toggle()
      end,
      cat = 'lens',
    },
  }
end

M._parse_catalogs = parse_catalogs

return M
