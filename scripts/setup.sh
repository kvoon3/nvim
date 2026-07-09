#!/usr/bin/env bash
# One-shot bootstrap for this Neovim config.
set -euo pipefail

have() { command -v "$1" >/dev/null 2>&1; }

if have brew; then
  brew install tree-sitter-cli lazygit
  if [[ "$(uname -s)" == "Darwin" ]]; then
    brew tap daipeihust/tap 2>/dev/null || true
    brew install im-select || true
  fi
fi

if have npm; then
  npm install -g oxfmt oxlint oxlint-tsgolint
fi

# Lazy plugins (jieba, treesitter, …) + Mason via config load
nvim --headless "+Lazy! sync" +qa

echo "Done. Open nvim once if Mason/parsers still need to finish."
