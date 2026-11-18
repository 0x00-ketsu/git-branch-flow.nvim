vim.opt.runtimepath:prepend(vim.fn.getcwd())
local entry = require("git-branch-flow")
local git = require("git-branch-flow.git")
local original_run, original_select = git.run, vim.ui.select
git.run = function(_, args, callback)
  assert(args[1] == "for-each-ref")
  callback(
    "release\0\0*\ndevelop\0\0 \norigin/release\0\0 \norigin/develop\0\0 \norigin/HEAD\0refs/remotes/origin/release\0 \n",
    nil
  )
end
local chosen
vim.ui.select = function(branches, opts, callback)
  assert(opts.snacks.layout.layout.min_width < 80)
  local layout = { layout = { { win = "input", height = 1 }, { win = "list" } } }
  opts.snacks.layout.config(layout)
  assert(layout.layout[2].height == #branches)
  chosen = branches
  callback(nil)
end
entry.open()
assert(vim.deep_equal(chosen, { "develop", "origin/develop" }), vim.inspect(chosen))
git.run, vim.ui.select = original_run, original_select
print("entry test passed")
vim.cmd("qa!")
