--[[
Prose buffers (markdown, text) soft-wrap long lines and make j/k follow
display lines, so the cursor moves to the visually adjacent character
instead of jumping whole wrapped paragraphs.
]]
vim.api.nvim_create_autocmd('FileType', {
  group = vim.api.nvim_create_augroup('ProseWrap', { clear = true }),
  pattern = { 'markdown', 'text' },
  callback = function(args)
    vim.opt_local.wrap = true
    vim.opt_local.linebreak = true -- wrap at word boundaries, not mid-word
    vim.opt_local.breakindent = true -- keep indent on wrapped continuation lines

    -- counts still operate on real lines (e.g. 3j skips 3 lines);
    -- must use ? : since VimL has no and/or operators
    vim.keymap.set({ 'n', 'x' }, 'j', "v:count == 0 ? 'gj' : 'j'", { expr = true, buffer = args.buf })
    vim.keymap.set({ 'n', 'x' }, 'k', "v:count == 0 ? 'gk' : 'k'", { expr = true, buffer = args.buf })
  end,
})
