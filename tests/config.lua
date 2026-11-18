vim.opt.runtimepath:prepend(vim.fn.getcwd())
local parser = require("git-branch-flow.parser")
local plugin = require("git-branch-flow")
local seen = {}
plugin.setup({
  issue = {
    extract = function(commit)
      return { commit.subject:match("JIRA%-%d+") }
    end,
  },
  hooks = {
    on_open = function(data)
      seen.open = data
    end,
  },
})
local rows = parser.parse_log("\30abc\0" .. "1\0author\0JIRA-42 fix\0body\n")
assert(vim.deep_equal(rows[1].issues, { "JIRA-42" }))
local config = require("git-branch-flow.config")
config.emit("on_open", { branch = "main" })
assert(seen.open.branch == "main")
print("config test passed")
vim.cmd("qa!")
