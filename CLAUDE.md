# CLAUDE.md - Neovim Configuration Guide

This file provides comprehensive guidance for working with the Neovim configuration in `/Users/kvoon/.config/nvim`. It covers common commands, architecture, file structure, and development workflows.

## Commands for Common Tasks

### Setup & Installation
```bash
# Auto-setup on first launch (lazy.nvim handles this)
# The configuration automatically installs: lazy.nvim -> plugins -> dependencies

# Manual plugin updates
:Lazy sync                   # Sync and update all plugins
:Lazy update                 # Update plugins with changes
:Lazy install                # Install missing plugins

# Plugin management commands (within neovim)
:Lazy                        # Open lazy.nvim UI
:Lazy health                 # Check plugin health
:Lazy dev [plugin]           # Develop/debug specific plugin
:Lazy clean                  # Remove unused plugins
```

### Configuration Testing & Validation
```bash
# Inside neovim:
:checkhealth                 # Check overall neovim health
:checkhealth coc            # Check CoC language server status
:checkhealth treesitter     # Check treesitter parser status
:checkhealth telescope      # Check telescope functionality

# Lua configuration validation
:lua print(vim.inspect(require('config.lazy')))
:luafile %                  # Source current lua file (when editing configs)
:source ~/.config/nvim/init.lua  # Reload entire configuration

# Test keybindings
:nmap<Space><BS>            # Test file explorer binding
:nmap <C-p>                 # Test telescope find files
:nmap <c-'>                 # Test quit binding
```

### Development Environment Checks
```bash
# Verify plugin locations
echo $HOME/.local/share/nvim/lazy | ls

# Check treesitter parser installation
nvim --headless -c "TSInstallInfo" -c "quit!"

# Validate CoC extensions
coc-extensions: coc-explorer, coc-json, coc-tsserver, coc-python, etc.
```

## High-Level Architecture & Structure

### Overview
This Neovim configuration uses a **modular Lua-based architecture** built on lazy.nvim as the plugin manager. It follows the modern Neovim configuration pattern with separate concerns:

- **Core load order**: `init.lua` → `config/lazy.lua` → `options.lua` → `keymaps.lua` → `coc-config.lua`
- **Plugin loading**: All plugins are defined in separate files under `lua/plugins/`
- **Lazy loading**: Uses lazy.nvim's sophisticated plugin loading system
- **Editor integration**: Primary backend via CoC (Conquer of Completion) for LSP features

### Plugin Loading Architecture
```
init.lua (entry point)
├── config.lazy: Sets up lazy.nvim plugin manager
│   ├── Loads all plugins from lua/plugins/*.lua
│   ├── Manages plugin dependencies
│   └── Handles lazy loading strategies
├── options.lua: Global Neovim settings
├── keymaps.lua: Keybinding definitions
└── coc-config.lua: Language server configuration
```

### Configuration Philosophy
- **Minimal defaults**: Clean, focused setup without bloat
- **Opinionated choices**: Moonfly colorscheme, CoC for LSP, telescope for fuzzy finding
- **Performance-focused**: Lazy loading enabled for all non-critical plugins
- **Developer-friendly**: Extensive keybindings, language server support, Chinese text support

## Key File Structure

### Primary Files
```
~/.config/nvim/
├── init.lua                 # Entry point - loads everything
├── coc-settings.json        # CoC extension configuration (currently empty)
├── lazy-lock.json          # Plugin lock file (auto-generated)
├── LICENSE                 # MIT License
└── README.md               # Basic documentation
```

### Lua Configuration (`/lua/`)
```
lua/
├── config/
│   └── lazy.lua           # Lazy.nvim setup and plugin management
├── plugins/               # Individual plugin configurations (15 files)
│   ├── auto-dark-mode.lua # Automatic dark/light mode switching
│   ├── auto-pairs.lua    # Auto-closing brackets/quotes
│   ├── coc.lua          # Conquer of Completion integration
│   ├── flash.lua        # Advanced search/jump functionality
│   ├── imm-select.lua   # IME management for Chinese input
│   ├── jieba.lua        # Chinese text segmentation/word motion
│   ├── kanagawa.lua     # Alternative colorscheme (backup)
│   ├── markdown.lua     # Markdown rendering and preview
│   ├── markers.lua      # Bookmark/navigation system
│   ├── moonfly.lua      # Primary colorscheme configuration
│   ├── surround.lua     # Text object surround operations
│   ├── telescope.lua    # Fuzzy finding framework
│   ├── treesitter.lua   # Syntax highlighting and parsing
│   ├── ts-comment.lua   # TypeScript/JavaScript commenting
│   └── wakatime.lua     # Code time tracking
├── coc-config.lua         # CoC keybindings and functionality
├── options.lua           # Global Neovim settings
└── keymaps.lua           # Keybinding definitions
```

### Detailed Plugin Overview

**Colors & Themes**
- **moonfly.lua (priority: 1000)**: Primary colorscheme loaded immediately
- **auto-dark-mode.lua**: System dark mode synchronization
- **kanagawa.lua**: Backup colorscheme option

**Developer Tools**
- **telescope.lua**: File finding (`<C-p>`), grep (`<leader>ff`), buffers, help
- **treesitter.lua**: Advanced syntax highlighting and parsing
- **coc.lua**: VSCode-grade language server support (LSP, diagnostics, refactoring)
- **flash.lua**: Lightning-fast search and jump (similar to easymotion)
- **markers.lua**: Navigation bookmarks and location management

**Text Manipulation**
- **surround.lua**: `ys`, `cs`, `ds` operations for quotes/parentheses
- **auto-pairs.lua**: Automatic bracket and quote completion
- **markdown.lua**: Enhanced markdown rendering and preview
- **jieba.lua**: Chinese text word motion and text objects

**Language Support**
- **ts-comment.lua**: TypeScript-aware commenting
- **imm-select.lua**: Input method switching for multilingual typing
- **wakatime.lua**: automatic time tracking for coding statistics

## Common Development Tasks

### Adding New Plugins
1. Create new file: `lua/plugins/[plugin-name].lua`
2. Follow the pattern (return `{ plugin_name, opts = {} }`)
3. Restart Neovim or run `:Lazy sync`

**Example Template:**
```lua
-- lua/plugins/new-plugin.lua
return {
  "author/plugin-name",
  event = "VeryLazy",  -- Load after everything else
  config = function()
    require("plugin-name").setup({
      -- configuration here
    })
  end,
  dependencies = {
    "other/dependency-plugin",
  }
}
```

### Modifying Plugin Settings
1. Locate plugin file in `lua/plugins/`
2. Add/modify configuration in the returned table
3. Apply changes: `:Lazy sync` or restart Neovim

### Adding New Keybindings
1. Add to `lua/keymaps.lua` using the existing pattern
2. Group related bindings together using comments
3. Test immediately with `:luafile %`

**Keybinding Pattern:**
```lua
-- [mode], [key], [command], [options]
vim.keymap.set('n', '<leader>key', ':Command<CR>', { desc = 'Description' })
```

### Debugging Configuration Issues

**Common Debugging Commands:**
```bash
# Test configuration elements
:lua require('options')    # Test options loading
:lua require('keymaps')    # Test keymaps loading

# Check specific plugin state
:lua print(vim.inspect(require("plugins.moonfly")))

# CoC debugging
coc-extension: CocList extensions
:coc-status               # Check CoC health
```

**Log and Cache Locations:**
- Lazy plugin cache: `~/.local/share/nvim/lazy/`
- CoC data: `~/.config/coc/` 
- Treesitter parsers: `~/.local/share/nvim/tree-sitter/`
- Debug logs: Check `:messages`

### Performance Optimization
- All plugins use lazy-loading (on-demand or event-based)
- Critical plugins (colorscheme) loaded immediately with `lazy = false`
- Colorscheme has priority 1000 to load before UI initialization
- Heavy plugins (markdown rendering, etc.) load on filetype events

### Maintenance Commands
```bash
# Update all plugins
:Lazy sync

# Check for configuration drift
:Lazy health

# Clean unused plugins
:Lazy clean

# Update treesitter parsers
:TSUpdate

# Check neovim version compatibility
:version
```

## Environment Notes

**Platform Support:** Configured for macOS (Darwin) with darwin-specific paths and system integrations

**Python/Node Requirements:**
- CoC requires Node.js for language servers
- Some treesitter parsers may require specific compilers
- Jieba plugin requires Chinese text support

**Custom Settings:**
- Uses spaces instead of tabs (tabstop=2, shiftwidth=2, expandtab)
- Moonfly colorscheme as default (dark variant)
- Spacebar `<Space>` as leader key
- Extensive Chinese text support via jieba.nvim

This configuration represents a personal, opinionated setup optimized for developer productivity with strong support for multilingual development (especially Chinese text) and modern language server integration.