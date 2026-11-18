vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.g.mapleader = ","
local events = {}
require("git-branch-flow").setup({
  hooks = {
    before_cherry_pick = function(event)
      events.before = event
    end,
    after_cherry_pick = function(event)
      events.after = event
    end,
  },
})
local git = require("git-branch-flow.git")
local done, data, failure = false, nil, nil
git.load(vim.env.GIT_TEST_REPO, "develop", function(value, err)
  data, failure, done = value, err, true
end)
assert(
  vim.wait(10000, function()
    return done
  end),
  "load timed out"
)
assert(not failure, failure)
require("git-branch-flow.ui").open(data)
vim.wait(100)
local function keys(value)
  vim.fn.feedkeys(vim.api.nvim_replace_termcodes(value, true, false, true), "xt")
end
keys("<CR>")
local source = vim.api.nvim_get_current_buf()
local source_lines = vim.api.nvim_buf_get_lines(source, 0, -1, false)
local found = 0
for index, line in ipairs(source_lines) do
  if line:find("[ ]", 1, true) then
    vim.api.nvim_win_set_cursor(0, { index, 0 })
    keys("<Space>")
    found = found + 1
  end
end
assert(found == 2, "expected two selectable commits")
source_lines = vim.api.nvim_buf_get_lines(source, 0, -1, false)
assert(#vim.tbl_filter(function(line)
  return line:find("[x]", 1, true)
end, source_lines) == 2, "both commits must stay selected")
keys("p")
assert(
  vim.wait(10000, function()
    return vim.api.nvim_get_current_buf() ~= source
  end),
  "review timed out"
)
local review = vim.api.nvim_get_current_buf()
local review_text = table.concat(vim.api.nvim_buf_get_lines(review, 0, -1, false), "\n")
assert(review_text:find("billing first", 1, true))
assert(review_text:find("billing second", 1, true))
local title = vim.api.nvim_win_get_config(0).title
assert(title[2][1]:find("2 commits", 1, true))
keys("G")
keys("y")
assert(
  vim.wait(10000, function()
    local lines = vim.fn.systemlist({ "git", "-C", data.root, "log", "-2", "--format=%s" })
    return lines[1] == "billing second" and lines[2] == "billing first"
  end, 50),
  "both commits were not cherry-picked in order"
)
assert(vim.wait(10000, function()
  return events.after ~= nil
end))
assert(#events.before.commits == 2 and events.after.status == "success")
print("batch UI cherry-pick passed")
vim.cmd("qa!")
