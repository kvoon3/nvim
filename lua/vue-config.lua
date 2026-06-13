local vue_group = vim.api.nvim_create_augroup("VueConfig", { clear = true })

vim.api.nvim_create_autocmd("FileType", {
  group = vue_group,
  pattern = "vue",
  callback = function()
    vim.opt_local.iskeyword:append('-')
  end,
  desc = "Configure Vue file settings"
})
