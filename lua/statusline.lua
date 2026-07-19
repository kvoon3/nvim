local M = {}

local icons = {
  branch = '󰘬',
  ahead = '󰁝',
  behind = '󰁅',
  dirty = '●',
  explorer = '󰉋',
  terminal = '󰆍',
  finder = '󰀶',
  github = '󰊤',
}

-- test

--[[ Snacks explorer sidebar windows get a blank statusline and winbar.
With laststatus=2 the row itself cannot be removed per-window, only emptied. ]]
local disabled_filetypes = {
  snacks_picker_list = true,
  snacks_picker_input = true,
  snacks_picker_preview = true,
  snacks_layout_box = true,
}

--[[ The window the current %! evaluation belongs to; g:statusline_winid is set for both
'statusline' and 'winbar'. Falls back to the current window for direct calls. ]]
local function render_winid()
  return tonumber(vim.g.statusline_winid) or vim.api.nvim_get_current_win()
end

--[[ Focus the window whose statusline/winbar was clicked, so buffer-scoped actions
(copy path, git push, open in GitHub) operate on the clicked window. ]]
local function focus_clicked_win()
  local winid = vim.fn.getmousepos().winid
  if winid ~= 0 and vim.api.nvim_win_is_valid(winid) then
    vim.api.nvim_set_current_win(winid)
  end
end

--[[ Turn fn into a click handler that only fires on left-click.
Click handlers are called with (minwid, clicks, button, modifiers). ]]
local function on_left_click(fn)
  return function(_minwid, _clicks, button)
    if button == 'l' then
      fn()
    end
  end
end

--[[ Wrap text in a click label: clicking it calls require('statusline')[handler](). ]]
local function clickable(handler, text)
  return "%@v:lua.require'statusline'." .. handler .. '@' .. text .. '%X'
end

--[[ Toggle the Snacks file explorer: close it when it is open, open it when it is closed. ]]
local function toggle_explorer()
  local pickers = Snacks.picker.get { source = 'explorer' }
  if #pickers > 0 then
    for _, picker in ipairs(pickers) do
      picker:close()
    end
    return
  end
  Snacks.picker.explorer()
end

--[[ Return the absolute path that the current buffer represents.
For netrw, this is the directory being browsed; otherwise the current file path. ]]
local function buffer_path(buf)
  if vim.bo[buf].filetype == 'netrw' then
    return vim.b[buf].netrw_curdir
  end
  return vim.fn.expand '%:p'
end

--[[ Copy the absolute path of the current file to the system clipboard. ]]
local function copy_absolute_path()
  local path = buffer_path(vim.api.nvim_get_current_buf())
  if not path or path == '' then
    vim.notify('No file in current buffer', vim.log.levels.WARN)
    return
  end
  vim.fn.setreg('+', path)
  vim.notify('Copied: ' .. path)
end

--[[ Reveal the current file in macOS Finder. ]]
local function reveal_in_finder()
  local file = buffer_path(vim.api.nvim_get_current_buf())
  if not file or file == '' then
    vim.notify('No file in current buffer', vim.log.levels.WARN)
    return
  end
  vim.system { 'open', '-R', file }
end

M.click_explorer = on_left_click(toggle_explorer)

M.click_terminal = on_left_click(function()
  vim.cmd 'ToggleTerm'
end)

M.click_branch = on_left_click(function()
  focus_clicked_win()
  Snacks.lazygit()
  -- The click is processed in normal mode, which cancels snacks' own startinsert;
  -- re-enter terminal mode after click handling completes.
  vim.schedule(function()
    if vim.bo.buftype == 'terminal' then
      vim.cmd 'startinsert'
    end
  end)
end)

M.click_finder = on_left_click(function()
  focus_clicked_win()
  reveal_in_finder()
end)

M.click_github = on_left_click(function()
  focus_clicked_win()
  require('open-in-github').open_in_github()
end)

M.click_push = on_left_click(function()
  focus_clicked_win()
  require('git-status').push()
end)

M.click_pull = on_left_click(function()
  focus_clicked_win()
  require('git-status').pull()
end)

M.click_pull_rebase_push = on_left_click(function()
  focus_clicked_win()
  require('git-status').pull_rebase_push()
end)

--[[ Git branch and sync arrows for the left side of the footer.
Clicking the branch opens lazygit. Arrows: ahead = push, behind = pull, both = one rebase+push button. ]]
local function git_section(buf)
  local status = require('git-status').get(buf)
  if not status then
    return nil
  end
  local branch_label = status.branch and (icons.branch .. ' ' .. status.branch) or icons.branch
  local parts = { clickable('click_branch', branch_label) }
  if status.dirty then
    parts[#parts + 1] = icons.dirty
  end
  if status.upstream and status.ahead > 0 and status.behind > 0 then
    local diverged = icons.ahead .. status.ahead .. ' ' .. icons.behind .. status.behind
    parts[#parts + 1] = clickable('click_pull_rebase_push', diverged)
  elseif status.upstream and status.ahead > 0 then
    parts[#parts + 1] = clickable('click_push', icons.ahead .. status.ahead)
  elseif status.upstream and status.behind > 0 then
    parts[#parts + 1] = clickable('click_pull', icons.behind .. status.behind)
  end
  return table.concat(parts, ' ')
end

--[[ Render the winbar header: file path and flags centered. Blank for explorer windows and non-file buffers. ]]
function M.render_header()
  local buf = vim.api.nvim_win_get_buf(render_winid())
  if disabled_filetypes[vim.bo[buf].filetype] or vim.bo[buf].buftype ~= '' then
    return ''
  end
  return '%=%f %m%r%h%w %='
end

--[[ Render the footer: git branch and sync arrows on the left, cursor info and clickable
action icons on the right. Blank for explorer windows and terminal buffers. ]]
function M.render()
  local buf = vim.api.nvim_win_get_buf(render_winid())
  if disabled_filetypes[vim.bo[buf].filetype] or vim.bo[buf].buftype == 'terminal' then
    return ''
  end
  local parts = {
    git_section(buf),
    '%=',
    '[%l,%c] [%p%%] [%L lines]',
    clickable('click_explorer', ' ' .. icons.explorer .. ' '),
    clickable('click_terminal', ' ' .. icons.terminal .. ' '),
    clickable('click_finder', ' ' .. icons.finder .. ' '),
    clickable('click_github', ' ' .. icons.github .. ' '),
  }
  if not parts[1] then
    table.remove(parts, 1)
  end
  return table.concat(parts, ' ')
end

require('cmdr').add {
  {
    desc = 'Reveal current file in Finder',
    cmd = reveal_in_finder,
    cat = 'file',
  },
  {
    desc = 'Copy absolute file path',
    cmd = copy_absolute_path,
    cat = 'file',
  },
}

return M
