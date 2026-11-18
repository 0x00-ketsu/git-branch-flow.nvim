vim.opt.runtimepath:prepend(vim.fn.getcwd())
local done, result, failure = false, nil, nil
require("git-branch-flow.git").load(vim.env.GIT_TEST_REPO, "develop", function(data, err)
  result, failure, done = data, err, true
end)
assert(
  vim.wait(10000, function()
    return done
  end),
  "load timed out"
)
assert(not failure, failure)
for _, commit in ipairs(result.source) do
  if commit.subject == "change" then
    assert(commit.status == "equivalent", "different context should still match")
    print("context-independent patch comparison passed")
    vim.cmd("qa!")
    return
  end
end
error("fixture commit missing")
