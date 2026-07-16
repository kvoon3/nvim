return {
  'MeanderingProgrammer/render-markdown.nvim',
  dependencies = { 'nvim-mini/mini.icons' },
  ---@module 'render-markdown'
  ---@type render.md.UserConfig
  opts = {
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
    Normal mode renders in place; insert mode switches to split preview
    (raw source on the left, live-rendered output on the right) and leaving
    insert mode closes it again. preview.open() toggles, so each call checks
    the plugin's own open-state table to stay in sync with manual toggles.
    Scheduled because nvim_buf_delete() inside an autocmd callback never
    fires the preview buffer's BufWipeout cleanup, leaving stale state.
    ]]
    local preview = require 'render-markdown.core.preview'

    ---@param buf integer
    ---@param open boolean
    local function sync_preview(buf, open)
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(buf) and (preview.buffers[buf] ~= nil) ~= open then
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
        desc = 'Toggle markdown split preview',
        cmd = '<CMD>RenderMarkdown preview<CR>',
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
