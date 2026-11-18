# Repository Guidelines

## Project Structure & Module Organization

The Neovim plugin lives in `lua/git-branch-flow/`. `init.lua` exposes `setup()` and `open()`;
`git.lua` handles Git operations, `parser.lua` and `model.lua` process commits, and `ui.lua`
and `select.lua` provide the interface. Defaults and validation belong in `config.lua`.
Tests live in `tests/`; `tests/run.py` creates temporary Git repositories for integration tests.
`README.md` documents installation, configuration, and user-facing behavior.

## Build, Test, and Development Commands

Neovim 0.12 or newer, Git, and Python 3 are required for development. Run from the repository root:

- `NVIM_LOG_FILE=/tmp/nvim-git-branch-flow.log python3 tests/run.py` runs Git integration tests.
- `for test in config model entry ui copy conflict_display unpushed_display; do
  NVIM_LOG_FILE=/tmp/nvim-git-branch-flow.log nvim --clean --headless -l "tests/$test.lua";
  done` runs the independent Lua tests.
- `stylua --check lua tests/*.lua` checks Lua formatting; `typos` checks spelling.

There is no build step. Load the plugin in Neovim and call
`require("git-branch-flow").open()` to exercise it interactively.

## Coding Style & Naming Conventions

Follow `.stylua.toml`: two spaces, 100-column lines, Unix line endings, and sorted requires.
Use lowercase snake_case for Lua modules, functions, and variables, matching existing code.
Document added or changed functions concisely using the existing Lua comment style. Keep Git
operations, data processing, and UI behavior in their respective modules.

## Testing Guidelines

Tests are Lua scripts using Neovim and assertions, without a separate test framework. Name new
scripts after the behavior they cover, such as `tests/conflict_display.lua`. Add integration
fixtures to `tests/run.py` when a test needs a Git repository; keep fixtures in temporary
folders. Run the relevant tests and formatting checks for each change. No coverage threshold is
configured.

## Commit & Pull Request Guidelines

The available history contains only `Initial commit`, so it establishes no detailed message
convention. Use a concise, imperative subject describing the change. Pull requests should explain
the behavior and motivation, link relevant issues, and list verification commands and results.
Include screenshots when changing visible UI behavior.
