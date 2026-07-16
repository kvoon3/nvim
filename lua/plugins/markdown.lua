return {
  'MeanderingProgrammer/render-markdown.nvim',
  dependencies = { 'nvim-mini/mini.icons' },
  ---@module 'render-markdown'
  ---@type render.md.UserConfig
  opts = {
    -- never render in place; the rendered view only shows in the insert-mode corner float
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
    In-place rendering is disabled (render_modes = {}). Instead of the
    plugin's 1/2 split preview, entering insert mode opens a small corner
    float (1/4 of the editor, bottom-right) showing the live-rendered
    markdown. The float holds a scratch copy of the source (kept in sync via
    diff, like the plugin's own preview) and we render markdown into it with
    the public render-markdown API. Leaving insert mode closes the float.
    ]]
    local render = require 'render-markdown'
    local preview_group = vim.api.nvim_create_augroup('RenderMarkdownPreview', {})

    ---@class CornerPreview
    ---@field buf integer?  source markdown buffer
    ---@field dst_buf integer?  scratch buffer shown in the float
    ---@field win integer?  float window
    local preview = {
      buf = nil,
      dst_buf = nil,
      win = nil,
    }

    --[[
    Diff-copy source lines into the scratch buffer so the rendered float
    always mirrors the source without a full rewrite on every keystroke.
    ]]
    ---@param src integer
    ---@param dst integer
    local function copy_lines(src, dst)
      local src_lines = vim.api.nvim_buf_get_lines(src, 0, -1, false)
      local dst_lines = vim.api.nvim_buf_get_lines(dst, 0, -1, false)
      local src_text = table.concat(src_lines, '\n') .. '\n'
      local dst_text = table.concat(dst_lines, '\n') .. '\n'
      ---@diagnostic disable-next-line: deprecated
      local get_diff = vim.text and vim.text.diff or vim.diff
      local diff = get_diff(dst_text, src_text, { result_type = 'indices' })
      if type(diff) ~= 'table' then
        return
      end
      vim.bo[dst].modifiable = true
      for i = 1, #diff do
        local hunk = diff[#diff - i + 1]
        local start_a, count_a, start_b, count_b = unpack(hunk)
        local line_start = start_a - 1
        local line_end = start_a + count_a - 1
        if count_a == 0 then
          line_start = line_start + 1
          line_end = line_end + 1
        end
        vim.api.nvim_buf_set_lines(dst, line_start, line_end, false, {
          unpack(src_lines, start_b, start_b + count_b - 1),
        })
      end
      vim.bo[dst].modifiable = false
    end

    --[[
    Re-render the scratch buffer's markdown into the float window via the
    public render-markdown API.
    ]]
    local function rerender()
      if not preview.dst_buf or not preview.win then
        return
      end
      render.render { buf = preview.dst_buf, win = preview.win }
    end

    local function close()
      local dst_buf = preview.dst_buf
      local win = preview.win
      local src_buf = preview.buf
      preview.dst_buf = nil
      preview.win = nil
      preview.buf = nil

      if src_buf then
        vim.api.nvim_clear_autocmds({ group = preview_group, buffer = src_buf })
      end

      -- the BufWipeout autocmd on dst_buf also calls close(); clearing it
      -- first avoids a recursive/duplicate delete attempt.
      if dst_buf and vim.api.nvim_buf_is_valid(dst_buf) then
        vim.api.nvim_clear_autocmds({ group = preview_group, buffer = dst_buf })
      end

      if win and vim.api.nvim_win_is_valid(win) then
        -- detach the buffer from the window first so the buffer is not
        -- "in use" when we delete it (avoids E937).
        pcall(vim.api.nvim_win_set_buf, win, vim.api.nvim_create_buf(false, true))
        vim.api.nvim_win_close(win, true)
      end

      if dst_buf and vim.api.nvim_buf_is_valid(dst_buf) then
        vim.api.nvim_buf_delete(dst_buf, { force = true })
      end
    end

    --[[
    Open a bottom-right float at 1/4 of the editor size. The scratch buffer
    copies the source and gets rendered; cursor/line sync keeps it aligned.
    ]]
    ---@param buf integer
    local function open(buf)
      local src_win = vim.fn.bufwinid(buf)
      if src_win == -1 then
        return
      end
      local ed_w, ed_h = vim.o.columns, vim.o.lines
      local w = math.max(20, math.floor(ed_w / 3))
      local h = math.max(5, math.floor(ed_h / 3))
      local dst_buf = vim.api.nvim_create_buf(false, true)
      local win = vim.api.nvim_open_win(dst_buf, false, {
        relative = 'editor',
        width = w,
        height = h,
        col = ed_w - w,
        row = ed_h - h - 2, -- leave room for the command line
        style = 'minimal',
        border = 'rounded',
        zindex = 50,
      })
      preview.buf = buf
      preview.dst_buf = dst_buf
      preview.win = win

      vim.bo[dst_buf].buftype = 'nofile'
      vim.bo[dst_buf].filetype = 'markdown'
      vim.bo[dst_buf].modifiable = false
      vim.bo[dst_buf].swapfile = false
      vim.wo[win].wrap = true
      vim.wo[win].linebreak = true

      copy_lines(buf, dst_buf)
      rerender()

      local function sync()
        if not preview.buf or not preview.dst_buf or not preview.win then
          return
        end
        if not vim.api.nvim_buf_is_valid(preview.buf) then
          close()
          return
        end
        copy_lines(preview.buf, preview.dst_buf)
        rerender()
        local cursor = vim.api.nvim_win_get_cursor(src_win)
        pcall(vim.api.nvim_win_set_cursor, preview.win, cursor)
        -- keep the cursor line in view: center it within the float so the
        -- preview follows the editing position as the source scrolls.
        vim.api.nvim_win_call(preview.win, function()
          vim.cmd 'normal! zz'
        end)
      end

      vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI', 'TextChanged', 'TextChangedI' }, {
        group = preview_group,
        buffer = buf,
        callback = sync,
      })
      vim.api.nvim_create_autocmd('BufWipeout', {
        group = preview_group,
        buffer = dst_buf,
        once = true,
        callback = close,
      })
    end

    --[[
    Toggle the corner float on insert enter/leave. Scheduled because
    nvim_buf_delete() inside an autocmd callback never fires the preview
    buffer's BufWipeout cleanup, leaving stale state.
    ]]
    ---@param buf integer
    ---@param want_open boolean
    local function sync_preview(buf, want_open)
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf) then
          return
        end
        if want_open and preview.buf == nil then
          open(buf)
        elseif not want_open and preview.buf ~= nil then
          close()
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
