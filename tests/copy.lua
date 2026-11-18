vim.opt.runtimepath:prepend(vim.fn.getcwd())
local git = require("git-branch-flow.git")
git.unpushed_picks = function(_, callback)
  callback({ status = "no_upstream" })
end
local records = {}
local previous_setreg = vim.fn.setreg
vim.fn.setreg = function(register, value)
  if register == "+" then
    error("clipboard unavailable")
  end
  records[register] = value
end
local messages = {}
vim.notify = function(message)
  table.insert(messages, message)
end
local function item(sha, status, time)
  return {
    sha = sha,
    status = status,
    time = time,
    author = "Tester",
    subject = sha,
    issues = { "BILLING-420" },
    depends_on = {},
    depends_on_commits = {},
  }
end
require("git-branch-flow.ui").open({
  root = "/tmp",
  branch = "release",
  source_ref = "develop",
  head_sha = "head",
  target = {},
  source = {
    item("newest", "unmatched", os.time()),
    item("oldest", "included", os.time() - 86400 * 365),
  },
})
local function keys(value)
  vim.fn.feedkeys(vim.api.nvim_replace_termcodes(value, true, false, true), "xt")
end
keys("y")
local menu_win = vim.api.nvim_get_current_win()
local config = vim.api.nvim_win_get_config(menu_win)
assert(config.width == math.min(100, math.floor(vim.o.columns * 0.8), vim.o.columns - 4))
assert(config.height == 3 and config.footer[1][1]:find("1 of 3", 1, true))
keys("<Down>")
assert(vim.api.nvim_win_get_config(menu_win).footer[1][1]:find("2 of 3", 1, true))
keys("<CR>")
assert(records['"'] == "oldest\nnewest", "copy all commits in chronological order")
assert(messages[#messages]:find("clipboard unavailable", 1, true))
keys("y")
keys("jj<CR>")
assert(records['"'] == "oldest\nnewest", "closing the menu must not copy")
vim.fn.setreg = previous_setreg
print("issue copy menu passed")
vim.cmd("qa!")
