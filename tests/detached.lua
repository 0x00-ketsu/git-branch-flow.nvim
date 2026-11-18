vim.opt.runtimepath:prepend(vim.fn.getcwd())
local done, failure = false, nil
require("git-branch-flow.git").load(vim.env.GIT_TEST_REPO, "develop", function(_, err)
  failure, done = err, true
end)
assert(vim.wait(10000, function()
  return done
end))
assert(failure and failure:find("detached HEAD", 1, true))
print("detached HEAD check passed")
vim.cmd("qa!")
