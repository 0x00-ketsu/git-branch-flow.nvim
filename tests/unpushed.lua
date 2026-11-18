vim.opt.runtimepath:prepend(vim.fn.getcwd())
local git = require("git-branch-flow.git")
local done, result, err = false, nil, nil
git.unpushed_picks(vim.env.GIT_TEST_REPO, function(value, failure)
  result, err, done = value, failure, true
end)
assert(
  vim.wait(10000, function()
    return done
  end),
  "unpushed query timed out"
)
assert(not err, err)
assert(result.status == "ready")
assert(#result.commits == 1 and result.commits[1].subject == "picked")
assert(result.commits[1].issues[1] == "IMS-1")
vim.fn.system({ "git", "-C", vim.env.GIT_TEST_REPO, "config", "--unset", "branch.release.merge" })
done, result, err = false, nil, nil
git.unpushed_picks(vim.env.GIT_TEST_REPO, function(value, failure)
  result, err, done = value, failure, true
end)
assert(
  vim.wait(10000, function()
    return done
  end),
  "missing upstream query timed out"
)
assert(not err and result.status == "no_upstream")
vim.fn.system({
  "git",
  "-C",
  vim.env.GIT_TEST_REPO,
  "config",
  "branch.release.merge",
  "refs/heads/release",
})
print("unpushed picks passed")
vim.cmd("qa!")
