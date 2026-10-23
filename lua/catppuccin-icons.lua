--- Catppuccin VS Code icons, prepared as PNG for real-icons.nvim.
---
--- real-icons hands icon files to ImageMagick, but the Homebrew ImageMagick bottle has no
--- librsvg delegate and its internal SVG renderer cannot draw these pastel stroke icons
--- (blank or failing output). So the VS Code extension ships SVG while we ship PNG: this
--- module converts the installed extension once and points the icon packs at the result.
local M = {}

local extension = 'catppuccin.catppuccin-vsc-icons'
local flavors = { 'mocha', 'latte' }
local roots = {
  '~/.vscode/extensions',
  '~/.vscode-oss/extensions',
  '~/.vscodium/extensions',
  '~/.cursor/extensions',
  '~/.windsurf/extensions',
}
local size = 128 -- source SVGs are 16x16; real-icons downsamples this to its own pixel size

--[[ Zero-pad every number so plain string order matches numeric version order. ]]
local function version_key(path)
  local padded = (path:match '%-([%d%.]+)$' or ''):gsub('%d+', function(number)
    return string.format('%08d', tonumber(number))
  end)
  return padded
end

--[[ Newest installed copy of the extension, or nil when VS Code never installed it. ]]
function M.extension_dir()
  local matches = {}
  for _, root in ipairs(roots) do
    vim.list_extend(matches, vim.fn.glob(root .. '/' .. extension .. '-*', false, true))
  end

  table.sort(matches, function(a, b)
    return version_key(a) < version_key(b)
  end)

  return matches[#matches]
end

--[[ Converted icons live next to the cache, keyed by extension version so updates rebuild. ]]
local function cache_root(dir)
  local version = dir:match '%-([%d%.]+)$' or 'latest'
  return vim.fn.stdpath 'cache' .. '/catppuccin-icons/' .. version
end

--[[ Icon pack specs for real-icons, plus whether every flavor has been converted. ]]
function M.packs()
  local dir = M.extension_dir()
  if not dir then
    return nil, nil
  end

  local root = cache_root(dir)
  local packs = {}
  local ready = true
  for _, flavor in ipairs(flavors) do
    packs['catppuccin_' .. flavor] = {
      type = 'vscode',
      path = root .. '/' .. flavor,
      manifest = 'theme.json',
    }
    ready = ready and vim.uv.fs_stat(root .. '/' .. flavor .. '/.complete') ~= nil
  end

  return packs, ready
end

--[[ Rewrite icon paths from SVG to the PNG files written beside them. ]]
local function write_manifest(source, target)
  local file = assert(io.open(source .. '/theme.json', 'r'))
  local manifest = file:read '*a'
  file:close()

  file = assert(io.open(target .. '/theme.json', 'w'))
  file:write((manifest:gsub('%.svg"', '.png"')))
  file:close()
end

local function convert_flavor(dir, root, flavor, notify)
  local source = dir .. '/dist/' .. flavor
  local target = root .. '/' .. flavor
  if vim.uv.fs_stat(target .. '/.complete') then
    return true
  end

  if vim.fn.executable 'rsvg-convert' ~= 1 then
    return false, 'rsvg-convert is missing (brew install librsvg)'
  end

  vim.fn.mkdir(target .. '/icons', 'p')
  write_manifest(source, target)

  local icons = vim.fn.glob(source .. '/icons/*.svg', false, true)
  local failed = 0
  for index, icon in ipairs(icons) do
    local output = target .. '/icons/' .. vim.fs.basename(icon):gsub('%.svg$', '.png')
    local result = vim
      .system({
        'rsvg-convert',
        '--width',
        tostring(size),
        '--height',
        tostring(size),
        '--output',
        output,
        icon,
      }, { text = true })
      :wait()
    if result.code ~= 0 then
      failed = failed + 1
    end

    if notify and index % 100 == 0 then
      vim.notify(string.format('catppuccin-icons: %s %d/%d', flavor, index, #icons), vim.log.levels.INFO)
    end
  end

  if failed > 0 then
    return false, string.format('%d of %d icons failed in %s', failed, #icons, flavor)
  end

  vim.fn.writefile({}, target .. '/.complete')
  return true
end

--[[ Convert every flavor once. Runs from the plugin build step, or from the palette after an extension update. ]]
function M.build(opts)
  opts = opts or {}
  local dir = M.extension_dir()
  if not dir then
    vim.notify('catppuccin-icons: install the Catppuccin Icons VS Code extension first', vim.log.levels.WARN)
    return false
  end

  local root = cache_root(dir)
  if opts.force then
    vim.fn.delete(root, 'rf')
  end

  for _, flavor in ipairs(flavors) do
    local ok, err = convert_flavor(dir, root, flavor, opts.notify ~= false)
    if not ok then
      vim.notify('catppuccin-icons: ' .. err, vim.log.levels.ERROR)
      return false
    end
  end

  if opts.notify ~= false then
    vim.notify('catppuccin-icons: icons ready in ' .. root, vim.log.levels.INFO)
  end

  -- Refresh this session when the build was triggered from the palette.
  if package.loaded['real-icons'] then
    local real_icons = require 'real-icons'
    real_icons.use_pack(real_icons.pack(), { notify = false })
  end

  return true
end

return M
