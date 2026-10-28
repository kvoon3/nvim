# product-icons

The footer's icons, taken from [Carbon](https://github.com/antfu/vscode-icons-carbon), the
product icon theme that ports IBM [Carbon](https://carbondesignsystem.com/elements/icons/library/)
to VS Code's product icon API.

Each file is one icon as published by [Iconify](https://iconify.design) for the `carbon` set, with
its original `fill="currentColor"`, so `lua/product-icons.lua` can substitute the tint before
rasterising it. `warning.svg` is what the footer uses for a diagnostic **error** (a circle with `!`)
and `warning-alt.svg` for a **warning** (a triangle); the rest map one to one:

| Footer role | SVG               | Carbon icon    |
| ----------- | ----------------- | -------------- |
| explorer    | `folder-tree.svg` | `folder-tree`  |
| terminal    | `terminal.svg`    | `terminal`     |
| finder      | `apple.svg`       | `apple`        |
| github      | `logo-github.svg` | `logo-github`  |
| branch      | `branch.svg`      | `branch`       |
| diff        | `compare.svg`     | `compare`      |
| lsp         | `plug.svg`        | `plug`         |
| todo        | `list-checked.svg`| `list-checked` |
| error       | `warning.svg`     | `warning`      |
| warning     | `warning-alt.svg` | `warning-alt`  |
| info        | `information.svg` | `information`  |
| hint        | `idea.svg`        | `idea`         |

To refresh or add one, download it by Carbon name and add the role to the registry in
`lua/product-icons.lua`:

```sh
curl -sS -o assets/product-icons/idea.svg https://api.iconify.design/carbon/idea.svg
```

Rasterised copies live in `stdpath('cache')/product-icons` and are keyed on the SVG's size and
mtime, so a refreshed file is picked up on the next start.

Carbon Icons are licensed under the Apache License 2.0, © IBM.
