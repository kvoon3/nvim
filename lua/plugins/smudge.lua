-- https://github.com/indium114/smudge.nvim
local augroup = vim.api.nvim_create_augroup('SmudgeCursor', { clear = true })
local smear
local enabled = true

local function set_highlight()
  vim.api.nvim_set_hl(0, 'SmudgeCursor', { link = 'Comment' })
end

---Register the smear handler under our own augroup instead of smudge's.
---@param callback? function CursorMoved handler taken from smudge, or nil to detach
local function attach(callback)
  vim.api.nvim_clear_autocmds { group = augroup }
  if not callback then
    return
  end

  vim.api.nvim_create_autocmd('CursorMoved', { group = augroup, callback = callback })
end

---@return function?
local function take_smear()
  --[[ smudge passes an undefined `augroup` global to nvim_create_autocmd(), so its
  handler lands in the global group and smudge.disable() cannot remove it. Stealing
  the callback lets the animation toggle for real. ]]
  local taken
  for _, autocmd in ipairs(vim.api.nvim_get_autocmds { event = 'CursorMoved' }) do
    local callback = autocmd.callback
    if type(callback) == 'function' and (debug.getinfo(callback, 'S').source or ''):find('/smudge/', 1, true) then
      taken = callback
      vim.api.nvim_del_autocmd(autocmd.id)
    end
  end
  return taken
end

return {
  'indium114/smudge.nvim',
  lazy = false,
  config = function()
    local smudge = require 'smudge'

    set_highlight()
    vim.api.nvim_create_autocmd('ColorScheme', { group = augroup, callback = set_highlight })

    smudge.setup {
      char = '░',
      max_age = 80,
      length = 2,
    }

    --[[ smudge registers its autocmd behind vim.schedule(), so adopt it afterwards. ]]
    vim.schedule(function()
      smear = take_smear()
      attach(smear)
    end)

    require('cmdr').add {
      {
        desc = 'Toggle cursor smudge animation',
        cmd = function()
          enabled = not enabled
          attach(enabled and smear or nil)
          if not enabled then
            smudge.disable()
          end
        end,
        cat = 'ui',
      },
    }
  end,
}
