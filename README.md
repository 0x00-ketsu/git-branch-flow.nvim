# git-branch-flow.nvim

Compare Git branches by issue, inspect commit dependencies, and cherry-pick selected commits.
The comparison groups commits by identifiers in commit messages and tracks included and equivalent
patches. It can also show unpushed cherry-picks, review dependencies, and inspect conflicts.

## Requirements

- Neovim 0.12 or newer and Git, available on `PATH`.
- A clipboard provider for copying to the system clipboard. The unnamed register remains available.
- [snacks.nvim](https://github.com/folke/snacks.nvim) is optional. When its `vim.ui.select`
  implementation is enabled, the branch picker uses a compact Snacks layout. Other implementations
  of `vim.ui.select` are supported without Snacks.

## Installation

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "0x00-ketsu/git-branch-flow.nvim",
  dependencies = {
    "folke/snacks.nvim", -- optional; remove this line if you do not use Snacks
  },
  keys = {
    {
      "<leader>gm",
      function() require("git-branch-flow").open() end,
      desc = "Compare Git branch commits",
    },
  },
  opts = {},
}
```

The example installs Snacks as a dependency; omit it if you do not use Snacks.

Call `require("git-branch-flow").open()` from a mapping or a dashboard action. Select a source
branch; the current branch is the target. Open `g?` in the comparison for the available keys.

## Configuration

All options are optional. `setup()` replaces the current configuration with the supplied options
merged into the defaults. Width is automatic when omitted.

```lua
require("git-branch-flow").setup({
  issue = {
    pattern = "[%a][%w]*%-%d+", -- Lua pattern used to parse issue trailers
    width = 48, -- issue sidebar width; omit for automatic sizing
    extract = function(commit)
      -- Return all issue identifiers from the commit's subject or body.
      -- Fields: sha, time (Unix seconds), author, subject, body.
      local issues = {}
      for id in (commit.subject .. "\n" .. commit.body):gmatch("JIRA%-%d+") do
        issues[#issues + 1] = id
      end
      return issues
    end,
  },
  history_days = 90,
  hooks = {
    on_open = function(comparison) end,
    on_refresh = function(comparison) end,
    before_cherry_pick = function(event) end,
    after_cherry_pick = function(event) end,
  },
})
```

By default, identifiers are read from `Issue:` trailers in commit bodies. A custom `extract`
function replaces that extraction for each commit; return an array, or an empty array if there are
no issues. `Depends-on:` issue references and `Depends-on-commit:` hashes retain their existing
trailer formats. The pattern also affects how identifiers in those trailers are parsed.

Hooks are optional observers. Their errors produce a warning and do not interrupt the operation.
`on_open` receives the comparison data; `on_refresh` receives updated comparison data after a
manual refresh or a successful cherry-pick reload. `before_cherry_pick` receives `root`, `branch`,
and `commits` (an array of hashes). `after_cherry_pick` receives `commits`, a `status` of `success`,
`conflict`, or `failed`, and an `error` on failure. A successful cherry-pick is reported before the
subsequent comparison refresh completes.

## Development

Run the independent tests from the repository root:

```sh
NVIM_LOG_FILE=/tmp/nvim-git-branch-flow.log python3 tests/run.py
for test in config model entry ui copy conflict_display unpushed_display; do
  NVIM_LOG_FILE=/tmp/nvim-git-branch-flow.log nvim --clean --headless -l "tests/$test.lua"
done
stylua --check lua tests/*.lua
typos
```
