-- Show resolved pnpm catalog versions inline next to `catalog:` entries in package.json.
-- Catalogs are read from the nearest pnpm-workspace.yaml above the current file.
local M = {}
local ns = vim.api.nvim_create_namespace 'pnpm_catalog_lens'
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

local function hsl_to_hex(h, s, l)
  h = (h % 360) / 360
  s = s / 100
  l = l / 100
  local r, g, b
  if s == 0 then
    r, g, b = l, l, l
  else
    local function hue2rgb(p, q, t)
      if t < 0 then
        t = t + 1
      end
      if t > 1 then
        t = t - 1
      end
      if t < 1 / 6 then
        return p + (q - p) * 6 * t
      end
      if t < 1 / 2 then
        return q
      end
      if t < 2 / 3 then
        return p + (q - p) * (2 / 3 - t) * 6
      end
      return p
    end
    local q = l < 0.5 and l * (1 + s) or l + s - l * s
    local p = 2 * l - q
    r = hue2rgb(p, q, h + 1 / 3)
    g = hue2rgb(p, q, h)
    b = hue2rgb(p, q, h - 1 / 3)
  end
  local function channel(x)
    return math.max(0, math.min(255, math.floor(x * 255 + 0.5)))
  end
  return string.format('#%02x%02x%02x', channel(r), channel(g), channel(b))
end

local color_cache = { default = '#f69220' } -- pnpm orange, same as the VS Code extension

--[[
Deterministic color per catalog name, using the same string hash, saturation,
and lightness as the VS Code extension.
]]
local function catalog_color(name)
  local cached = color_cache[name]
  if cached then
    return cached
  end
  local hash = 0
  for i = 1, #name do
    hash = name:byte(i) + hash * 31
  end
  local color = hsl_to_hex(hash % 360, 35, 55)
  color_cache[name] = color
  return color
end

local applied_hl = {}

--[[
Approximate the VS Code badge background: catalog color at low alpha over the
Normal background (Neovim has no real alpha, so blend to a solid hex).
]]
local function badge_bg(color)
  local normal_bg = vim.api.nvim_get_hl(0, { name = 'Normal' }).bg
  local base = normal_bg and string.format('#%06x', normal_bg)
    or (vim.o.background == 'dark' and '#000000' or '#ffffff')
  local function channel(i)
    local fg = tonumber(color:sub(i, i + 1), 16)
    local bg = tonumber(base:sub(i, i + 1), 16)
    return math.floor(0.15 * fg + 0.85 * bg + 0.5)
  end
  return string.format('#%02x%02x%02x', channel(2), channel(4), channel(6))
end

--[[
Return highlight groups for a catalog: a badge (fg + blended bg) for the
version and a plain fg group for the trailing named-catalog label.
]]
local function hl_for(catalog_name)
  local badge = 'PnpmCatalogLens' .. (catalog_name == 'default' and '' or ('_' .. catalog_name:gsub('[^%w]', '')))
  if not applied_hl[badge] then
    local color = catalog_color(catalog_name)
    vim.api.nvim_set_hl(0, badge, { fg = color, bg = badge_bg(color) })
    vim.api.nvim_set_hl(0, badge .. 'Label', { fg = color })
    applied_hl[badge] = true
  end
  return badge, badge .. 'Label'
end

local function decorate_line(bufnr, catalogs, row, line)
  local pkg, catalog = line:match '^%s*"([^"]+)"%s*:%s*"catalog:([^"]*)"'
  if not pkg then
    return
  end
  local catalog_name = catalog ~= '' and catalog or 'default'
  local entry = catalogs[catalog_name]
  local version = entry and entry[pkg]
  if not version then
    return
  end
  -- Conceal the catalog protocol (keeping the quotes) and put the resolved
  -- version in its place, like the VS Code extension.
  local start_col, end_col = line:find '"catalog:[^"]*"'
  local badge, label_hl = hl_for(catalog_name)
  local chunks = { { ' ' .. version .. ' ', badge } }
  if catalog ~= '' then
    chunks[#chunks + 1] = { ' ' .. catalog, label_hl }
  end
  vim.api.nvim_buf_set_extmark(bufnr, ns, row - 1, start_col, {
    end_col = end_col - 1,
    conceal = '',
    virt_text = chunks,
    virt_text_pos = 'inline',
  })
end

function M.refresh(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  -- Insert mode keeps the raw `catalog:xxx` strings editable.
  if not enabled or vim.fn.mode():sub(1, 1) == 'i' then
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

  if bufnr == vim.api.nvim_get_current_buf() then
    vim.wo.conceallevel = 2
  end

  local catalogs = parse_catalogs(workspace)

  for row, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
    decorate_line(bufnr, catalogs, row, line)
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

  -- Highlight groups survive until a colorscheme clears them; re-apply lazily.
  vim.api.nvim_create_autocmd('ColorScheme', {
    group = group,
    callback = function()
      applied_hl = {}
      M.refresh()
    end,
    desc = 'Re-apply pnpm catalog lens colors',
  })

  vim.api.nvim_create_autocmd({ 'BufEnter', 'BufWritePost', 'TextChanged', 'TextChangedI', 'InsertLeave' }, {
    group = group,
    pattern = 'package.json',
    callback = function(args)
      M.refresh(args.buf)
    end,
    desc = 'Update pnpm catalog version hints',
  })

  -- mode() still reports 'n' during InsertEnter, so clear directly instead of
  -- going through refresh's insert-mode guard.
  vim.api.nvim_create_autocmd('InsertEnter', {
    group = group,
    pattern = 'package.json',
    callback = function(args)
      vim.api.nvim_buf_clear_namespace(args.buf, ns, 0, -1)
    end,
    desc = 'Show raw catalog strings while editing',
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
M._catalog_color = catalog_color

return M
