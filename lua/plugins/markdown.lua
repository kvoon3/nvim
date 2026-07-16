return {
  'MeanderingProgrammer/render-markdown.nvim',
  dependencies = { 'nvim-mini/mini.icons' },
  ---@module 'render-markdown'
  ---@type render.md.UserConfig
  opts = {
    -- never render in place; the rendered view only shows in the insert-mode split preview
    render_modes = {},
    sign = {
      enabled = false,
    },
    heading = {
      backgrounds = {},
    },
    win_options = {
      wrap = { default = false, rendered = true },
    },
  },
  config = function(_, opts)
    require('render-markdown').setup(opts)

    --[[
    In-place rendering is disabled (render_modes = {}); entering insert mode
    opens the split preview (raw source next to live-rendered output, which
    renders via the plugin's overrides.preview defaults) and leaving insert
    mode closes it again. preview.open() toggles, so each call checks the
    plugin's own open-state table to stay in sync with manual
    toggles. Scheduled because nvim_buf_delete() inside an autocmd callback
    never fires the preview buffer's BufWipeout cleanup, leaving stale state.
    ]]
    local preview = require 'render-markdown.core.preview'

    --[[
    Open the preview to the right of wide windows and below tall ones, since
    preview.open() itself only ever splits right. Terminal cells are about
    twice as tall as they are wide, so cols > 2*lines reads as "wider than
    tall". The move uses :wincmd, which keeps the window id, so the plugin's
    line/cursor sync closures stay valid.
    ]]
    ---@param buf integer
    local function open_preview(buf)
      local src_win = vim.fn.bufwinid(buf)
      local wide = src_win ~= -1 and vim.api.nvim_win_get_width(src_win) > vim.api.nvim_win_get_height(src_win) * 2
      preview.open(buf)
      local dst = preview.buffers[buf]
      if wide or not dst then
        return
      end
      local dst_win = vim.fn.bufwinid(dst)
      if dst_win == -1 then
        return
      end
      vim.api.nvim_win_call(dst_win, function()
        vim.cmd.wincmd 'J'
      end)
    end

    ---@param buf integer
    ---@param open boolean
    local function sync_preview(buf, open)
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf) then
          return
        end
        if open and preview.buffers[buf] == nil then
          open_preview(buf)
        elseif not open and preview.buffers[buf] ~= nil then
          preview.open(buf)
        end
      end)
    end

    local group = vim.api.nvim_create_augroup('MarkdownInsertPreview', {})
    vim.api.nvim_create_autocmd('FileType', {
      group = group,
      pattern = 'markdown',
      callback = function(args)
        -- the preview copy itself is a nofile scratch buffer; do not recurse into it
        if vim.bo[args.buf].buftype ~= '' then
          return
        end
        vim.api.nvim_create_autocmd('InsertEnter', {
          group = group,
          buffer = args.buf,
          callback = function()
            sync_preview(args.buf, true)
          end,
        })
        vim.api.nvim_create_autocmd('InsertLeave', {
          group = group,
          buffer = args.buf,
          callback = function()
            sync_preview(args.buf, false)
          end,
        })
      end,
    })

    require('cmdr').add {
      {
        desc = 'Toggle markdown rendering',
        cmd = '<CMD>RenderMarkdown toggle<CR>',
        cat = 'markdown',
      },
      {
        desc = 'Enable markdown rendering',
        cmd = '<CMD>RenderMarkdown enable<CR>',
        cat = 'markdown',
      },
      {
        desc = 'Disable markdown rendering',
        cmd = '<CMD>RenderMarkdown disable<CR>',
        cat = 'markdown',
      },
    }
  end,
}
