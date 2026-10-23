local M = {}

local recent_file = vim.fn.stdpath 'data' .. '/cmdr_recent.json'
local recent = {}

local function load_recent()
  local f = io.open(recent_file, 'r')
  if not f then
    return
  end
  local ok, data = pcall(vim.json.decode, f:read '*a')
  f:close()
  if ok and type(data) == 'table' then
    recent = data
  end
end

local function save_recent()
  local f = io.open(recent_file, 'w')
  if not f then
    return
  end
  f:write(vim.json.encode(recent))
  f:close()
end

local commands = {}

local function command_id(cmd)
  return (cmd.desc or '') .. '\0' .. (cmd.cmd_str or '')
end

local function command_str(cmd)
  return type(cmd.cmd) == 'function' and '<function>' or cmd.cmd
end

local function normalize_keys(keys)
  if type(keys) == 'string' then
    return { { 'n', keys } }
  end

  if type(keys) ~= 'table' then
    return {}
  end

  if keys.lhs or (type(keys[1]) == 'string' and type(keys[2]) == 'string') then
    return { { keys.mode or keys[1], keys.lhs or keys[2] } }
  end

  local result = {}
  for _, key in ipairs(keys) do
    if type(key) == 'string' then
      table.insert(result, { 'n', key })
    else
      table.insert(result, { key.mode or key[1] or 'n', key.lhs or key[2] })
    end
  end
  return result
end

function M.add(items)
  for _, item in ipairs(items) do
    if item.cmd then
      local cmd = {
        desc = item.desc or '',
        cmd = item.cmd,
        cmd_str = command_str(item),
        cat = item.cat or '',
      }

      local keymap_strs = {}
      for _, keymap in ipairs(normalize_keys(item.keys)) do
        local mode, lhs = keymap[1], keymap[2]
        if lhs then
          vim.keymap.set(mode, lhs, cmd.cmd, { desc = cmd.desc, silent = true })
          table.insert(keymap_strs, mode .. ' ' .. lhs)
        end
      end
      cmd.keys_str = table.concat(keymap_strs, ' ')

      --[[ Snacks matches on `text`; without it every keystroke filters the list to nothing. ]]
      cmd.text = cmd.desc
      table.insert(commands, cmd)
    else
      vim.notify('cmdr: missing cmd in ' .. vim.inspect(item), vim.log.levels.WARN)
    end
  end
end

local function sorted_commands()
  local sorted = vim.deepcopy(commands)
  table.sort(sorted, function(a, b)
    local ra = recent[command_id(a)] or 0
    local rb = recent[command_id(b)] or 0
    if ra ~= rb then
      return ra > rb
    end
    return a.desc < b.desc
  end)
  return sorted
end

local function show(items)
  local widths = { desc = 0, keys = 0 }
  for _, cmd in ipairs(items) do
    widths.desc = math.max(widths.desc, #cmd.desc)
    widths.keys = math.max(widths.keys, #(cmd.keys_str or ''))
  end

  local function pad(text, width)
    return text .. string.rep(' ', math.max(width - #text, 0))
  end

  Snacks.picker.pick {
    source = 'cmdr',
    title = 'Cmdr',
    items = items,
    --[[ Dropdown without the preset's preview pane: commands have no previewable content. ]]
    layout = { preset = 'dropdown', preview = false },
    format = function(item)
      return {
        { pad(item.desc, widths.desc) .. '  ' },
        { pad(item.keys_str or '', widths.keys) .. '  ', 'Comment' },
        { item.cat, 'Special' },
      }
    end,
    confirm = function(picker, item)
      picker:close()
      if not item then
        return
      end
      M.mark_used(item)
      if type(item.cmd) == 'function' then
        item.cmd()
      else
        local keys = vim.api.nvim_replace_termcodes(item.cmd, true, false, true)
        vim.api.nvim_feedkeys(keys, 't', true)
      end
    end,
  }
end

function M.show()
  if #commands == 0 then
    vim.notify('cmdr: no commands registered', vim.log.levels.INFO)
    return
  end

  show(sorted_commands())
end

function M.mark_used(cmd)
  recent[command_id(cmd)] = os.time()
  save_recent()
end

-- Backwards-compatible alias for legacy commander callers
package.loaded['commander'] = M

load_recent()

return M
