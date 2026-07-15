vim = vim or {}

require 'config.lazy'
require 'options'
require 'keymaps'
require 'config.lsp'
require('config.run_on_save').setup()
require 'vue-config'
