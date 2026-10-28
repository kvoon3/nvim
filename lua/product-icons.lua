--[[ Product icons: the UI half of the icon set.

File icons answer "what is this buffer?" and come from a VS Code file icon
theme (see plugins/real-icons.lua). Product icons answer "what does this
button do?" - explorer, terminal, VCS, diagnostics - and come from a VS Code
*product* icon theme: Carbon (antfu/vscode-icons-carbon, Carbon Icons by IBM,
Apache-2.0), vendored as SVG in assets/product-icons. VS Code only accepts
that theme as a WOFF font, which Neovim cannot load, so the SVGs are
rasterised here instead.

Both families paint through real-icons: a Kitty graphics image behind a
placeholder cell pair. A product icon is tinted with the foreground of the
highlight group it belongs to, so it follows the colorscheme instead of
carrying a palette of its own. Without an image backend or an SVG rasteriser
the Nerd Font glyph in the registry stands in and the footer keeps its
layout. ]]

local M = {}

local uv = vim.uv or vim.loop

--[[ role -> Carbon file, stand-in glyph, and the group whose foreground tints
the image. Roles are the vocabulary callers use, so refreshing the vendored
assets never renames a call site. ]]
local registry = {
  branch = { svg = 'branch', glyph = '󰘬', group = 'MiniStatuslineDevinfo' },
  diff = { svg = 'compare', glyph = '', group = 'MiniStatuslineDevinfo' },
  lsp = { svg = 'plug', glyph = '󰰎', group = 'MiniStatuslineDevinfo' },
  todo = { svg = 'list-checked', glyph = '', group = 'MiniStatuslineDevinfo' },
  error = { svg = 'warning', glyph = '󰅚', group = 'DiagnosticError' },
  warning = { svg = 'warning-alt', glyph = '󰀪', group = 'DiagnosticWarn' },
  info = { svg = 'information', glyph = '󰋽', group = 'DiagnosticInfo' },
  hint = { svg = 'idea', glyph = '󰌶', group = 'DiagnosticHint' },
  explorer = { svg = 'folder-tree', glyph = '󰉋', group = 'MiniStatuslineFileinfo' },
  terminal = { svg = 'terminal', glyph = '󰆍', group = 'MiniStatuslineFileinfo' },
  finder = { svg = 'apple', glyph = '󰀶', group = 'MiniStatuslineFileinfo' },
  github = { svg = 'logo-github', glyph = '󰊤', group = 'MiniStatuslineFileinfo' },
}

local roles = vim.tbl_keys(registry)
table.sort(roles)

local segment_cache = {}
local ready = {}
local failed = {}
local queued = {}
local queue = {}
local running = 0
local capability

local function root()
  local source = debug.getinfo(1, 'S').source
  local file = source:sub(1, 1) == '@' and source:sub(2) or source
  return vim.fs.dirname(vim.fs.dirname(vim.fn.fnamemodify(file, ':p')))
end

local function svg_path(role)
  return root() .. '/assets/product-icons/' .. registry[role].svg .. '.svg'
end

---Executable that can turn an SVG into a PNG, or nil when neither is installed.
local function converter()
  if vim.fn.executable 'rsvg-convert' == 1 then
    return 'rsvg-convert'
  end
  if vim.fn.executable 'magick' == 1 then
    return 'magick'
  end
end

--[[ Match the file icon geometry so both families share a baseline: two cells
wide, one row tall, and the same supersampled pixel box real-icons uses. ]]
local function size()
  local pixels = 48
  local ok, config = pcall(require, 'real-icons.config')
  if ok and type(config.options) == 'table' and type(config.options.size) == 'table' then
    pixels = tonumber(config.options.size.pixels) or pixels
  end
  return { cols = 2, rows = 1, pixels = pixels, padding = 0, trim = false }
end

local function hex(value)
  if type(value) == 'number' then
    return string.format('#%06x', value % 0x1000000)
  end
  if type(value) == 'string' and value:match '^#' then
    return value
  end
  return nil
end

local function foreground(group)
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = group, link = false })
  if not ok or type(hl) ~= 'table' then
    return nil
  end
  return hex(hl.fg)
end

--[[ Tint an icon with its own group's foreground, so a severity icon is
exactly as red as the count beside it. Normal covers groups without a
foreground, and a plain grey covers a colorscheme that sets none at all. ]]
local function tint(group)
  return foreground(group) or foreground 'Normal' or (vim.o.background == 'light' and '#1c1c1c' or '#dddddd')
end

local function cache_dir()
  return vim.fn.stdpath 'cache' .. '/product-icons'
end

local dir_ready = false

local function ensure_dir()
  if not dir_ready then
    vim.fn.mkdir(cache_dir(), 'p')
    dir_ready = true
  end
end

local function read(path)
  local fd = uv.fs_open(path, 'r', 438)
  if not fd then
    return nil
  end
  local stat = uv.fs_fstat(fd)
  local data = stat and uv.fs_read(fd, stat.size, 0)
  uv.fs_close(fd)
  return data
end

local function write(path, data)
  local fd = uv.fs_open(path, 'w', 420)
  if not fd then
    return false
  end
  uv.fs_write(fd, data, 0)
  uv.fs_close(fd)
  return true
end

---The temporary SVG that carries the tint, next to the PNG it produces.
local function tinted_path(png)
  return (png:gsub('%.png$', '.svg'))
end

--[[ Cache name for one tinted raster. The source size and mtime are part of
the key, so refreshing a vendored SVG produces a new file instead of silently
reusing a stale one. ]]
local function target(role, color)
  local stat = uv.fs_stat(svg_path(role))
  local pixels = size().pixels
  local key = table.concat({
    role,
    color,
    pixels,
    stat and stat.size or 0,
    stat and stat.mtime.sec or 0,
    stat and stat.mtime.nsec or 0,
  }, '|')
  return string.format('%s/%s-%s.png', cache_dir(), role, vim.fn.sha256(key):sub(1, 12))
end

--[[ Rasterise one tinted icon at the exact pixel box it will be drawn into.
rsvg-convert renders the SVG straight to that size; ImageMagick is the
fallback for machines without librsvg. Returns nil when the source cannot be
read or written. ]]
local function argv(role, png, color)
  local source = read(svg_path(role))
  if not source then
    return nil
  end
  local tinted = tinted_path(png)
  ensure_dir()
  if not write(tinted, (source:gsub('currentColor', color))) then
    return nil
  end

  local pixels = size().pixels
  if converter() == 'rsvg-convert' then
    return { 'rsvg-convert', '--width', tostring(pixels), '--height', tostring(pixels), '--output', png, tinted }
  end
  return { 'magick', '-background', 'none', tinted, '-resize', pixels .. 'x' .. pixels, png }
end

local pump

local function settle(png, err)
  running = running - 1
  queued[png] = nil
  if err and err ~= '' then
    failed[png] = err
  else
    ready[png] = true
  end
  uv.fs_unlink(tinted_path(png))
  segment_cache = {}
  vim.schedule(function()
    pcall(vim.cmd, 'redrawstatus')
  end)
  pump()
end

--[[ Conversions stay off the redraw path: the footer shows the glyph until
the raster exists, and the redraw in settle() swaps the image in. ]]
pump = function()
  while running < 4 and #queue > 0 do
    local job = table.remove(queue, 1)
    local command = argv(job.role, job.png, job.color)
    if not command then
      queued[job.png] = nil
      failed[job.png] = 'unable to prepare ' .. registry[job.role].svg .. '.svg'
    else
      running = running + 1
      vim.system(command, { text = true }, function(result)
        vim.schedule(function()
          local err = ''
          if result.code ~= 0 or not uv.fs_stat(job.png) then
            err = vim.trim(result.stderr or result.stdout or '') or ''
            err = err == '' and 'icon conversion failed' or err
          end
          settle(job.png, err)
        end)
      end)
    end
  end
end

--[[ Cached raster for this role and tint, queueing the conversion when it is
missing. nil means "not ready yet, draw the glyph". ]]
local function request(role, color)
  local png = target(role, color)
  if ready[png] then
    return png
  end
  if failed[png] or queued[png] then
    return nil
  end
  if uv.fs_stat(png) then
    ready[png] = true
    return png
  end
  queued[png] = true
  queue[#queue + 1] = { role = role, color = color, png = png }
  pump()
  return nil
end

--[[ Icons only start rasterising once startup is over. Anything the footer
paints before that is tinted with pre-colorscheme defaults, so the glyphs stay
until the tints are real. ]]
local function images()
  if vim.v.vim_did_enter == 0 then
    return false
  end
  if capability == nil then
    local ok, backend = pcall(require, 'real-icons.backend.kitty')
    capability = ok and converter() ~= nil and vim.o.termguicolors and backend.supports_terminal() == true
  end
  return capability
end

local function image_segment(png)
  local ok, renderer = pcall(require, 'real-icons.render.placeholder')
  if not ok then
    return nil
  end
  local settings = size()
  local icon = { pack = 'product', key = png, source = png, asset = png }
  local success, segment = pcall(renderer.segment, icon, { cols = settings.cols, size = settings, color = false })
  if not success or type(segment) ~= 'table' or segment.source ~= 'image' then
    return nil
  end
  return { text = segment.text, hl = segment.hl, width = segment.width, image = true }
end

--[[ Segment for one role: an image while its raster is ready, the glyph
otherwise. `opts.group` overrides the tint group, `opts.restore` the group the
statusline returns to after the icon. ]]
function M.segment(role, opts)
  opts = opts or {}
  local icon = registry[role]
  if not icon then
    return nil
  end

  local group = opts.group or icon.group
  local restore = opts.restore or group
  local key = table.concat({ role, group, restore }, '|')
  if segment_cache[key] then
    return segment_cache[key]
  end

  local segment
  if images() then
    local png = request(role, tint(group))
    if png then
      segment = image_segment(png)
    end
  end

  if not segment then
    segment = { text = icon.glyph, hl = group, width = vim.fn.strdisplaywidth(icon.glyph), image = false }
  end
  segment.group = group
  segment.restore = restore
  if segment.text == '' then
    segment.statusline = ''
  else
    segment.statusline = string.format('%%#%s#%s%%#%s#', segment.hl, segment.text, restore)
  end

  segment_cache[key] = segment
  return segment
end

--[[ Statusline/winbar string for one role, already wrapped in its highlights.
Empty when the role has neither image nor glyph, so callers can concatenate
it unconditionally. ]]
function M.statusline(role, opts)
  local segment = M.segment(role, opts)
  return segment and segment.statusline or ''
end

---Nerd Font glyph for `role`, for callers that never want an image.
function M.glyph(role)
  local icon = registry[role]
  return icon and icon.glyph or ''
end

---Every known role, sorted.
function M.roles()
  return vim.deepcopy(roles)
end

---Carbon icon name behind `role`, i.e. the stem of its vendored SVG.
function M.source(role)
  local icon = registry[role]
  return icon and icon.svg or nil
end

--[[ Scratch window listing every role next to its Carbon source, so the set
can be eyeballed against the current colorscheme. ]]
function M.preview()
  local lines = {}
  for index, role in ipairs(roles) do
    lines[index] = string.rep(' ', 6) .. '  ' .. role .. '  (' .. registry[role].svg .. ')'
  end

  local buffer = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
  vim.bo[buffer].buftype = 'nofile'
  vim.bo[buffer].bufhidden = 'wipe'
  vim.bo[buffer].filetype = 'product-icons'

  local namespace = vim.api.nvim_create_namespace 'ProductIconsPreview'
  for index, role in ipairs(roles) do
    local segment = M.segment(role)
    if segment and segment.text ~= '' then
      vim.api.nvim_buf_set_extmark(buffer, namespace, index - 1, 0, {
        virt_text = { { segment.text .. ' ', segment.hl } },
        virt_text_pos = 'inline',
      })
    end
  end

  vim.cmd 'split'
  vim.api.nvim_win_set_buf(0, buffer)
  vim.bo[buffer].modifiable = false
end

--[[ A new colorscheme, background, or termguicolors means new tints, so drop
the segment cache. The next paint asks for rasters in the new colours, and a
role the footer never shows never pays for one. ]]
local function invalidate()
  capability = nil
  segment_cache = {}
end

local group = vim.api.nvim_create_augroup('ProductIcons', { clear = true })
vim.api.nvim_create_autocmd('ColorScheme', { group = group, callback = invalidate })
vim.api.nvim_create_autocmd('OptionSet', {
  group = group,
  pattern = { 'background', 'termguicolors' },
  callback = invalidate,
})

require('cmdr').add {
  {
    desc = 'Preview product icons',
    cmd = M.preview,
    cat = 'icons',
  },
}

return M
