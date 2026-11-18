vim.opt.runtimepath:prepend(vim.fn.getcwd())
local git_summary = require("git-branch-flow.git")
local ui = require("git-branch-flow.ui")
local original_unpushed = git_summary.unpushed_picks
git_summary.unpushed_picks = function(_, callback)
  callback({
    status = "ready",
    commits = {
      {
        sha = "12345678",
        time = 1700000000,
        author = "张三",
        subject = "picked 中文 change",
        issues = { "IMS-1", "IMS-2" },
      },
      {
        sha = "87654321",
        time = 1700000000,
        author = "Test",
        subject = "another change",
        issues = {},
      },
    },
  })
end
vim.o.splitright = false
vim.g.mapleader = ","
require("git-branch-flow").setup({ issue = { width = 20 } })
local data = {
  root = "/tmp",
  branch = "release",
  source_ref = "develop",
  head_sha = "abc",
  source = {
    {
      sha = "aaaaaaaa",
      time = os.time(),
      issues = { "IMS-1" },
      status = "unmatched",
      author = "Test",
      subject = "pending",
      depends_on = {},
      depends_on_commits = {},
    },
  },
  target = {},
}
ui.open(data)
vim.wait(20)
assert(#vim.api.nvim_tabpage_list_wins(0) == 5)
local function assert_balanced()
  local widths = {}
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local bar = vim.wo[win].winbar
    if bar:find("Current:", 1, true) then
      widths.current = vim.api.nvim_win_get_width(win)
    elseif bar:find("Source:", 1, true) then
      widths.source = vim.api.nvim_win_get_width(win)
    end
  end
  assert(widths.current and widths.source and math.abs(widths.current - widths.source) <= 1)
end
local starting_issue_window = vim.api.nvim_get_current_win()
assert_balanced()
-- K opens the commit under the cursor in a floating, scrollable preview.
local source_panel
for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
  if vim.wo[win].winbar:find("Source:", 1, true) then
    source_panel = win
  end
end
local original_run = git_summary.run
local preview_callback
git_summary.run = function(_, args, callback)
  assert(args[#args] == "aaaaaaaa")
  preview_callback = callback
end
vim.api.nvim_set_current_win(source_panel)
vim.api.nvim_win_set_cursor(source_panel, { 2, 0 })
vim.fn.feedkeys("K", "xt")
assert(preview_callback, "K should request the current commit")
local preview_win = vim.api.nvim_get_current_win()
assert(vim.api.nvim_win_get_config(preview_win).relative == "editor")
assert(vim.wo[preview_win].winhighlight == "FloatBorder:GitBranchCompareMerged")
assert(vim.api.nvim_buf_get_lines(0, 0, -1, false)[1]:find("Loading", 1, true))
preview_callback("commit aaaaaaaa\nAuthor: Test\n\ndiff --git a/a b/a\n+added", nil)
assert(vim.bo.filetype == "git")
assert(table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"):find("+added", 1, true))
vim.fn.feedkeys("q", "xt")
assert(vim.api.nvim_get_current_win() == source_panel)
assert(vim.fn.maparg("d", "n", false, true).buffer ~= 1)
git_summary.run = original_run
vim.api.nvim_set_current_win(starting_issue_window)
assert(vim.bo.filetype == "gitbranchissues")
assert(vim.api.nvim_buf_get_name(0):find("Issues", 1, true))
local summary_found = false
for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
  local buf = vim.api.nvim_win_get_buf(win)
  if vim.bo[buf].filetype == "gitbranchsummary" then
    assert(vim.wo[win].winhighlight:find("SignColumn:CursorLine", 1, true))
    local line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
    assert(line:find("Picked: 2", 1, true) and line:find("(H)", 1, true))
    summary_found = true
  end
end
assert(summary_found)
vim.fn.feedkeys("H", "xt")
local picks_detail = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
assert(picks_detail:find("2 commits · 2 issues", 1, true))
assert(
  picks_detail:find(
    "12345678  " .. os.date("%Y-%m-%d", 1700000000) .. "  张三  picked 中文 change",
    1,
    true
  )
)
assert(picks_detail:find("IMS-1, IMS-2", 1, true))
local picks_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
assert(picks_lines[5] == "" and picks_lines[#picks_lines] == "   No issue")
local picks_ns = vim.api.nvim_get_namespaces().git_branch_compare
local picks_marks = vim.api.nvim_buf_get_extmarks(0, picks_ns, 0, -1, { details = true })
local function has_pick_color(row, col, group)
  for _, mark in ipairs(picks_marks) do
    if mark[2] == row and mark[3] == col and mark[4].hl_group == group then
      return true
    end
  end
  return false
end
local summary_line = vim.api.nvim_buf_get_lines(0, 0, 1, false)[1]
assert(
  has_pick_color(0, summary_line:find("2 commits", 1, true) - 1, "GitBranchCompareConflictSummary")
)
assert(has_pick_color(2, 0, "GitBranchCompareIndex"))
assert(has_pick_color(2, 3, "DiagnosticWarn"))
assert(has_pick_color(2, 13, "DiagnosticHint"))
assert(has_pick_color(2, 25, "DiagnosticInfo"))
assert(has_pick_color(2, 25 + #"张三" + 2, "GitBranchCompareMessage"))
assert(has_pick_color(3, 3, "DiagnosticInfo"))
assert(has_pick_color(6, 3, "Comment"))
vim.fn.feedkeys("q", "xt")
local starting_win = vim.api.nvim_get_current_win()
for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
  if
    vim.wo[win].winbar:find("Current:", 1, true) or vim.wo[win].winbar:find("Source:", 1, true)
  then
    vim.api.nvim_set_current_win(win)
    vim.fn.feedkeys("H", "xt")
    assert(
      table
        .concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
        :find("2 commits · 2 issues", 1, true)
    )
    vim.fn.feedkeys("q", "xt")
    vim.fn.feedkeys("g?", "xt")
    assert(
      table
        .concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
        :find("H           Show unpushed cherry-picks", 1, true)
    )
    vim.fn.feedkeys("q", "xt")
  end
end
vim.api.nvim_set_current_win(starting_win)
git_summary.unpushed_picks = original_unpushed
local issue_win = vim.api.nvim_get_current_win()
assert(vim.wo[issue_win].winfixwidth)
assert(vim.wo[issue_win].winbar == "")
local sidebar = vim.api.nvim_buf_get_lines(0, 0, -1, false)
assert(not table.concat(sidebar, "\n"):find("Merged History:", 1, true), "List duplicates header")
local header_win
for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
  if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "gitbranchheader" then
    header_win = win
  end
end
assert(header_win)
assert(
  #vim.api.nvim_buf_get_extmarks(
      vim.api.nvim_win_get_buf(header_win),
      vim.api.nvim_get_namespaces().git_branch_compare_position,
      0,
      -1,
      {}
    ) == 0,
  "Position must not cover tabs in a narrow sidebar"
)
local header = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(header_win), 0, -1, false)
assert(header[1] == "Merged History: 90d (R)ange (b)ranch")
assert(header[2] == "Help: g?" and header[3] == "" and header[5] == "")
assert(header[4]:find("Pending", 1, true))
assert(header[6]:find("Issue ↑", 1, true) and header[6]:find("Status", 1, true))
assert(vim.wo[header_win].statusline:find("WinSeparator", 1, true))
local separator = vim.api.nvim_eval_statusline(vim.wo[header_win].statusline, {
  winid = header_win,
  maxwidth = vim.api.nvim_win_get_width(header_win),
}).str
assert(not separator:find("<", 1, true), "Sidebar separator is truncated")
assert(vim.fn.strdisplaywidth(separator) == vim.api.nvim_win_get_width(header_win))
assert(separator == " " .. string.rep("─", vim.api.nvim_win_get_width(header_win) - 2) .. " ")
vim.api.nvim_win_set_width(header_win, 24)
local resized_width = vim.api.nvim_win_get_width(header_win)
local resized_separator = vim.api.nvim_eval_statusline(vim.wo[header_win].statusline, {
  winid = header_win,
  maxwidth = resized_width,
}).str
assert(resized_separator == " " .. string.rep("─", resized_width - 2) .. " ")
vim.api.nvim_win_set_width(header_win, 20)
assert(sidebar[1]:match("0/1%s+U"))
assert(sidebar[1]:find("IMS-1", 1, true))
assert(vim.api.nvim_win_get_cursor(issue_win)[1] == 1)
assert(vim.fn.maparg("<Space>", "n", false, true).buffer ~= 1)
vim.fn.feedkeys("y", "xt")
assert(vim.api.nvim_win_get_config(0).title[1][1] == " Copy to clipboard ")
assert(vim.api.nvim_win_get_cursor(0)[1] == 1)
assert(vim.api.nvim_win_get_height(0) == 3)
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), {
  "  Issue",
  "c Related commits",
  "  Cancel",
}))
vim.fn.feedkeys("j", "xt")
assert(vim.api.nvim_win_get_cursor(0)[1] == 2)
assert(vim.api.nvim_win_get_config(0).footer[1][1] == " 2 of 3 ")
vim.fn.feedkeys("k", "xt")
vim.fn.feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "xt")
assert(vim.fn.getreg('"') == "IMS-1")
vim.fn.feedkeys("y", "xt")
vim.fn.feedkeys("c", "xt")
assert(vim.fn.getreg('"') == "aaaaaaaa")
assert(vim.api.nvim_get_current_win() == issue_win)
vim.fn.feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "xt")
assert(vim.api.nvim_get_current_win() ~= issue_win)
assert(vim.api.nvim_buf_get_name(0):find("Source", 1, true))
assert(vim.api.nvim_buf_get_lines(0, 1, 2, false)[1]:find("[ ]", 1, true))
vim.fn.feedkeys(" ", "xt")
local selection_ns = vim.api.nvim_get_namespaces().git_branch_compare
local function selected_rows()
  local rows = {}
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(0, selection_ns, 0, -1, { details = true })) do
    if mark[4].line_hl_group == "GitBranchCompareSelected" then
      rows[mark[2] + 1] = true
    end
  end
  return rows
end
assert(selected_rows()[2] and selected_rows()[3])
local source_win = vim.api.nvim_get_current_win()
vim.fn.feedkeys("g?", "xt")
assert(vim.api.nvim_get_current_win() ~= source_win)
local help_title = vim.api.nvim_win_get_config(0).title
assert(vim.api.nvim_win_get_config(0).title_pos == "left")
assert(help_title[1][1] == " Keybindings " and help_title[1][2] == "GitBranchCompareHelpHeading")
local source_help = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
assert(source_help:find("Select or deselect", 1, true))
assert(source_help:find("Equivalent change included", 1, true))
assert(source_help:find("Keyboard shortcuts", 1, true))
assert(source_help:find("g?          Show this help\n\n            ── Commit Status", 1, true))
assert(not source_help:find("merged-history", 1, true))
assert(not source_help:find("Close comparison", 1, true))
vim.fn.feedkeys("q", "xt")
assert(vim.api.nvim_get_current_win() == source_win)
assert(vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == "")
assert(vim.api.nvim_buf_get_lines(0, 1, 2, false)[1]:find("[x]", 1, true))
assert(not vim.api.nvim_buf_get_lines(0, 1, 2, false)[1]:find("pending", 1, true))
local source_item = vim.api.nvim_buf_get_lines(0, 1, 3, false)
assert(source_item[2]:find("pending", 1, true) == source_item[1]:find("aaaaaaaa", 1, true) + 2)
vim.api.nvim_win_set_cursor(0, { 3, 0 })
vim.fn.feedkeys(" ", "xt")
assert(vim.api.nvim_buf_get_lines(0, 1, 2, false)[1]:find("[ ]", 1, true))
assert(next(selected_rows()) == nil)
vim.fn.feedkeys(" ", "xt")
assert(selected_rows()[2] and selected_rows()[3])
local git = require("git-branch-flow.git")
local model = require("git-branch-flow.model")
local old_resolve, old_dependencies = git.resolve_dependencies, model.dependencies
git.resolve_dependencies = function(_, _, callback)
  callback()
end
model.dependencies = function()
  return {
    { kind = "unmatched", sha = "deadbeef", subject = "dependency" },
    { kind = "missing_issue", ref = "IMS-404" },
  }, { { sha = "deadbeef", status = "unmatched", author = "Tester", subject = "dependency" } }
end
vim.fn.feedkeys("D", "xt")
local dependency_lines = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
assert(dependency_lines:find("Declared dependencies", 1, true))
assert(dependency_lines:find("Dependency commits", 1, true))
assert(dependency_lines:find("missing_issue: IMS-404", 1, true))
assert(not dependency_lines:find("unmatched: deadbeef", 1, true))
vim.fn.feedkeys("q", "xt")
vim.fn.feedkeys("p", "xt")
local review = vim.api.nvim_get_current_win()
assert(vim.wo[review].winhighlight == "FloatBorder:GitBranchCompareMerged")
local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
assert(lines[1] ~= "" and lines[#lines] ~= "")
assert(lines[1]:find("Test", 1, true) and lines[1]:find(os.date("%Y-%m-%d"), 1, true))
assert(lines[1]:match("^1%. %S"))
assert(lines[2]:find("pending", 1, true) == lines[1]:find("aaaaaaaa", 1, true) + 2)
assert(vim.wo[review].winbar:find("2 dependencies", 1, true))
local ns = vim.api.nvim_get_namespaces().git_branch_compare
local marks = vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })
assert(#marks >= 4)
local row_colors = {}
for _, mark in ipairs(marks) do
  assert(mark[4].hl_group ~= "Comment")
  if mark[2] == 0 then
    row_colors[mark[4].hl_group] = true
  end
end
assert(row_colors.DiagnosticHint and row_colors.DiagnosticWarn and row_colors.DiagnosticInfo)
local config = vim.api.nvim_win_get_config(review)
assert(config.row == math.floor((vim.o.lines - vim.o.cmdheight - config.height - 2) / 2))
assert(config.footer[1][1]:find("Cherry-pick", 1, true))
assert(vim.fn.maparg("y", "n", false, true).buffer == 1)
assert(config.title_pos == "left" and config.footer_pos == "center")
vim.fn.feedkeys("q", "xt")
local saved_pick, saved_notify = git.pick, vim.notify
local review_notices, pick_calls = {}, 0
model.dependencies = function()
  local warnings = {}
  for index = 1, 40 do
    table.insert(warnings, { kind = "missing_issue", ref = "ISSUE-" .. index })
  end
  return warnings
end
git.pick = function(_, _, _, _, callback)
  pick_calls = pick_calls + 1
  callback("test stop")
end
vim.notify = function(message)
  table.insert(review_notices, message)
end
vim.fn.feedkeys("p", "xt")
local long_review = vim.api.nvim_get_current_win()
assert(vim.wo[long_review].winbar:find("40 dependencies", 1, true))
vim.fn.feedkeys("y", "xt")
assert(pick_calls == 0 and vim.api.nvim_win_is_valid(long_review))
vim.fn.feedkeys("G", "xt")
vim.fn.feedkeys("y", "xt")
assert(pick_calls == 1 and not vim.api.nvim_win_is_valid(long_review))
git.pick, vim.notify = saved_pick, saved_notify
git.resolve_dependencies, model.dependencies = old_resolve, old_dependencies
vim.fn.feedkeys(",e", "xt")
assert(vim.api.nvim_get_current_win() == issue_win)
vim.fn.feedkeys(",b", "xt")
assert(#vim.api.nvim_tabpage_list_wins(0) == 2)
assert_balanced()
vim.fn.feedkeys(",e", "xt")
assert(#vim.api.nvim_tabpage_list_wins(0) == 5)
assert_balanced()
assert(vim.bo.filetype == "gitbranchissues")
vim.fn.feedkeys(",b", "xt")
assert(#vim.api.nvim_tabpage_list_wins(0) == 2)
vim.fn.feedkeys(",b", "xt")
assert(#vim.api.nvim_tabpage_list_wins(0) == 5)
issue_win = vim.api.nvim_get_current_win()
assert(vim.bo.filetype == "gitbranchissues")
assert(vim.api.nvim_win_get_width(issue_win) == 20)
vim.cmd("rightbelow vsplit")
vim.cmd("close")
vim.api.nvim_exec_autocmds("WinResized", {})
assert(vim.api.nvim_win_get_width(issue_win) == 20)
vim.api.nvim_set_current_win(issue_win)
assert(vim.fn.maparg("g?", "n", false, true).buffer == 1)
vim.fn.feedkeys("g?", "xt")
assert(#vim.api.nvim_tabpage_list_wins(0) == 6)
assert(vim.api.nvim_win_get_config(0).title[1][1] == " Keybindings ")
local issue_help = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
assert(issue_help:find("merged-history", 1, true))
assert(issue_help:find("Issue Status", 1, true))
local legend_colors =
  { green = "GitBranchCompareMerged", yellow = "DiagnosticWarn", red = "DiagnosticError" }
local help_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
local help_marks = vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })
for row, line in ipairs(help_lines) do
  local color = line:match("^↳ (%a+)")
  if legend_colors[color] then
    local found = false
    for _, mark in ipairs(help_marks) do
      if mark[2] == row - 1 and mark[4].hl_group == legend_colors[color] then
        found = mark[3] == 0 and mark[4].end_col == #("↳ " .. color)
      end
    end
    assert(found, "Incorrect dependency legend color: " .. color)
  end
end
assert(issue_help:find("A           All commits included", 1, true))
assert(issue_help:find("Some commits included", 1, true))
assert(issue_help:find("Issue ID in string ascending order", 1, true))
assert(issue_help:find("H           Show unpushed cherry-picks", 1, true))
assert(issue_help:find("Close comparison", 1, true))
assert(issue_help:find("Enter", 1, true))
assert(issue_help:find("Enter / o", 1, true))
assert(not issue_help:find("Space", 1, true))
vim.fn.feedkeys("q", "xt")
assert(#vim.api.nvim_tabpage_list_wins(0) == 5)
local positions = {}
local separator_ns = vim.api.nvim_get_namespaces().git_branch_compare_separator
vim.api.nvim_exec_autocmds("WinResized", {})
assert_balanced()
for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
  local title = vim.wo[win].winbar
  if title:find("Current:", 1, true) or title:find("Source:", 1, true) then
    local marks = vim.api.nvim_buf_get_extmarks(
      vim.api.nvim_win_get_buf(win),
      separator_ns,
      0,
      -1,
      { details = true }
    )
    assert(#marks == 1)
    assert(vim.fn.strdisplaywidth(marks[1][4].virt_text[1][1]) == vim.api.nvim_win_get_width(win))
    assert(marks[1][4].virt_text[1][2] == "WinSeparator")
  end
  if title:find("Current:", 1, true) then
    assert(title:find("release (0)", 1, true))
    assert(vim.wo[win].winhighlight:find("WinBar:Normal", 1, true))
    assert(vim.wo[win].winhighlight:find("WinBarNC:Normal", 1, true))
    assert(not vim.wo[win].cursorline)
    assert(vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(win)) == 1)
    assert(title:find("%#GitBranchCompareCurrent#", 1, true))
    assert(title:find("(K)%#Comment# details", 1, true))
    assert(title:find("%#Comment#", 1, true))
    assert(title:find("%#GitBranchCompareKeys#(", 1, true))
    assert(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win)):find("Current", 1, true))
    vim.g.statusline_winid = win
    vim.g.statusline_winid = nil
  end
  if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "gitbranchissues" then
    positions.issues = vim.api.nvim_win_get_position(win)[2]
  end
  if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "gitbranchissues" then
    assert(vim.api.nvim_win_get_width(win) == 20)
  end
  if title:find("Current:", 1, true) then
    assert(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, 1, false)[1] == "")
    positions.current = vim.api.nvim_win_get_position(win)[2]
  end
  if title:find("Source:", 1, true) then
    assert(vim.wo[win].winhighlight:find("WinBar:Normal", 1, true))
    assert(vim.wo[win].winhighlight:find("WinBarNC:Normal", 1, true))
    assert(vim.wo[win].cursorline)
    assert(not title:find("? help", 1, true))
    assert(title:find("%#GitBranchCompareSource#", 1, true))
    assert(title:find("(Space)%#Comment# select", 1, true))
    assert(title:find("%#Comment#", 1, true))
    assert(title:find("%#GitBranchCompareKeys#(", 1, true))
    positions.source = vim.api.nvim_win_get_position(win)[2]
  end
end
assert(positions.issues < positions.current and positions.current < positions.source)
local found = false
for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
  for _, line in ipairs(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)) do
    if line:find("IMS%-1") then
      found = true
    end
  end
end
assert(found)
local second = vim.deepcopy(data)
second.source[1].issues = { "A" }
second.source[1].status = "included"
local other = vim.deepcopy(second.source[1])
other.sha = "bbbbbbbb"
other.issues = { "任务-22" }
other.status = "unmatched"
other.subject = "second issue"
table.insert(second.source, other)
local equivalent = vim.deepcopy(second.source[1])
equivalent.sha = "cccccccc"
equivalent.status = "equivalent"
table.insert(second.source, equivalent)
second.target = { vim.deepcopy(equivalent) }
require("git-branch-flow").setup({ issue = { width = 40 } })
ui.open(second)
vim.wait(20)
local function issue_position()
  local position_ns = vim.api.nvim_get_namespaces().git_branch_compare_position
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].filetype == "gitbranchheader" then
      local marks = vim.api.nvim_buf_get_extmarks(buf, position_ns, 0, -1, { details = true })
      if marks[1] then
        assert(marks[1][4].virt_text[2][1] == "  ", "Position needs two spaces of right padding")
        return marks[1][4].virt_text[1][1]
      end
    end
  end
end
local function keys(value)
  vim.fn.feedkeys(vim.api.nvim_replace_termcodes(value, true, false, true), "xt")
end
assert(vim.api.nvim_get_current_line():find("任务-22", 1, true))
keys("/missing<CR>")
assert(vim.wo.statusline:find("<Esc>", 1, true))
assert(issue_position() == "0 / 0")
assert(not vim.wo.statusline:find("0 / 0", 1, true))
assert(vim.api.nvim_win_get_cursor(0)[1] == 1)
assert(
  table
    .concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
    :find("No matching issues", 1, true)
)
keys("/<C-u><CR>")
assert(vim.api.nvim_get_current_line():find("任务-22", 1, true))
keys("/missing<Esc>")
assert(vim.api.nvim_get_current_line():find("任务-22", 1, true))
keys("/missing<CR>")
keys("<Tab>")
assert(vim.api.nvim_get_current_line():find("A", 1, true))
assert(not vim.wo.statusline:find("Filter:", 1, true))
keys("/a<CR>")
assert(vim.api.nvim_get_current_line():find("A", 1, true))
keys("<Tab>")
assert(vim.wo.statusline:find("<Esc>", 1, true))
assert(
  table
    .concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
    :find("No matching issues", 1, true)
)
keys("<Esc>")
assert(not vim.wo.statusline:find("Filter:", 1, true))
assert(vim.api.nvim_get_current_line():find("任务-22", 1, true))
vim.fn.feedkeys("\t", "xt")
keys("/<C-u><CR>")
vim.fn.feedkeys("G", "xt")
assert(vim.api.nvim_win_get_cursor(0)[1] == 2)
local last_source
for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
  if vim.wo[win].winbar:find("Source:", 1, true) then
    last_source = win
  end
end
assert(
  table
    .concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(last_source), 0, -1, false), "\n")
    :find("second issue", 1, true)
)
vim.fn.feedkeys("gg", "xt")
assert(vim.api.nvim_win_get_cursor(0)[1] == 1)
local rows = vim.api.nvim_buf_get_lines(0, 0, -1, false)
local sidebar_marks = vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })
local merged_color
for _, mark in ipairs(sidebar_marks) do
  if mark[2] == 0 then
    merged_color = mark[4].hl_group
  end
end
assert(merged_color == "GitBranchCompareMerged")
local first_column = rows[1]:find("2/2", 1, true)
local second_column = rows[2]:find("0/1", 1, true)
assert(
  vim.fn.strdisplaywidth(rows[1]:sub(1, first_column - 1))
    == vim.fn.strdisplaywidth(rows[2]:sub(1, second_column - 1))
)
local source
for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
  if vim.wo[win].winbar:find("Source:", 1, true) then
    source = win
  end
end
local merged_lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(source), 0, -1, false)
assert(merged_lines[2]:find("1. I", 1, true) == 1)
assert(merged_lines[2]:find("aaaaaaaa  " .. os.date("%Y-%m-%d") .. "  Test", 1, true))
assert(merged_lines[3]:find("pending", 1, true) == merged_lines[2]:find("aaaaaaaa", 1, true) + 2)
assert(merged_lines[4] == "")
assert(merged_lines[5]:find("2. E", 1, true) == 1)
assert(vim.wo[source].winbar:find("develop (2)", 1, true))
local second_issue_win = vim.api.nvim_get_current_win()
local original_setreg = vim.fn.setreg
local previous_notify = vim.notify
local yank_notifications = {}
vim.notify = function(message, level)
  table.insert(yank_notifications, { message = message, level = level })
end
local registers = {}
vim.fn.setreg = function(reg, value)
  registers[reg] = value
end
vim.api.nvim_set_current_win(source)
vim.api.nvim_win_set_cursor(source, { 2, 0 })
vim.fn.feedkeys("y", "xt")
assert(registers['"'] == "aaaaaaaa" and registers["+"] == "aaaaaaaa")
assert(yank_notifications[1].message == "Copied commit ID")
assert(yank_notifications[1].level == vim.log.levels.INFO)
vim.fn.feedkeys("j", "xt")
assert(vim.api.nvim_win_get_cursor(source)[1] == 5)
vim.fn.feedkeys("j", "xt")
assert(vim.api.nvim_win_get_cursor(source)[1] == 5)
vim.fn.feedkeys("k", "xt")
assert(vim.api.nvim_win_get_cursor(source)[1] == 2)
vim.api.nvim_set_current_win(second_issue_win)
local function line_color(win, row, column)
  local highlights =
    vim.api.nvim_buf_get_extmarks(vim.api.nvim_win_get_buf(win), ns, 0, -1, { details = true })
  for _, mark in ipairs(highlights) do
    if mark[2] == row - 1 and mark[3] == (column or 0) and mark[4].hl_group then
      return mark[4].hl_group
    end
  end
end
assert(line_color(source, 2) == "GitBranchCompareIndex")
assert(line_color(source, 2, 3) == "GitBranchCompareMerged")
assert(line_color(source, 2, 5) == "DiagnosticWarn")
assert(line_color(source, 2, 15) == "DiagnosticHint")
assert(line_color(source, 2, 27) == "DiagnosticInfo")
assert(line_color(source, 3) == "GitBranchCompareMessage")
assert(line_color(source, 5, 3) == "GitBranchCompareMerged")
for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
  if vim.wo[win].winbar:find("Current:", 1, true) then
    assert(line_color(win, 2, 3) == "GitBranchCompareMerged")
    assert(vim.wo[win].winbar:find("release (1)", 1, true))
    assert(vim.wo[win].cursorline)
    vim.api.nvim_set_current_win(win)
    vim.fn.feedkeys("y", "xt")
    assert(registers['"'] == "cccccccc" and registers["+"] == "cccccccc")
  end
end
vim.fn.setreg = original_setreg
vim.notify = previous_notify
vim.api.nvim_set_current_win(second_issue_win)
vim.fn.feedkeys("j", "xt")
vim.cmd("doautocmd CursorMoved")
for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
  if vim.wo[win].winbar:find("Source:", 1, true) then
    source = win
  end
end
assert(
  vim.api
    .nvim_buf_get_lines(vim.api.nvim_win_get_buf(source), 2, 3, false)[1]
    :find("second issue", 1, true)
)
assert(line_color(source, 2, 3) == "Normal")
assert(line_color(source, 2, 7) == "DiagnosticError")
local original_pick, original_load, original_notify = git.pick, git.load, vim.notify
local notifications = {}
git.resolve_dependencies = function(_, _, callback)
  callback()
end
git.pick = function(_, _, _, _, callback)
  callback(nil)
end
git.load = function(_, _, callback)
  local updated = vim.deepcopy(second)
  updated.head_sha = "new-head"
  updated.source[2].status = "included"
  callback(updated, nil)
end
vim.notify = function(message)
  table.insert(notifications, message)
end
vim.fn.feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "xt")
vim.fn.feedkeys(" ", "xt")
assert(line_color(source, 2, 3) == "DiagnosticWarn")
vim.fn.feedkeys("p", "xt")
vim.fn.feedkeys("y", "xt")
local refreshed = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(source), 0, -1, false)
assert(refreshed[2]:find("1. I", 1, true) == 1)
assert(#notifications == 0)
git.pick, git.load, git.resolve_dependencies, vim.notify =
  original_pick, original_load, old_resolve, original_notify
local empty = vim.deepcopy(data)
empty.source = {}
ui.open(empty)
local empty_cursor = vim.api.nvim_win_get_cursor(0)[1]
vim.fn.feedkeys("Ggg", "xt")
assert(vim.api.nvim_win_get_cursor(0)[1] == empty_cursor)
vim.fn.feedkeys("q", "xt")
for _, role_name in ipairs({ "Issues", "Current", "Source" }) do
  ui.open(data)
  local comparison_tab = vim.api.nvim_get_current_tabpage()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(comparison_tab)) do
    if vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win)):find(role_name, 1, true) then
      vim.api.nvim_set_current_win(win)
      break
    end
  end
  if role_name == "Current" then
    assert(vim.fn.maparg("<Space>", "n", false, true).buffer ~= 1)
    vim.fn.feedkeys("g?", "xt")
    local current_help = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
    assert(current_help:find("commit details and diff", 1, true))
    assert(current_help:find("Equivalent change included", 1, true))
    assert(not current_help:find("Select or deselect", 1, true))
    assert(not current_help:find("Close comparison", 1, true))
    vim.fn.feedkeys("q", "xt")
  end
  local mapping = vim.fn.maparg("q", "n", false, true)
  if role_name ~= "Issues" then
    assert(mapping.buffer ~= 1, role_name .. " has a buffer-local q mapping")
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(comparison_tab)) do
      if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "gitbranchissues" then
        vim.api.nvim_set_current_win(win)
        break
      end
    end
  else
    assert(mapping.buffer == 1)
    vim.fn.feedkeys("o", "xt")
    assert(vim.api.nvim_buf_get_name(0):find("Source", 1, true))
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(comparison_tab)) do
      if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "gitbranchissues" then
        vim.api.nvim_set_current_win(win)
        break
      end
    end
  end
  vim.fn.feedkeys("q", "xt")
  assert(not vim.api.nvim_tabpage_is_valid(comparison_tab), role_name .. " did not close")
end
local dependent = vim.deepcopy(data)
dependent.source[1].issues = { "A-1" }
dependent.source[1].depends_on = {}
local later_commit = vim.deepcopy(dependent.source[1])
later_commit.sha = "cccccccc"
later_commit.depends_on = { "B-1" }
table.insert(dependent.source, later_commit)
local prerequisite = vim.deepcopy(dependent.source[1])
prerequisite.sha = "bbbbbbbb"
prerequisite.issues = { "B-1" }
prerequisite.depends_on = {}
table.insert(dependent.source, prerequisite)
ui.open(dependent)
vim.wait(20)
assert(vim.api.nvim_get_current_line():find("↳", 1, true))
local issue_rows = vim.api.nvim_buf_get_lines(0, 0, -1, false)
local issue_header_text
for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
  local buf = vim.api.nvim_win_get_buf(win)
  if vim.bo[buf].filetype == "gitbranchheader" then
    issue_header_text = vim.api.nvim_buf_get_lines(buf, 5, 6, false)[1]
  end
end
assert(issue_header_text:find("Dep", 1, true) < issue_header_text:find("Status", 1, true))
local dep_col =
  vim.fn.strdisplaywidth(issue_header_text:sub(1, issue_header_text:find("Dep", 1, true) - 1))
local marker_pos = issue_rows[1]:find("↳", 1, true)
assert(vim.fn.strdisplaywidth(issue_rows[1]:sub(1, marker_pos - 1)) == dep_col)
local status_col =
  vim.fn.strdisplaywidth(issue_header_text:sub(1, issue_header_text:find("Status", 1, true) - 1))
for _, line in ipairs(issue_rows) do
  local pos = line:find("U", 1, true)
  assert(vim.fn.strdisplaywidth(line:sub(1, pos - 1)) == status_col)
end
keys("D")
local issue_detail = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
assert(issue_detail:find("B-1", 1, true) and issue_detail:find("not completed", 1, true))
keys("q")
keys("<CR>")
keys("<Space>")
local resolve_dependencies = git.resolve_dependencies
git.resolve_dependencies = function(_, _, callback)
  callback()
end
keys("p")
local blocked_review = vim.api.nvim_get_current_win()
local blocked_text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
assert(blocked_text:find("B-1 — not completed", 1, true))
assert(blocked_text:find("bbbbbbbb", 1, true))
assert(vim.api.nvim_win_get_config(blocked_review).footer[1][1]:find("Cherry-pick", 1, true))
assert(vim.fn.maparg("y", "n", false, true).buffer == 1)
keys("q")
keys(",e")
keys("j")
keys("<CR>")
keys("<Space>")
keys("p")
blocked_text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
assert(blocked_text:find("B-1", 1, true), "Selecting a dependency must not bypass the check")
assert(vim.fn.maparg("y", "n", false, true).buffer == 1)
keys("q")
git.resolve_dependencies = resolve_dependencies
local long = vim.deepcopy(data)
long.source = {}
for index = 1, 60 do
  local item = vim.deepcopy(data.source[1])
  item.sha = ("%040x"):format(index)
  item.issues = { ("SCROLL-%03d"):format(index) }
  table.insert(long.source, item)
end
vim.o.winborder = "rounded"
ui.open(long)
local long_win = vim.api.nvim_get_current_win()
vim.cmd("redraw")
vim.api.nvim_exec_autocmds("WinScrolled", {})
assert(issue_position() == "1 / 60")
assert(not vim.wo[long_win].statusline:find("↓", 1, true))
local function scrollbar_lines()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.b[buf].git_branch_compare_scrollbar then
      return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    end
  end
end
assert(
  vim.wait(1000, function()
    return scrollbar_lines() ~= nil
  end),
  "Scrollbar missing"
)
local top_scrollbar = scrollbar_lines()
assert(top_scrollbar[1] == "┃" and top_scrollbar[#top_scrollbar] == "│")
for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
  if vim.b[vim.api.nvim_win_get_buf(win)].git_branch_compare_scrollbar then
    local config = vim.api.nvim_win_get_config(win)
    assert(config.border == nil or config.border == "none", "Scrollbar has a border")
    assert(config.height == vim.api.nvim_win_get_height(long_win))
  end
end
vim.fn.feedkeys("G", "xt")
vim.cmd("redraw")
vim.cmd("doautocmd CursorMoved")
assert(issue_position() == "60 / 60")
assert(not vim.wo[long_win].statusline:find("↑", 1, true))
assert(not vim.wo[long_win].statusline:find("↓", 1, true))
assert(
  vim.wait(1000, function()
    local bar = scrollbar_lines()
    return bar and bar[1] == "│" and bar[#bar] == "┃"
  end),
  "Scrollbar did not reach the bottom"
)
keys("/SCROLL-001<CR>")
assert(
  vim.wait(1000, function()
    return scrollbar_lines() == nil
  end),
  "Short list has scrollbar"
)
keys("<Esc>")
assert(
  vim.wait(1000, function()
    return scrollbar_lines() ~= nil
  end),
  "Scrollbar did not return"
)
keys("<Tab>")
assert(
  vim.wait(1000, function()
    return scrollbar_lines() ~= nil
  end),
  "View switch lost scrollbar"
)
keys(",b")
assert(
  vim.wait(1000, function()
    return scrollbar_lines() == nil
  end),
  "Hidden sidebar has scrollbar"
)
keys(",e")
assert(
  vim.wait(1000, function()
    return scrollbar_lines() ~= nil
  end),
  "Reopened sidebar lost scrollbar"
)
long_win = vim.api.nvim_get_current_win()
local original_lines = vim.o.lines
vim.o.lines = original_lines + 5
vim.cmd("redraw")
vim.api.nvim_exec_autocmds("WinResized", {})
assert(
  vim.wait(1000, function()
    local bar = scrollbar_lines()
    return bar and #bar == vim.api.nvim_win_get_height(long_win)
  end),
  "Scrollbar height did not follow the window"
)
vim.o.lines = original_lines
local header_visible = false
for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
  local content =
    table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false), "\n")
  if win ~= long_win and content:find("Merged History:", 1, true) then
    header_visible = true
  end
end
assert(header_visible, "Issue header should remain in a separate fixed window")
print("ui smoke test passed")
vim.cmd("qa!")
