# Agents

This is a personal Neovim configuration rooted at `~/.config/nvim`. It is written in Lua and uses [lazy.nvim](https://github.com/folke/lazy.nvim) for plugin management.

- Use the `--[[ ... ]]` lua syntax at the beginning of a function to write comments, focusing on aspects that are not easily understood by reading the function interface.
- The same applies to `computed` and `watch` `watchEffect` ... etc in Vue - add comments when their purpose is not clear from their name.
- Avoid writing comments inside the function body unless the code logic is very complex.
- Write comments in English.

## Docs

- Features / install: `README.md`
- Vue & treesitter context: `notes/vue-treesitter.md`

## Commit Codes

- Following Conventional Commits
- Update README.md when we add/update/remove neovim features

## Command Palette (cmdr)

- Register cmdr items in the plugin spec that owns the feature (`lua/plugins/<plugin>.lua`).
- For local feature modules without a lazy.nvim spec, register items in the module itself.
- Do not add `keys` to a new cmdr item unless the user explicitly asks for a keybinding. Keep any existing keybindings intact.
- Whenever a new plugin is added, expose some of its capabilities as cmdr items so they are reachable from the command palette.

