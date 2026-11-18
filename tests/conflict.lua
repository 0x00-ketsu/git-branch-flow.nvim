vim.opt.runtimepath:prepend(vim.fn.getcwd())
local git = require("git-branch-flow.git")
local done, data, failure = false, nil, nil
git.load(vim.env.GIT_TEST_REPO, "develop", function(value, error)
  data, failure, done = value, error, true
end)
assert(
  vim.wait(10000, function()
    return done
  end),
  "load timed out"
)
assert(not failure, failure)
local selected = {}
for i = #data.source, 1, -1 do
  local item = data.source[i]
  if item.subject == "clean" or item.subject == "conflict" or item.subject == "after-conflict" then
    table.insert(selected, item.sha)
  end
end
assert(#selected == 3)
done, failure = false, nil
git.pick(data.root, data.branch, data.head_sha, selected, function(error)
  failure, done = error, true
end)
assert(
  vim.wait(10000, function()
    return done
  end),
  "pick timed out"
)
assert(failure and failure ~= "")
local subject = vim.fn.systemlist({ "git", "-C", data.root, "log", "-1", "--format=%s" })[1]
assert(subject == "clean", subject)
assert(vim.uv.fs_stat(data.root .. "/.git/CHERRY_PICK_HEAD"))
local todo = vim.fn.readfile(data.root .. "/.git/sequencer/todo")
assert(table.concat(todo, "\n"):find("after-conflict", 1, true))
assert(not vim.uv.fs_stat(data.root .. "/after-conflict"))
print("conflict preservation passed")
vim.cmd("qa!")
