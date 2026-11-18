vim.opt.runtimepath:prepend(vim.fn.getcwd())
local git = require("git-branch-flow.git")
local finished, result, err = false, nil, nil
git.load(vim.env.GIT_TEST_REPO, "develop", function(value, failure)
  result, err, finished = value, failure, true
end)
assert(
  vim.wait(10000, function()
    return finished
  end),
  "timed out"
)
assert(not err, err)
local statuses = {}
for _, commit in ipairs(result.source) do
  statuses[commit.subject] = commit.status
end
print(vim.inspect(statuses))
assert(statuses["base"] == "included")
assert(statuses["picked"] == "equivalent")
assert(statuses["pending"] == "unmatched")
local target_statuses = {}
for _, commit in ipairs(result.target) do
  target_statuses[commit.subject] = commit.status
end
assert(target_statuses["base"] == "included")
assert(target_statuses["picked"] == "equivalent")
assert(target_statuses["target-only"] == "unmatched")
local pending
for _, commit in ipairs(result.source) do
  if commit.subject == "pending" then
    pending = commit.sha
  end
end
local resolved = false
git.resolve_dependencies(result, { pending }, function()
  resolved = true
end)
assert(
  vim.wait(10000, function()
    return resolved
  end),
  "dependency resolution timed out"
)
local warnings = require("git-branch-flow.model").dependencies(
  result.source,
  result.target,
  { pending },
  result.extra,
  result.resolved
)
assert(#warnings == 1 and warnings[1].sha == vim.env.EXTERNAL_SHA)
local done, pickerr = false, nil
vim.fn.writefile({ "untracked" }, vim.env.GIT_TEST_REPO .. "/dirty")
git.pick(vim.env.GIT_TEST_REPO, result.branch, result.head_sha, { pending }, function(error)
  pickerr, done = error, true
end)
assert(
  vim.wait(10000, function()
    return done
  end),
  "pick timed out"
)
assert(not pickerr, pickerr)
assert(vim.fn.readfile(vim.env.GIT_TEST_REPO .. "/dirty")[1] == "untracked")
vim.fn.delete(vim.env.GIT_TEST_REPO .. "/dirty")
assert(
  vim.fn.systemlist({ "git", "-C", vim.env.GIT_TEST_REPO, "log", "-1", "--format=%s" })[1]
    == "pending"
)
local current = vim.fn.systemlist({ "git", "-C", vim.env.GIT_TEST_REPO, "rev-parse", "HEAD" })[1]
vim.fn.writefile({ "modified" }, vim.env.GIT_TEST_REPO .. "/base")
done, pickerr = false, nil
git.pick(vim.env.GIT_TEST_REPO, result.branch, current, { pending }, function(error)
  pickerr, done = error, true
end)
assert(
  vim.wait(10000, function()
    return done
  end),
  "dirty test timed out"
)
assert(pickerr and pickerr:find("uncommitted changes", 1, true))
vim.fn.system({ "git", "-C", vim.env.GIT_TEST_REPO, "add", "base" })
done, pickerr = false, nil
git.pick(vim.env.GIT_TEST_REPO, result.branch, current, { pending }, function(error)
  pickerr, done = error, true
end)
assert(
  vim.wait(10000, function()
    return done
  end),
  "staged test timed out"
)
assert(pickerr and pickerr:find("uncommitted changes", 1, true))
vim.fn.system({ "git", "-C", vim.env.GIT_TEST_REPO, "reset", "--hard", "HEAD" })
local edited = vim.fn.bufadd(vim.env.GIT_TEST_REPO .. "/base")
vim.fn.bufload(edited)
vim.api.nvim_buf_set_lines(edited, 0, -1, false, { "unsaved edit" })
done, pickerr = false, nil
git.pick(vim.env.GIT_TEST_REPO, result.branch, current, { pending }, function(error)
  pickerr, done = error, true
end)
assert(
  vim.wait(10000, function()
    return done
  end),
  "unsaved test timed out"
)
assert(pickerr and pickerr:find("unsaved", 1, true))
vim.api.nvim_buf_delete(edited, { force = true })
print("git comparison passed")
vim.cmd("qa!")
