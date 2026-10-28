--[[ The animated feedback engine behind glow.lua.

Two styles share one diagonal wave:

• `fade_in` — the text starts invisible and its own color arrives band by band,
  so it reads as the text appearing. Used for pasted and restored text.
• `flash` — the region starts tinted with an accent and the tint leaves band by
  band. Used for undo, redo, yank, search, and comments, where the text was
  already there and only needs a pointer.

Both run from the region's top-left corner to its bottom-right one, and both keep
the front narrow on purpose: the wave has to read as a sweep, not as a fade.

The wave is cheap by construction: the cells are grouped into a fixed number of
bands along the diagonal, one highlight group per band, and each frame only
rewrites those groups. The extmarks are placed once and removed when the wave
ends, so nothing is left behind on the text.
]]

local M = {}

local namespace = vim.api.nvim_create_namespace 'wave'

--[[
The wave travels at a constant speed rather than finishing in a fixed time:
`sweep` is how long it takes to cross one row, and a row's width counts an eighth
of a row per column, so a long paste keeps sweeping instead of whipping past in
the same quarter second as a one-line one. `min_sweep` gives a tiny region enough
travel to read as a sweep at all.

`fade_share` is the part of the sweep one band spends changing color. It has to
stay well under one: at `1` every band fades at the same time and the diagonal
disappears into a plain fade, which is exactly what makes the direction obvious
or invisible. `max_duration` bounds the whole thing.
]]
local defaults = {
  sweep = 10,
  min_sweep = 120,
  fade_share = 0.35,
  max_duration = 800,
  fps = 60,
  bands = 32,
  max_lines = 120,
  max_bytes = 12000,
  priority = 4096,
}

--[[ How much of an accent a flash mixes into the theme background (opaque themes)
or into the text color (transparent themes), so the same palette stays readable
on light and dark themes. ]]
local tint_strength = { dark = 0.3, light = 0.22 }
local text_strength = 0.8

local config = vim.deepcopy(defaults)
local enabled = true
local animation = nil

local function clamp(value, low, high)
  return math.min(high, math.max(low, value))
end

--[[ Blend two `0xRRGGBB` colors: 0 keeps `base`, 1 takes `accent`. ]]
local function blend(accent, base, alpha)
  local function channel(shift)
    local from = math.floor(base / shift) % 256
    local to = math.floor(accent / shift) % 256
    return math.floor(to * alpha + from * (1 - alpha) + 0.5)
  end

  return channel(0x10000) * 0x10000 + channel(0x100) * 0x100 + channel(1)
end

--[[ First byte index at or after `from` that begins a UTF-8 character. ]]
local function char_start(line, from)
  local index = from
  while index < #line do
    local byte = line:byte(index + 1)
    if byte < 0x80 or byte >= 0xC0 then
      return index
    end
    index = index + 1
  end

  return index
end

--[[
Split one row span into extmark-sized slices. `from` and `to` are byte columns
into `line`; a slice boundary never falls inside a multibyte character.
]]
function M.slices(line, from, to, width)
  local slices = {}
  local index = from

  while index < to do
    local stop = math.min(char_start(line, math.min(index + width, to)), to)
    if stop <= index then
      stop = to
    end
    slices[#slices + 1] = { from = index, to = stop }
    index = stop
  end

  return slices
end

--[[
Per-row byte spans of a region. `shape` comes from the register or the operator:
`line` covers whole lines, `block` a rectangle, and `char` funnels out of
`first` on the opening row and back into `last` on the closing one.
]]
function M.spans(shape, first, last, lengths)
  local count = #lengths
  local spans = {}

  for index = 1, count do
    local length = lengths[index]
    local from, to = 0, length

    if shape == 'block' then
      from, to = math.min(first, last), math.max(first, last)
    elseif shape == 'char' then
      from, to = first, last
      if count > 1 and index == 1 then
        to = length
      elseif count > 1 and index == count then
        from = 0
      elseif count > 1 then
        from, to = 0, length
      end
    end

    spans[index] = { from = clamp(from, 0, length), to = clamp(to, 0, length) }
  end

  return spans
end

--[[
Where a cell sits on the diagonal: 0 at the region's top-left corner, 1 at its
bottom-right corner. Rows and columns are normalized separately, so the wave
still crosses the whole region whether it is wide, tall, or square.
]]
function M.progress(row, rows, column, span)
  local vertical = rows > 1 and (row - 1) / (rows - 1) or 0
  local horizontal = span > 0 and column / span or 0
  local extent = (rows > 1 and 1 or 0) + (span > 0 and 1 or 0)

  if extent == 0 then
    return 0
  end

  return (vertical + horizontal) / extent
end

--[[ Band 1..`bands` for a diagonal position; one highlight group covers a band. ]]
function M.band(progress, bands)
  return clamp(math.floor(progress * bands) + 1, 1, bands)
end

--[[ When a band starts, in milliseconds into the sweep. ]]
function M.delay(band, bands, stagger)
  if bands < 2 then
    return 0
  end

  return (band - 1) / (bands - 1) * stagger
end

--[[
Opacity of a band at `elapsed` ms: 0 invisible, 1 fully drawn. Smoothstep rather
than a linear ramp, so the travelling front stays soft and shows no band edges.
]]
function M.opacity(elapsed, delay, fade)
  local raw = clamp((elapsed - delay) / fade, 0, 1)
  return raw * raw * (3 - 2 * raw)
end

--[[
Extmark specs for one region: slice every row, then bucket the slices by their
position on the diagonal. One slice per band crossing keeps the work
proportional to the bands instead of to the text — a 200-column row needs about
13 slices, not 33. Rows come from `M.rows` and carry their absolute buffer row,
so planning stays independent of where the region starts.
]]
function M.plan(rows, bands)
  local span = 0
  for _, row in ipairs(rows) do
    span = math.max(span, row.to - row.from)
  end

  local extent = (span > 0 and 1 or 0) + (#rows > 1 and 1 or 0)
  local width = math.max(1, math.ceil(span * extent / math.max(1, bands - 1)))

  local marks = {}
  for index, row in ipairs(rows) do
    for _, slice in ipairs(M.slices(row.line, row.from, row.to, width)) do
      local centre = (slice.from + slice.to) / 2 - row.from
      marks[#marks + 1] = {
        row = row.row,
        from = slice.from,
        to = slice.to,
        band = M.band(M.progress(index, #rows, centre, span), bands),
      }
    end
  end

  return marks
end

--[[
Text color, the background behind it (`nil` when the theme is transparent), and
`accent` mixed into whichever of the two the wave will animate. A transparent
theme has no background to move, so there the accent is mixed into the text
instead — inventing a background would paint a block the theme never had.
]]
local function palette(accent)
  local normal = vim.api.nvim_get_hl(0, { name = 'Normal' })
  local light = vim.o.background == 'light'
  local fallback = light and 0xffffff or 0x000000
  local background = normal.bg
  local foreground = normal.fg or (light and 0x000000 or 0xffffff)
  local strength = tint_strength[light and 'light' or 'dark']
  local base = background or fallback

  return {
    foreground = foreground,
    background = background,
    fallback = fallback,
    tint = blend(accent or base, base, strength),
  }
end

--[[ Drop the sweep from the screen: stop its timer, marks, and band groups. ]]
function M.stop()
  local current = animation
  if not current then
    return
  end

  animation = nil
  current.timer:stop()
  if not current.timer:is_closing() then
    current.timer:close()
  end

  if vim.api.nvim_buf_is_valid(current.buf) then
    vim.api.nvim_buf_clear_namespace(current.buf, namespace, 0, -1)
  end

  for _, group in ipairs(current.groups) do
    vim.api.nvim_set_hl(0, group, {})
  end
end

--[[
Sweep length for a region, from how far the wave has to travel: rows cost
`sweep` milliseconds each, and the widest row adds an eighth of that per column
because the wave moves sideways while it moves down. The band fade is a share of
that travel, so the front keeps the same width on a paragraph and on a whole
screen; only the ceiling ever has to compress it.
]]
function M.timing(rows)
  local span = 0
  for _, row in ipairs(rows) do
    span = math.max(span, row.to - row.from)
  end

  local stagger = math.max(config.min_sweep, (#rows + span / 8) * config.sweep)
  local fade = clamp(stagger * config.fade_share, 25, 200)
  if stagger + fade > config.max_duration then
    stagger = math.max(1, config.max_duration - fade)
  end

  return math.max(1, math.floor(stagger + fade)), math.max(1, math.floor(fade))
end

--[[
Repaint the band groups for `elapsed` ms, moving each band from `start_color`
towards `end_color` as the wave passes it. Fade-ins paint the text channel (and
the theme background under it when there is one); flashes paint the background
on an opaque theme and the text itself on a transparent one, where a background
band would be a block the theme never had.
]]
local function paint(current, elapsed)
  for band = 1, #current.groups do
    local progress = M.opacity(elapsed, current.delays[band], current.fade)
    local color = blend(current.end_color, current.start_color, progress)

    if color ~= current.painted[band] then
      current.painted[band] = color
      local hl = current.channel == 'fg' and { fg = ('#%06x'):format(color) } or { bg = ('#%06x'):format(color) }
      if current.keep_bg then
        hl.bg = ('#%06x'):format(current.background)
      end
      vim.api.nvim_set_hl(0, current.groups[band], hl)
    end
  end
end

--[[ Build the state of one sweep: which channel animates, and between which colors. ]]
local function configure(mode, colors, accent, duration, fade)
  local stagger = math.max(1, duration - fade)
  local current = {
    buf = vim.api.nvim_get_current_buf(),
    mode = mode,
    duration = duration,
    fade = fade,
    groups = {},
    delays = {},
    painted = {},
    background = colors.background or colors.fallback,
    started = vim.uv.hrtime(),
    timer = assert(vim.uv.new_timer()),
  }

  if mode == 'fade_in' then
    current.start_color = colors.background or colors.fallback
    current.end_color = colors.foreground
    current.channel = 'fg'
    current.keep_bg = colors.background ~= nil
  else
    current.start_color = colors.background and colors.tint
      or blend(accent or colors.foreground, colors.foreground, text_strength)
    current.end_color = colors.background or colors.foreground
    current.channel = colors.background and 'bg' or 'fg'
    current.keep_bg = false
  end

  for band = 1, config.bands do
    current.groups[band] = 'WaveBand' .. band
    current.delays[band] = M.delay(band, config.bands, stagger)
  end

  return current
end

--[[ Drive `current` until the sweep ends, then clean up after it. ]]
local function start_timer(current)
  current.timer:start(
    0,
    math.max(1, math.floor(1000 / config.fps)),
    vim.schedule_wrap(function()
      if animation ~= current then
        return
      end

      local elapsed = (vim.uv.hrtime() - current.started) / 1e6
      if elapsed >= current.duration then
        M.stop()
        return
      end

      paint(current, elapsed)
    end)
  )
end

--[[
Run `mode` over `rect` (see `M.rows`), replacing whatever sweep is on screen.
Every band is painted at its starting color before the extmarks go down, so the
region never flashes at the wrong opacity for a frame.
]]
local function play(mode, rect, accent)
  M.stop()
  if not enabled or not rect then
    return
  end

  local rows = M.rows(rect)
  if not rows then
    return
  end

  local duration, fade = M.timing(rows)
  local current = configure(mode, palette(accent), accent, duration, fade)

  animation = current
  paint(current, 0)
  for _, mark in ipairs(M.plan(rows, config.bands)) do
    vim.api.nvim_buf_set_extmark(current.buf, namespace, mark.row, mark.from, {
      end_row = mark.row,
      end_col = mark.to,
      hl_group = current.groups[mark.band],
      priority = config.priority,
    })
  end

  start_timer(current)
end

--[[ First and last buffer row (0-based) the current window shows. ]]
local function visible(buf)
  if vim.api.nvim_get_current_buf() ~= buf then
    return 0, vim.api.nvim_buf_line_count(buf) - 1
  end

  return vim.fn.line 'w0' - 1, vim.fn.line 'w$' - 1
end

--[[
The spans that are on screen and actually hold text, paired with their absolute
buffer row. Empty rows have nothing to fade and would only add zero-width
slices.
]]
local function on_screen(top, lines, spans)
  local first, last = visible(vim.api.nvim_get_current_buf())
  local rows = {}

  for index, span in ipairs(spans) do
    local row = top + index - 1
    if row >= first and row <= last and span.to > span.from then
      rows[#rows + 1] = { row = row, line = lines[index], from = span.from, to = span.to }
    end
  end

  return rows
end

--[[
Rows of `rect` that are worth animating, or nil. Oversized regions are skipped
whole: a wave over hundreds of lines only spends frames on text that scrolls
straight off screen. `max_bytes` measures UTF-8 bytes rather than characters,
which over-counts CJK — but it is also the unit the extmark slicing works in, so
it bounds the real cost, and skipping only ever means "no animation".
]]
function M.rows(rect)
  local top, bottom = rect.top, rect.bottom
  if top < 0 or bottom < top or bottom - top + 1 > config.max_lines then
    return nil
  end

  local lines = vim.api.nvim_buf_get_lines(0, top, bottom + 1, false)
  local lengths = {}
  for index, line in ipairs(lines) do
    lengths[index] = #line
  end

  local spans = M.spans(rect.shape, rect.first or 0, rect.last or 0, lengths)
  local cells = 0
  for _, span in ipairs(spans) do
    cells = cells + span.to - span.from
  end
  if cells <= 0 or cells > config.max_bytes then
    return nil
  end

  local rows = on_screen(top, lines, spans)
  return #rows > 0 and rows or nil
end

--[[
The region `'['` and `']'` describe, or nil when they are unset. `']'` gives the
last changed byte, hence the exclusive end; Vim fills it with `MAXCOL` for
linewise regions, which `M.spans` clamps back to the end of the line.
]]
function M.marked(shape)
  local open, close = vim.fn.getpos "'[", vim.fn.getpos "']"
  if open[2] < 1 or close[2] < 1 then
    return nil
  end

  return { top = open[2] - 1, bottom = close[2] - 1, first = open[3] - 1, last = close[3], shape = shape }
end

--[[ Fade a newly inserted region in from the background color. ]]
function M.fade_in(rect)
  play('fade_in', rect)
end

--[[ Tint `rect` with `accent` and let the tint leave along the wave. ]]
function M.flash(rect, accent)
  play('flash', rect, accent)
end

--[[ Turn the waves on or off; the operations they decorate keep working either way. ]]
function M.set_enabled(value)
  enabled = value and true or false
  if not enabled then
    M.stop()
  end
end

function M.is_enabled()
  return enabled
end

function M.is_running()
  return animation ~= nil
end

--[[ Configure the engine and hook its cleanup into buffer and session teardown. ]]
function M.setup(opts)
  config = vim.tbl_deep_extend('force', vim.deepcopy(defaults), opts or {})
  config.sweep = math.max(0, config.sweep)
  config.min_sweep = math.max(1, config.min_sweep)
  config.fade_share = clamp(config.fade_share, 0.05, 1)
  config.max_duration = math.max(config.min_sweep + 1, config.max_duration)
  config.bands = math.max(1, config.bands)

  local group = vim.api.nvim_create_augroup('Wave', { clear = true })
  vim.api.nvim_create_autocmd({ 'BufDelete', 'BufWipeout' }, {
    group = group,
    desc = 'Forget a wave whose buffer is being dropped',
    callback = function(ev)
      if animation and animation.buf == ev.buf then
        M.stop()
      end
    end,
  })
  vim.api.nvim_create_autocmd('VimLeavePre', {
    group = group,
    desc = 'Stop a wave before quitting',
    callback = function()
      M.stop()
    end,
  })
end

return M
