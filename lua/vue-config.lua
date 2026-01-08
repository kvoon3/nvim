local vue_group = vim.api.nvim_create_augroup("VueConfig", { clear = true })

vim.api.nvim_create_autocmd("FileType", {
  group = vue_group,
  pattern = "vue",
  callback = function()
    vim.b.coc_root_patterns = {
      '.git',
      '.env',
      'package.json',
      'tsconfig.json',
      'jsconfig.json',
      'vite.config.ts',
      'vite.config.js',
      'vue.config.js',
      'nuxt.config.ts',
      'nuxt.config.js'
    }
    
    vim.opt_local.iskeyword:append('-')
    vim.opt_local.formatexpr = "CocAction('formatSelected')"
  end,
  desc = "Configure workspace patterns and settings for Vue files"
})
