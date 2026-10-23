require 'config.lazy'
require 'options'
require 'keymaps'
require 'config.lsp'
require 'config.prose'
require('config.run-on-save').setup()
require 'vue-config'
require('enclosing-brackets').setup()
require('markdown-links').setup()
require('markdown-table').setup()
require('pnpm-catalog-lens').setup()
require('eslint-codemod').setup()

--[[ Build the Rust jieba segmenter (~70ms of dictionary trie) in the background
so the first w/b/e press does not stall. Deferred past startup; a no-op when the
shared library is missing (`just build-native`). ]]
vim.defer_fn(function()
  require('jieba-native').prewarm { hmm = false }
end, 1000)
