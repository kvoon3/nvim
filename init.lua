vim = vim or {}

require 'config.lazy'
require 'options'
require 'keymaps'
require 'config.lsp'
require('config.run-on-save').setup()
require 'vue-config'
