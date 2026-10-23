--[[ Split a `0xRRGGBB` color into its red, green, and blue channels. ]]
local function rgb(color)
  return math.floor(color / 65536) % 256, math.floor(color / 256) % 256, color % 256
end

--[[ Blend `accent` over `base` by `alpha` (0..1) into a `#rrggbb` color. ]]
local function tint(accent, base, alpha)
  local ar, ag, ab = rgb(accent)
  local br, bg, bb = rgb(base)

  local function blend(a, b)
    return math.floor(a * alpha + b * (1 - alpha) + 0.5)
  end

  return string.format('#%02x%02x%02x', blend(ar, br), blend(ag, bg), blend(ab, bb))
end

--[[
Per-operation accents. The tint is mixed into the active colorscheme's `Normal`
background, so the same palette stays readable on both light and dark themes.
]]
local accents = {
  UgUndo = '#e06c75',
  UgRedo = '#98c379',
  UgYank = '#e5c07b',
  UgPaste = '#56b6c2',
  UgSearch = '#c678dd',
  UgComment = '#d19a66',
  UgCursor = '#61afef',
}

--[[ Retint undo-glow's highlight groups for the active colorscheme. ]]
local function apply_colors()
  local normal = vim.api.nvim_get_hl(0, { name = 'Normal' })
  local base = normal.bg or (vim.o.background == 'light' and 0xffffff or 0x000000)
  local alpha = vim.o.background == 'light' and 0.22 or 0.3

  for group, accent in pairs(accents) do
    vim.api.nvim_set_hl(0, group, { bg = tint(tonumber(accent:sub(2), 16), base, alpha) })
  end
end

local animations_enabled = true

--[[ Configure the plugin and re-apply the theme colors it does not create itself. ]]
local function setup(animate)
  animations_enabled = animate

  require('undo-glow').setup {
    animation = {
      enabled = animate,
      duration = 250,
      animation_type = 'fade',
      window_scoped = true,
    },
  }

  apply_colors()
end

--[[
Run a glow command, except when a count was typed: `3u` / `3n` / `3*` keep the
native behavior (the plugin API always acts once).
]]
local function with_count(keys, command)
  return function()
    if vim.v.count > 0 then
      vim.cmd(('normal! %d%s'):format(vim.v.count, keys))
      return
    end

    command()
  end
end

return {
  'y3owk1n/undo-glow.nvim',
  event = 'VeryLazy',
  config = function()
    setup(true)

    vim.api.nvim_create_autocmd('ColorScheme', {
      group = vim.api.nvim_create_augroup('UndoGlowColors', { clear = true }),
      desc = 'Retint undo-glow highlights for the active colorscheme',
      callback = apply_colors,
    })

    local ug = require 'undo-glow'

    vim.keymap.set('n', 'u', with_count('u', ug.undo), { desc = 'Undo with glow' })
    --[[ Redo is `<C-r>` so the native line-undo on `U` is left intact. ]]
    vim.keymap.set('n', '<C-r>', with_count('<C-r>', ug.redo), { desc = 'Redo with glow' })

    -- Paste commands handle counts themselves.
    vim.keymap.set('n', 'p', ug.paste_below, { desc = 'Paste below with glow' })
    vim.keymap.set('n', 'P', ug.paste_above, { desc = 'Paste above with glow' })

    vim.keymap.set('n', 'n', with_count('n', ug.search_next), { desc = 'Search next with glow' })
    vim.keymap.set('n', 'N', with_count('N', ug.search_prev), { desc = 'Search prev with glow' })
    vim.keymap.set('n', '*', with_count('*', ug.search_star), { desc = 'Search word forward with glow' })
    vim.keymap.set('n', '#', with_count('#', ug.search_hash), { desc = 'Search word backward with glow' })

    -- Same shapes as Neovim's default `gc` maps (see |gc-default|), plus glow.
    vim.keymap.set({ 'n', 'x' }, 'gc', function()
      --[[ Commenting moves the cursor; restore it once the operator has run. ]]
      local pos = vim.fn.getpos '.'
      vim.schedule(function()
        vim.fn.setpos('.', pos)
      end)

      return ug.comment()
    end, { expr = true, desc = 'Toggle comment with glow' })
    vim.keymap.set('n', 'gcc', function()
      return ug.comment_line()
    end, { expr = true, desc = 'Toggle comment line with glow' })
    vim.keymap.set('o', 'gc', ug.comment_textobject, { desc = 'Comment textobject with glow' })

    vim.api.nvim_create_autocmd('TextYankPost', {
      group = vim.api.nvim_create_augroup('UndoGlowYank', { clear = true }),
      desc = 'Highlight yanked text with glow',
      callback = function()
        ug.yank()
      end,
    })

    vim.api.nvim_create_autocmd('CmdlineLeave', {
      group = vim.api.nvim_create_augroup('UndoGlowSearch', { clear = true }),
      desc = 'Highlight the match after a search command',
      callback = function()
        ug.search_cmd()
      end,
    })

    require('cmdr').add {
      {
        desc = 'Toggle undo-glow animations',
        cmd = function()
          setup(not animations_enabled)
          vim.notify('undo-glow animations ' .. (animations_enabled and 'enabled' or 'disabled'))
        end,
        cat = 'edit',
      },
      {
        desc = 'Check undo-glow health',
        cmd = '<CMD>checkhealth undo-glow<CR>',
        cat = 'edit',
      },
    }
  end,
}
