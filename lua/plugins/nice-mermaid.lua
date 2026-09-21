return {
  'iurysza/nice-mermaid.nvim',
  event = 'VeryLazy',
  -- The renderer is a Node bridge, so the pinned package is installed at build time.
  build = function(plugin)
    local result = vim.system({ 'npm', 'ci', '--omit=dev' }, { cwd = plugin.dir .. '/bridge', text = true }):wait()
    if result.code ~= 0 then
      error(result.stderr)
    end
  end,
  config = function()
    require('nice_mermaid').setup {}

    require('cmdr').add {
      { desc = 'Markdown: toggle Mermaid preview', cmd = '<CMD>Mermaid toggle<CR>', cat = 'markdown' },
    }
  end,
}
