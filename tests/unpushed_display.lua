vim.opt.runtimepath:prepend(vim.fn.getcwd())
local git = require("git-branch-flow.git")
local ui = require("git-branch-flow.ui")
vim.o.columns = 160
require("git-branch-flow").setup({ issue = { width = 45 } })
local result = {
  status = "ready",
  commits = {
    {
      sha = "12345678",
      time = 1700000000,
      author = "张三",
      subject = "中文 message",
      issues = { "IMS-1" },
    },
  },
}
git.unpushed_picks = function(_, callback)
  callback(result)
end

local data = {
  root = "/tmp",
  branch = "release",
  source_ref = "develop",
  head_sha = "abc",
  source = {},
  target = {},
}
ui.open(data)
vim.wait(20)
---Check the summary text and highlights in the current comparison tab.
local function check_summary(expected, group, shortcut)
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].filetype == "gitbranchsummary" then
      local line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
      assert(line == expected, line)
      local marks = vim.api.nvim_buf_get_extmarks(
        buf,
        vim.api.nvim_get_namespaces().git_branch_compare,
        0,
        -1,
        { details = true }
      )
      local found, key = false, false
      for _, mark in ipairs(marks) do
        found = found or (mark[3] == 0 and mark[4].hl_group == group)
        key = key
          or (
            mark[3] == line:find("(H)", 1, true) - 1
            and mark[4].hl_group == "GitBranchCompareKeys"
          )
      end
      assert(found and key == shortcut)
      return
    end
  end
  error("Summary window not found")
end
check_summary("Picked: 1 commit · 1 issue  (H)", "GitBranchCompareMerged", true)
vim.fn.feedkeys("H", "xt")
local detail = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
assert(detail:find("1 commit · 1 issue", 1, true))
assert(
  detail:find(
    "12345678  " .. os.date("%Y-%m-%d", 1700000000) .. "  张三  中文 message",
    1,
    true
  )
)
local detail_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
local width = vim.api.nvim_win_get_width(0)
local text = "1 commit · 1 issue"
local padding = math.floor((width - vim.fn.strdisplaywidth(text)) / 2)
assert(detail_lines[1] == string.rep(" ", padding) .. text)
local highlights = vim.api.nvim_buf_get_extmarks(
  0,
  vim.api.nvim_get_namespaces().git_branch_compare,
  0,
  -1,
  { details = true }
)
local found_summary = false
for _, mark in ipairs(highlights) do
  found_summary = found_summary
    or (
      mark[2] == 0
      and mark[3] == padding
      and mark[4].hl_group == "GitBranchCompareConflictSummary"
    )
end
assert(found_summary)
assert(detail_lines[2] == " " .. string.rep("─", width - 2) .. " ")
assert(detail_lines[#detail_lines] == "   IMS-1")
vim.fn.feedkeys("q", "xt")
result = { status = "ready", commits = {} }
ui.open(data)
vim.wait(20)
check_summary("Picked: 0 commits · 0 issues  (H)", "DiagnosticInfo", false)
vim.fn.feedkeys("H", "xt")
local empty_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
assert(empty_lines[2]:find("─", 1, true))
assert(empty_lines[#empty_lines] == empty_lines[2])
vim.fn.feedkeys("q", "xt")
result = { status = "no_upstream", commits = {} }
ui.open(data)
vim.wait(20)
check_summary("Upstream not configured  (H)", "DiagnosticInfo", false)
vim.fn.feedkeys("H", "xt")
assert(vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == "Upstream not configured")
assert(vim.api.nvim_buf_line_count(0) == 1)
assert(not table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"):find("─", 1, true))
print("unpushed display passed")
vim.cmd("qa!")
