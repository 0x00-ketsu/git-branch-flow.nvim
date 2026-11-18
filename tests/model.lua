vim.opt.runtimepath:prepend(vim.fn.getcwd())
local model = require("git-branch-flow.model")
local rows = require("git-branch-flow.parser").parse_log(
  "\30abc\0"
    .. "1\0author\0subject\0Issue: #123, FEATURE-42, custom-name\n"
    .. "Depends-on: #123, custom-name\n"
)
assert(vim.deep_equal(rows[1].issues, { "#123", "FEATURE-42", "custom-name" }))
assert(vim.deep_equal(rows[1].depends_on, { "#123", "custom-name" }))
local legacy = require("git-branch-flow.parser").parse_log(
  "\30def\0" .. "1\0author\0subject\0Issue: IMS-1 IMS-2\n"
)
assert(vim.deep_equal(legacy[1].issues, { "IMS-1", "IMS-2" }))
local marked = model.classify({ "a", "b", "c" }, { a = true }, "- b\n+ c\n")
assert(marked.a == "included" and marked.b == "equivalent" and marked.c == "unmatched")
local now = 20000000
local commits = {
  { sha = "a", time = now - 10, issues = { "IMS-1" }, status = "included" },
  { sha = "b", time = now - 100, issues = { "IMS-1" }, status = "equivalent" },
  { sha = "c", time = now - 1000, issues = { "IMS-1" }, status = "unmatched" },
  { sha = "d", time = now - 1, issues = {}, status = "unmatched" },
}
local groups = model.groups(commits, 50, now)
assert(#groups == 1)
assert(groups[1].id == "IMS-1")
assert(#groups[1].commits == 2)
assert(groups[1].included == 1 and groups[1].limited)
assert(groups[1].state == "partial")
local dependencies = model.dependencies({
  {
    sha = "aaaa1111",
    issues = { "IMS-2" },
    depends_on = { "IMS-1" },
    depends_on_commits = { "cccc3333" },
    status = "unmatched",
  },
  {
    sha = "bbbb2222",
    issues = { "IMS-1" },
    depends_on = {},
    depends_on_commits = {},
    status = "included",
  },
  {
    sha = "cccc3333",
    issues = {},
    depends_on = {},
    depends_on_commits = {},
    status = "unmatched",
  },
}, {}, { "aaaa1111" })
assert(#dependencies == 1 and dependencies[1].sha == "cccc3333")
local cyclic = model.dependencies({
  {
    sha = "1111aaaa",
    issues = { "custom" },
    status = "unmatched",
    depends_on = {},
    depends_on_commits = { "2222" },
  },
  {
    sha = "2222bbbb",
    issues = {},
    status = "unmatched",
    depends_on = {},
    depends_on_commits = { "1111" },
  },
}, {}, { "1111aaaa" }, {}, { ["2222"] = "2222bbbb", ["1111"] = "1111aaaa" })
assert(vim.tbl_contains(
  vim.tbl_map(function(item)
    return item.kind
  end, cyclic),
  "cycle"
))
local missing = model.dependencies({
  {
    sha = "3333cccc",
    issues = { "#42" },
    status = "unmatched",
    depends_on = { "not-found" },
    depends_on_commits = { "bad!" },
  },
}, {}, { "3333cccc" }, {}, { ["bad!"] = false })
assert(#missing == 2)
local issue_commits = {
  { sha = "a1", issues = { "A-1" }, depends_on = {}, status = "unmatched" },
  { sha = "a2", issues = { "A-1" }, depends_on = { "B-1" }, status = "unmatched" },
  { sha = "b1", issues = { "B-1" }, depends_on = { "C-1" }, status = "included" },
  { sha = "b2", issues = { "B-1" }, depends_on = {}, status = "unmatched" },
  { sha = "c1", issues = { "C-1" }, depends_on = {}, status = "equivalent" },
}
local graph = model.issue_dependencies(issue_commits, "A-1")
assert(graph.status == "pending" and #graph.warnings == 1)
assert(graph.warnings[1].ref == "B-1")
assert(graph.lines[1].id == "B-1" and graph.lines[2].id == "C-1")
issue_commits[4].status = "included"
assert(model.issue_dependencies(issue_commits, "A-1").status == "ready")
issue_commits[3].depends_on = { "A-1" }
assert(model.issue_dependencies(issue_commits, "A-1").status == "unknown")
issue_commits[3].depends_on = { "MISSING-1" }
assert(model.issue_dependencies(issue_commits, "A-1").warnings[1].kind == "missing_issue")
issue_commits[2].depends_on = { "A-1" }
assert(model.issue_dependencies(issue_commits, "A-1").warnings[1].kind == "cycle")
assert(vim.deep_equal(
  model.ordered_selection({
    { sha = "new" },
    { sha = "middle" },
    { sha = "old" },
  }, { new = true, old = true }),
  { "old", "new" }
))
print("model test passed")
vim.cmd("qa!")
