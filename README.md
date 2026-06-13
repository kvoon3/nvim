# @kvoon/nvim-config

Kevin Kwong's Neovim config.

## Dependencies

### im-select (optional)

The [im-select.nvim](https://github.com/keaising/im-select.nvim) plugin is used to switch input methods automatically when leaving/entering insert mode. It is only loaded when the `im-select` binary is found in your `PATH`.

To install it on macOS:

```bash
brew tap daipeihust/tap
brew install im-select
```

If the binary is not installed, the plugin is skipped silently and Neovim will start without errors.

