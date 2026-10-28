--[[ Catppuccin Icons, loaded straight from the VS Code extension.

real-icons discovers any installed VS Code icon theme, so the Catppuccin
extension needs no adapter: its four flavours show up as packs named
"Catppuccin <Flavour>". All we add is the light/dark pairing.

Icons render through the Kitty Graphics Protocol. Herdr wipes the outer
terminal identity from every pane (TERM_PROGRAM=herdr, no KITTY_WINDOW_ID), so
real-icons cannot auto-detect images there and would fall back to glyphs. ]]
local herdr = vim.env.HERDR_ENV == '1' or vim.env.TERM_PROGRAM == 'herdr'

local function backend()
  return herdr and 'kitty' or 'auto'
end

--[[ Icons paint into ~2 cells. Catppuccin draws 1.5px strokes at 16x16, so a
source larger than the space it is drawn into gets downsampled by the
terminal's GPU filter and the strokes fray. 48px covers 2 cells at font_size 16
on a retina display with headroom. ]]
local pixels = 48

local flavour = { light = 'Catppuccin Latte', dark = 'Catppuccin Mocha' }

--[[ Pack spec for the flavour matching `background`, or nil when the VS Code
extension is not installed. discover_packs() registers what it returns, so the
name is usable by use_pack() straight away. ]]
local function catppuccin_pack(background)
  local wanted = flavour[background] or flavour.dark
  for _, candidate in ipairs(require('real-icons').discover_packs()) do
    if candidate.label == wanted then
      return candidate.name
    end
  end
end

return {
  'kvoon3/real-icons.nvim',
  branch = 'fix/png-resize',
  lazy = false,
  dependencies = { 'nvim-mini/mini.icons' },
  opts = {
    backend = backend(),
    size = { pixels = pixels },
    integrations = {
      snacks_picker = true,
    },
  },
  config = function(_, opts)
    local icons = require 'real-icons'
    icons.setup(opts)

    local function apply(background)
      local pack = catppuccin_pack(background)
      if pack and icons.pack() ~= pack then
        icons.use_pack(pack, { notify = false })
      end
    end

    apply(vim.o.background)
    vim.api.nvim_create_autocmd('OptionSet', {
      pattern = 'background',
      callback = function()
        apply(vim.o.background)
      end,
    })

    require('cmdr').add {
      {
        desc = 'Choose file icon pack',
        cmd = function()
          icons.select_pack()
        end,
        cat = 'icons',
      },
      {
        desc = 'Preview file icons',
        cmd = function()
          icons.demo()
        end,
        cat = 'icons',
      },
      {
        desc = 'Check icon setup',
        cmd = function()
          vim.cmd 'checkhealth real-icons'
        end,
        cat = 'icons',
      },
    }
  end,
}
