vim.opt.runtimepath:prepend(vim.fn.getcwd())
local git = require("git-branch-flow.git")
git.unpushed_picks = function(_, callback)
  callback({ status = "no_upstream" })
end
git.resolve_dependencies = function(_, _, callback)
  callback()
end
git.pick = function(_, _, _, _, callback)
  callback("conflict")
end
local candidate = {
  commit = { sha = "abcd1234", subject = "prepare", issues = { "IMS-2" } },
  files = { "path/file" },
}
local result = { files = { "path/file" }, candidates = {} }
git.conflict_candidates = function(_, callback)
  callback(result)
end
local item = {
  sha = "12345678",
  status = "unmatched",
  time = os.time(),
  author = "Test",
  subject = "change",
  issues = { "IMS-1" },
  depends_on = {},
  depends_on_commits = {},
}
require("git-branch-flow.ui").open({
  root = "/tmp",
  branch = "release",
  source_ref = "develop",
  head_sha = "head",
  source = { item },
  target = {},
})
local function keys(value)
  vim.fn.feedkeys(vim.api.nvim_replace_termcodes(value, true, false, true), "xt")
end
keys("<CR><Space>p")
vim.wait(100)
keys("Gy")
local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
assert(lines[1] ~= "" and lines[#lines] ~= "")
local text = table.concat(lines, "\n")
assert(text:find("1 conflict file · 0 possible related commits", 1, true))
assert(text:find("Resolve the conflict manually", 1, true))
assert(text:find("path/file", 1, true))
keys("q")
result.candidates = { candidate }
keys("p")
vim.wait(100)
keys("Gy")
lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
assert(lines[1] ~= "" and lines[#lines] ~= "")
text = table.concat(lines, "\n")
assert(text:find("1 conflict file · 1 possible related commit", 1, true))
assert(text:find("may need to be applied first", 1, true))
assert(text:find("abcd1234", 1, true) and text:find("path/file", 1, true))
print("conflict display passed")
vim.cmd("qa!")
