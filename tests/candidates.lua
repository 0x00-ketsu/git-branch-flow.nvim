vim.opt.runtimepath:prepend(vim.fn.getcwd())
local git = require("git-branch-flow.git")
local done, data, err = false, nil, nil
git.load(vim.env.GIT_TEST_REPO, "develop", function(result, failure)
  data, err, done = result, failure, true
end)
assert(
  vim.wait(10000, function()
    return done
  end),
  "load timed out"
)
assert(not err, err)
done = false
git.pick(data.root, data.branch, data.head_sha, { vim.env.CONFLICT_SHA }, function(failure)
  err, done = failure, true
end)
assert(
  vim.wait(10000, function()
    return done
  end),
  "pick timed out"
)
assert(err, "expected conflict")
done = false
local found
git.conflict_candidates(data, function(result, failure)
  found, err, done = result, failure, true
end)
assert(
  vim.wait(10000, function()
    return done
  end),
  "analysis timed out"
)
assert(not err, err)
assert(#found.files == 1 and found.files[1] == "file")
assert(#found.candidates == 1 and found.candidates[1].commit.subject == "prepare")
assert(found.candidates[1].commit.issues[1] == "IMS-10")
assert(found.candidates[1].files[1] == "file")
assert(vim.uv.fs_stat(data.root .. "/.git/CHERRY_PICK_HEAD"))
print("conflict candidates passed")
vim.cmd("qa!")
