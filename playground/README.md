# Playgrounds

Real, runnable fixtures used to manually exercise config features and to
back integration tests (`tests/*-integration_spec.lua`).

Each subdirectory is a self-contained project:

| Directory           | For                        | Setup            |
|---------------------|----------------------------|------------------|
| `eslint-codemod/`   | `lua/eslint-codemod/`      | `pnpm install`   |

Conventions:

- One directory per feature/plugin; never shared state between them.
- Each has its own `.gitignore` (typically just `node_modules/`) and a
  committed lockfile so installs are reproducible.
- Integration tests gate on the install being present and fall back to a
  placeholder otherwise, so CI and fresh clones stay green.
- Add new directories here rather than at the repo root.
