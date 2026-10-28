--[[ Animated feedback of our own for edits.

Paste fades its text in, because the text is new: revealing it shows where it
landed, and a paste that restores text (undo of a delete, redo of an insert)
fades in the same way. Yank, search, and comment flash a tint that leaves along
the same diagonal, because there the text only needs a pointer. All of it comes
from wave.lua.

Each operation has to answer one question — which bytes did it touch — and the
answer comes from the cheapest source that is exact:

• `p`, `P`, `gp`, `gP` — `:normal!` runs the put, so counts, registers,
  `.`-repeat and its refusal messages stay native; `'['`/`']'` plus the register
  type describe the inserted region. The expression register cannot be replayed
  that way, so `put_expression` evaluates it instead.
• `u`, `<C-r>` — `:undo`/`:redo` once per count; Vim points `'['`/`']'` at the
  lines it brought back or took away, and the buffer's size says which of the
  two happened.
• `n`, `N`, `*`, `#`, `/`, `?` — the match under the cursor, measured with
  `searchpos()` so real patterns resolve.
• `gc`, `gcc` — `g@` hands our own `operatorfunc` the exact range, and
  `vim._comment` toggles that same range.
• yanks — `'['`/`']'` and the register type again, from `TextYankPost`.
]]

local wave = require 'wave'

local M = {}

--[[ One accent per operation; wave mixes it into the theme background. ]]
local accents = {
  undo = 0xe06c75,
  redo = 0x98c379,
  yank = 0xe5c07b,
  search = 0xc678dd,
  comment = 0xd19a66,
}

local shapes = { v = 'char', V = 'line', ['\22'] = 'block' }

--[[ Shape of what a register holds, from `getregtype()`. ]]
local function shape_of(register)
  local kind = vim.fn.getregtype(register == '' and '"' or register):sub(1, 1)
  return shapes[kind]
end

--[[ The cursor's line as a whole-line region. ]]
local function cursor_line()
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  return { top = row, bottom = row, shape = 'line' }
end

--[[ The keys typed before the map: an optional count and register. ]]
local function native_keys(keys)
  local pieces = {}
  if vim.v.count > 0 then
    pieces[#pieces + 1] = tostring(vim.v.count)
  end

  local register = vim.v.register
  if register ~= '' and register ~= '"' and register:match '^[%w*+_%-:%.%%#/]$' then
    pieces[#pieces + 1] = '"' .. register
  end

  pieces[#pieces + 1] = keys
  return table.concat(pieces)
end

--[[
Re-emit a Vim failure as Vim would, without the Lua traceback around it.
Everything that can refuse here — `E21` in an unmodifiable buffer, `E353` for an
empty register — raises through `pcall`, and swallowing those would make a
refused operation look like a silent no-op.
]]
local function report(err)
  local text = tostring(err)
  vim.api.nvim_err_writeln(text:match 'Vim%(%w+%):(.*)' or text:match 'Vim:(E%d+:.*)' or text)
end

--[[
Run the built-in put. A refused put leaves the change marks alone, hence the
success flag: nothing was pasted, so nothing should fade.
]]
local function put(keys)
  local ok, err = pcall(vim.cmd, 'normal! ' .. native_keys(keys))
  if not ok then
    report(err)
    return false
  end

  return true
end

--[[
The expression register is the one prefix that cannot be replayed as `"=p`: the
prefix would read the expression again and prompt. Evaluate it once and put the
result where the typed key would have. An API put sets no change marks, so this
path pastes without a fade.
]]
function M.put_expression(keys)
  local ok, value = pcall(vim.fn.getreg, '=')
  if not ok then
    report(value)
    return
  end

  local linewise = vim.fn.getregtype('='):sub(1, 1) == 'V'
  vim.api.nvim_put(
    vim.split(value, '\n', { plain = true }),
    linewise and 'l' or 'c',
    keys == 'p' or keys == 'gp',
    keys == 'p' or keys == 'P'
  )
end

--[[ Insert `keys` through the built-in put, then fade the pasted text in. ]]
function M.paste(keys)
  if vim.v.register == '=' then
    return M.put_expression(keys)
  end

  local shape = shape_of(vim.v.register)
  if not put(keys) then
    return
  end

  wave.fade_in(shape and wave.marked(shape) or nil)
end

--[[
Shape of the region `'['`/`']'` describe: whole lines unless the marks carry real
columns. Vim fills the closing column with `MAXCOL` for linewise regions and
leaves it at 1 for the linewise end of a change.
]]
local function marked_shape()
  local open, close = vim.fn.getpos "'[", vim.fn.getpos "']"
  local linewise = open[3] <= 1 and (close[3] <= 1 or close[3] == 2147483647)
  return linewise and 'line' or 'char'
end

--[[ Total byte size of `buf`, which is O(1) and tells an insert from a removal. ]]
local function buffer_bytes(buf)
  return vim.api.nvim_buf_get_offset(buf, vim.api.nvim_buf_line_count(buf))
end

--[[
`direction` is `undo` or `redo`, applied once per count. Both print their own
progress messages, so they stay loud; the changed-tick check keeps a no-op at
either end of the history from flashing a stale region. Restored text fades in
like a paste; anything else gets the pointer flash.
]]
local function history(direction, accent)
  local buf = vim.api.nvim_get_current_buf()
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  local size = buffer_bytes(buf)
  local count = vim.v.count > 0 and vim.v.count or 1

  for _ = 1, count do
    local before = vim.api.nvim_buf_get_changedtick(buf)
    local ok, err = pcall(vim.cmd, direction)
    if not ok then
      report(err)
      return
    end
    if vim.api.nvim_buf_get_changedtick(buf) == before then
      break
    end
  end

  if vim.api.nvim_buf_get_changedtick(buf) == tick then
    return
  end

  local region = wave.marked(marked_shape()) or cursor_line()
  if buffer_bytes(buf) > size then
    wave.fade_in(region)
    return
  end

  wave.flash(region, accent)
end

function M.undo()
  history('undo', accents.undo)
end

function M.redo()
  history('redo', accents.redo)
end

--[[
The match under the cursor, or nil when the search pattern does not resolve
there. `searchpos()` with `c`/`e`/`n`/`W` asks Vim for the end of the match
starting at the cursor without moving it, so `\zs`, `\d\+` and friends measure
correctly.
]]
local function match_rect()
  local pattern = vim.fn.getreg '/'
  if pattern == '' then
    return nil
  end

  local stop = vim.fn.searchpos(pattern, 'cneW')
  if stop[1] == 0 then
    return nil
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  return { top = cursor[1] - 1, bottom = stop[1] - 1, first = cursor[2], last = stop[2], shape = 'char' }
end

--[[ `n`, `N`, `*`, `#`: run the command, then flash the match it lands on. ]]
local function jump(keys)
  local count = vim.v.count > 0 and tostring(vim.v.count) or ''
  if not pcall(vim.cmd, 'normal! ' .. count .. keys) then
    return
  end

  wave.flash(match_rect() or cursor_line(), accents.search)
end

function M.next()
  jump 'n'
end

function M.prev()
  jump 'N'
end

function M.star()
  jump '*'
end

function M.hash()
  jump '#'
end

--[[
`/` and `?` land on a match too. Scheduled rather than timed off `CmdlineLeave`
so the jump has already happened when the match is measured.
]]
function M.search()
  local kind = vim.fn.getcmdtype()
  if kind ~= '/' and kind ~= '?' then
    return
  end

  vim.schedule(function()
    wave.flash(match_rect(), accents.search)
  end)
end

--[[
Flash what was just yanked, in the shape of the register it filled.
`TextYankPost` also fires for deletes and changes, but those already show their
own work by taking text away, so only `y` is worth a pointer.
]]
function M.yank()
  if vim.v.event.operator ~= 'y' then
    return
  end

  wave.flash(wave.marked(shape_of(vim.v.event.regname or '')) or cursor_line(), accents.yank)
end

--[[
`operatorfunc` for `gc`: `g@` has already set `'['`/`']'` to the operated range,
and `vim._comment.operator` toggles exactly that range and preserves the marks,
so the region is known and the flash can follow the toggle. Commenting always
works on whole lines, whatever the range looked like.
]]
function M.comment(mode)
  local rect = wave.marked 'line'
  require('vim._comment').operator(mode)
  wave.flash(rect or cursor_line(), accents.comment)
end

--[[ Take over `gc` so the operator range reaches `M.comment` as operatorfunc. ]]
local function comment_map(motion)
  vim.o.operatorfunc = "v:lua.require'glow'.comment"
  return 'g@' .. motion
end

--[[ Install the maps, the autocmds, and the palette entries. ]]
function M.setup(opts)
  wave.setup(opts)

  local function map_put(keys, description)
    vim.keymap.set('n', keys, function()
      M.paste(keys)
    end, { desc = description })
  end

  map_put('p', 'Paste below with a fade-in')
  map_put('P', 'Paste above with a fade-in')
  map_put('gp', 'Paste below, cursor after the text')
  map_put('gP', 'Paste above, cursor after the text')

  --[[ Redo is `<C-r>` so the native line-undo on `U` is left intact. ]]
  vim.keymap.set('n', 'u', M.undo, { desc = 'Undo with a flash' })
  vim.keymap.set('n', '<C-r>', M.redo, { desc = 'Redo with a flash' })

  vim.keymap.set('n', 'n', M.next, { desc = 'Search next with a flash' })
  vim.keymap.set('n', 'N', M.prev, { desc = 'Search prev with a flash' })
  vim.keymap.set('n', '*', M.star, { desc = 'Search word forward with a flash' })
  vim.keymap.set('n', '#', M.hash, { desc = 'Search word backward with a flash' })

  --[[ Same shapes as Neovim's default maps (see |gc-default|). The
  operator-pending map is the built-in text object with our operatorfunc in
  place, so `gcgc` flashes the block it toggles even on a fresh session. ]]
  vim.keymap.set({ 'n', 'x' }, 'gc', function()
    return comment_map ''
  end, { expr = true, desc = 'Toggle comment with a flash' })
  vim.keymap.set('n', 'gcc', function()
    return comment_map '_'
  end, { expr = true, desc = 'Toggle comment line with a flash' })
  vim.keymap.set('o', 'gc', function()
    vim.o.operatorfunc = "v:lua.require'glow'.comment"
    require('vim._comment').textobject()
  end, { desc = 'Comment the block at the cursor' })

  local group = vim.api.nvim_create_augroup('Glow', { clear = true })
  vim.api.nvim_create_autocmd('TextYankPost', {
    group = group,
    desc = 'Flash the yanked text',
    callback = M.yank,
  })
  vim.api.nvim_create_autocmd('CmdlineLeave', {
    group = group,
    desc = 'Flash the match a search landed on',
    callback = M.search,
  })

  require('cmdr').add {
    {
      desc = 'Toggle edit animations',
      cmd = function()
        wave.set_enabled(not wave.is_enabled())
        vim.notify('edit animations ' .. (wave.is_enabled() and 'enabled' or 'disabled'))
      end,
      cat = 'view',
    },
  }
end

return M
