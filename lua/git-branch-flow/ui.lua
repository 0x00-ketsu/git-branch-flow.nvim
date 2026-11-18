local config = require("git-branch-flow.config")
local git = require("git-branch-flow.git")
local model = require("git-branch-flow.model")
local M = {}
local ns = vim.api.nvim_create_namespace("git_branch_compare")
local separator_ns = vim.api.nvim_create_namespace("git_branch_compare_separator")
local position_ns = vim.api.nvim_create_namespace("git_branch_compare_position")

---Set distinct colors for comparison states, branch titles, and shortcut hints.
local function set_comparison_highlights()
  vim.api.nvim_set_hl(0, "GitBranchCompareMerged", { fg = "#83c97a", default = true })
  vim.api.nvim_set_hl(
    0,
    "GitBranchCompareHelpHeading",
    { fg = "#83c97a", bold = true, default = true }
  )
  vim.api.nvim_set_hl(0, "GitBranchCompareMessage", { fg = "#ebdbb2", default = true })
  vim.api.nvim_set_hl(0, "GitBranchCompareIndex", { fg = "#d5d5d5", default = true })
  vim.api.nvim_set_hl(0, "GitBranchCompareConflictSummary", { fg = "#91b6cf", default = true })
  vim.api.nvim_set_hl(
    0,
    "GitBranchCompareConflictFile",
    { fg = "#83c97a", italic = true, default = true }
  )
  vim.api.nvim_set_hl(0, "GitBranchCompareScrollTrack", { fg = "#626a70", default = true })
  vim.api.nvim_set_hl(0, "GitBranchCompareScrollThumb", { fg = "#c0c6c8", default = true })
  vim.api.nvim_set_hl(0, "GitBranchCompareSelected", { bg = "#496d88", default = true })
  vim.api.nvim_set_hl(0, "GitBranchCompareMergedBackground", { bg = "#30443c", default = true })
  vim.api.nvim_set_hl(0, "GitBranchCompareCurrent", { fg = "#83b6ef", default = true })
  vim.api.nvim_set_hl(0, "GitBranchCompareRange", { fg = "#b8a3c7", default = true })
  local comment = vim.api.nvim_get_hl(0, { name = "Comment", link = false })
  vim.api.nvim_set_hl(0, "GitBranchCompareHintText", { fg = comment.fg, default = true })
  vim.api.nvim_set_hl(0, "GitBranchCompareSource", { fg = "#66c2a5", default = true })
  vim.api.nvim_set_hl(0, "GitBranchCompareKeys", { link = "DiagnosticWarn", default = true })
end
set_comparison_highlights()
vim.api.nvim_create_autocmd("ColorScheme", { callback = set_comparison_highlights })

---Display one branch comparison in a dedicated tab.
---@param data table
function M.open(data)
  config.emit("on_open", data)
  local state = {
    data = data,
    days = config.options.history_days,
    selected = {},
    issue = nil,
    groups = {},
    rows = {},
    view = "pending",
    filters = { pending = "", all = "" },
    issue_dependencies = nil,
    issue_index = model.issue_index(data.source),
    unpushed = { status = "loading", commits = {} },
  }
  local issue_header = 6
  local function buffer()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].swapfile = false
    return buf
  end
  vim.cmd.tabnew()
  local tab = vim.api.nvim_get_current_tabpage()
  local issue_win = vim.api.nvim_get_current_win()
  local issue_buf = buffer()
  vim.api.nvim_buf_set_name(issue_buf, ("git-branch-compare://%d/Issues"):format(tab))
  vim.bo[issue_buf].filetype = "gitbranchissues"
  vim.bo[issue_buf].bufhidden = "hide"
  vim.api.nvim_win_set_buf(issue_win, issue_buf)
  vim.cmd("rightbelow vsplit")
  local target_win = vim.api.nvim_get_current_win()
  local target_buf = buffer()
  vim.api.nvim_buf_set_name(target_buf, ("git-branch-compare://%d/Current"):format(tab))
  vim.b[target_buf].branch_compare_role = { name = "CURRENT", branch = data.branch }
  vim.api.nvim_win_set_buf(target_win, target_buf)
  vim.cmd("rightbelow vsplit")
  local source_win = vim.api.nvim_get_current_win()
  local source_buf = buffer()
  vim.api.nvim_buf_set_name(source_buf, ("git-branch-compare://%d/Source"):format(tab))
  vim.b[source_buf].branch_compare_role = { name = "SOURCE", branch = data.source_ref }
  vim.api.nvim_win_set_buf(source_win, source_buf)
  local width = tonumber(config.options.issue.width)
  if not width or width < 1 then
    width = vim.o.columns > 220 and 48 or 43
  end
  vim.api.nvim_win_set_width(issue_win, math.floor(width))
  vim.wo[issue_win].winfixwidth = true
  vim.api.nvim_set_current_win(issue_win)
  local header_buf = buffer()
  vim.bo[header_buf].bufhidden = "hide"
  vim.bo[header_buf].filetype = "gitbranchheader"
  local header_win
  vim.api.nvim_create_autocmd("WinEnter", {
    buffer = header_buf,
    callback = function()
      if vim.api.nvim_win_is_valid(issue_win) then
        vim.api.nvim_set_current_win(issue_win)
      end
    end,
  })
  ---Create the fixed, non-editable sidebar header above the issue list.
  local function open_issue_header()
    vim.api.nvim_set_current_win(issue_win)
    vim.cmd("leftabove 6split")
    header_win = vim.api.nvim_get_current_win()
    vim.api.nvim_set_current_win(issue_win)
    vim.api.nvim_win_set_buf(header_win, header_buf)
    vim.wo[header_win].winfixheight = true
    vim.wo[header_win].number = false
    vim.wo[header_win].relativenumber = false
    vim.wo[header_win].wrap = false
    vim.wo[header_win].statusline = (" %%#WinSeparator#%%{repeat('─',max([0,winwidth(%d)-2]))} "):format(
      header_win
    )
    vim.api.nvim_set_current_win(issue_win)
    vim.wo[issue_win].scrolloff = 0
  end
  open_issue_header()
  local summary_buf = buffer()
  vim.bo[summary_buf].bufhidden = "hide"
  vim.bo[summary_buf].filetype = "gitbranchsummary"
  local summary_win
  ---Create the fixed summary below the issue list.
  local function open_issue_summary()
    vim.api.nvim_set_current_win(issue_win)
    vim.cmd("belowright 1split")
    summary_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(summary_win, summary_buf)
    vim.wo[summary_win].winfixheight = true
    vim.wo[summary_win].number = false
    vim.wo[summary_win].relativenumber = false
    vim.wo[summary_win].wrap = false
    local existing = vim.wo[summary_win].winhighlight
    vim.wo[summary_win].winhighlight = (existing == "" and "" or existing .. ",")
      .. "SignColumn:CursorLine"
    vim.api.nvim_set_current_win(issue_win)
  end
  vim.api.nvim_create_autocmd("WinEnter", {
    buffer = summary_buf,
    callback = function()
      if vim.api.nvim_win_is_valid(issue_win) then
        vim.api.nvim_set_current_win(issue_win)
      end
    end,
  })
  open_issue_summary()
  for _, win in ipairs({ issue_win, target_win, source_win }) do
    vim.wo[win].number = false
    vim.wo[win].relativenumber = false
    vim.wo[win].wrap = false
    vim.wo[win].cursorline = true
  end
  for _, win in ipairs({ target_win, source_win }) do
    local existing = vim.wo[win].winhighlight
    vim.wo[win].winhighlight = (existing == "" and "" or existing .. ",")
      .. "WinBar:Normal,WinBarNC:Normal"
  end
  ---Balance the commit panels while preserving the issue sidebar width.
  local function balance_panels()
    if not vim.api.nvim_win_is_valid(target_win) or not vim.api.nvim_win_is_valid(source_win) then
      return
    end
    local current_width = vim.api.nvim_win_get_width(target_win)
    local source_width = vim.api.nvim_win_get_width(source_win)
    if math.abs(current_width - source_width) > 1 then
      vim.api.nvim_win_set_width(target_win, math.floor((current_width + source_width) / 2))
    end
  end
  balance_panels()
  local function put(buf, lines, highlights)
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, #lines > 0 and lines or { "(empty)" })
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    for row, group in pairs(highlights or {}) do
      vim.api.nvim_buf_add_highlight(buf, ns, group, row - 1, 0, -1)
    end
    vim.bo[buf].modifiable = false
    vim.bo[buf].modified = false
  end
  local function esc(text)
    return text:gsub("%%", "%%%%")
  end
  ---Update the summary without replacing newer asynchronous results.
  local picks_generation = 0
  local function render_picks()
    if not summary_win or not vim.api.nvim_win_is_valid(summary_win) then
      return
    end
    local picks = state.unpushed
    local text
    local has_picks = picks.status == "ready" and #picks.commits > 0
    if picks.status == "ready" then
      local issues = {}
      for _, item in ipairs(picks.commits) do
        for _, issue in ipairs(item.issues) do
          issues[issue] = true
        end
      end
      local count = #picks.commits
      local issue_count = vim.tbl_count(issues)
      text = ("Picked: %d commit%s · %d issue%s  (H)"):format(
        count,
        count == 1 and "" or "s",
        issue_count,
        issue_count == 1 and "" or "s"
      )
      if vim.fn.strdisplaywidth(text) > vim.api.nvim_win_get_width(summary_win) then
        text = ("Picked: %d  (H)"):format(count)
      end
    elseif picks.status == "no_upstream" then
      text = "Upstream not configured  (H)"
    elseif picks.status == "error" then
      text = "Cherry-pick status unavailable  (H)"
    else
      text = "Checking cherry-picks…  (H)"
    end
    put(summary_buf, { text }, { has_picks and "GitBranchCompareMerged" or "DiagnosticInfo" })
    if has_picks then
      local start = text:find("(H)", 1, true)
      vim.api.nvim_buf_add_highlight(summary_buf, ns, "GitBranchCompareKeys", 0, start - 1, -1)
    end
  end
  local function refresh_picks()
    picks_generation = picks_generation + 1
    local generation = picks_generation
    git.unpushed_picks(data.root, function(result, err)
      if not vim.api.nvim_tabpage_is_valid(tab) or generation ~= picks_generation then
        return
      end
      state.unpushed = err and { status = "error", commits = {} } or result
      render_picks()
    end)
  end
  render_picks()
  local scrollbar_win, scrollbar_buf, scrollbar_pending, scrollbar_signature
  ---Refresh the issue viewport indicator after scrolling or layout changes.
  local function update_issue_scrollbar()
    if scrollbar_pending then
      return
    end
    scrollbar_pending = true
    vim.schedule(function()
      scrollbar_pending = false
      if not vim.api.nvim_tabpage_is_valid(tab) then
        return
      end
      local visible = vim.api.nvim_win_is_valid(issue_win)
        and vim.api.nvim_get_current_tabpage() == tab
      local height = visible and vim.api.nvim_win_get_height(issue_win) or 0
      local total = #state.groups
      if not visible or height < 1 or total <= height then
        if scrollbar_win and vim.api.nvim_win_is_valid(scrollbar_win) then
          vim.api.nvim_win_close(scrollbar_win, true)
        end
        scrollbar_win = nil
        scrollbar_signature = nil
        return
      end
      local width = vim.api.nvim_win_get_width(issue_win)
      local view = vim.fn.getwininfo(issue_win)[1]
      local top = math.max(1, math.min(view.topline, total - height + 1))
      local signature = table.concat({ issue_win, width, height, total, top }, ":")
      if
        scrollbar_signature == signature
        and scrollbar_win
        and vim.api.nvim_win_is_valid(scrollbar_win)
      then
        return
      end
      local thumb = math.max(1, math.min(height - 1, math.floor(height * height / total)))
      local offset = math.floor((top - 1) * (height - thumb) / (total - height) + 0.5)
      if not scrollbar_buf or not vim.api.nvim_buf_is_valid(scrollbar_buf) then
        scrollbar_buf = buffer()
        vim.bo[scrollbar_buf].bufhidden = "hide"
        vim.b[scrollbar_buf].git_branch_compare_scrollbar = true
      end
      local lines, colors = {}, {}
      for row = 1, height do
        local active = row > offset and row <= offset + thumb
        lines[row] = active and "┃" or "│"
        colors[row] = active and "GitBranchCompareScrollThumb" or "GitBranchCompareScrollTrack"
      end
      put(scrollbar_buf, lines, colors)
      local config = {
        relative = "win",
        win = issue_win,
        row = 0,
        col = width - 1,
        width = 1,
        height = height,
        style = "minimal",
        border = "none",
        focusable = false,
        mouse = false,
        zindex = 45,
        noautocmd = true,
      }
      if scrollbar_win and vim.api.nvim_win_is_valid(scrollbar_win) then
        vim.api.nvim_win_set_config(scrollbar_win, config)
      else
        scrollbar_win = vim.api.nvim_open_win(scrollbar_buf, false, config)
        vim.wo[scrollbar_win].winhighlight = "Normal:Normal,NormalFloat:Normal"
      end
      scrollbar_signature = signature
    end)
  end
  ---Show the filter in the statusline and the current position beside the tabs.
  local function update_issue_footer()
    if not vim.api.nvim_win_is_valid(issue_win) then
      return
    end
    local filter = state.filters[state.view]
    local total = #state.groups
    local index = total == 0 and 0 or vim.api.nvim_win_get_cursor(issue_win)[1]
    local position = index .. " / " .. total
    if
      header_win
      and vim.api.nvim_win_is_valid(header_win)
      and vim.api.nvim_buf_is_valid(header_buf)
    then
      vim.api.nvim_buf_clear_namespace(header_buf, position_ns, 0, -1)
      local tabs = vim.api.nvim_buf_get_lines(header_buf, 3, 4, false)[1]
      if
        tabs
        and vim.fn.strdisplaywidth(tabs) + vim.fn.strdisplaywidth(position) + 4
          <= vim.api.nvim_win_get_width(header_win)
      then
        vim.api.nvim_buf_set_extmark(header_buf, position_ns, 3, 0, {
          virt_text = { { position, "Normal" }, { "  ", "Normal" } },
          virt_text_pos = "right_align",
        })
      end
    end
    local available = vim.api.nvim_win_get_width(issue_win) - 2
    local left = ""
    if filter ~= "" and available > 0 then
      local hint = "<Esc>: Clear filter"
      if available < vim.fn.strdisplaywidth(hint) + 9 then
        hint = "<Esc>"
      end
      local limit = math.max(0, available - vim.fn.strdisplaywidth(hint) - 9)
      local value = filter
      if vim.fn.strdisplaywidth(value) > limit then
        value = ""
        for index = 0, vim.fn.strchars(filter) - 1 do
          local char = vim.fn.strcharpart(filter, index, 1)
          if vim.fn.strdisplaywidth(value .. char .. "…") > limit then
            break
          end
          value = value .. char
        end
        if limit > 0 then
          value = value .. "…"
        end
      end
      if available >= 15 then
        left = "%#Normal#Filter: " .. esc(value) .. "  %#DiagnosticInfo#" .. hint
      elseif available >= 5 then
        left = "%#DiagnosticInfo#<Esc>"
      end
    end
    vim.wo[issue_win].statusline = left .. "%#Normal#"
    update_issue_scrollbar()
  end
  local function titles()
    vim.wo[target_win].winbar = "%#GitBranchCompareCurrent# Current: "
      .. esc(data.branch)
      .. (" (%d)"):format(math.floor((#state.rows.target + 1) / 3))
      .. " %#GitBranchCompareKeys#(d)%#Comment#iff "
      .. "%#GitBranchCompareKeys#(D)%#Comment#eps "
      .. "%#GitBranchCompareKeys#(y)%#Comment#ank"
    vim.wo[source_win].winbar = "%#GitBranchCompareSource# Source: "
      .. esc(data.source_ref)
      .. (" (%d)"):format(math.floor((#state.rows.source + 1) / 3))
      .. " %#GitBranchCompareKeys#(Space)%#Comment# select "
      .. "%#GitBranchCompareKeys#(p)%#Comment#ick "
      .. "%#GitBranchCompareKeys#(r)%#Comment#efresh "
      .. "%#GitBranchCompareKeys#(y)%#Comment#ank"
  end
  ---Draw separators across the current widths of the commit panels.
  local function draw_separators()
    for _, panel in ipairs({ { target_win, target_buf }, { source_win, source_buf } }) do
      local win, buf = panel[1], panel[2]
      if vim.api.nvim_win_is_valid(win) and vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_clear_namespace(buf, separator_ns, 0, -1)
        vim.api.nvim_buf_set_extmark(buf, separator_ns, 0, 0, {
          virt_text = { { string.rep("─", vim.api.nvim_win_get_width(win)), "WinSeparator" } },
          virt_text_pos = "overlay",
        })
      end
    end
  end
  local function render_commits()
    local group
    for _, item in ipairs(state.groups) do
      if item.id == state.issue then
        group = item
        break
      end
    end
    local target_lines, source_lines = { "" }, { "" }
    local target_fields, source_fields = {}, {}
    local markers = { included = "I", equivalent = "E", unmatched = "U" }
    local colors = {
      included = "GitBranchCompareMerged",
      equivalent = "GitBranchCompareMerged",
      unmatched = "DiagnosticError",
    }
    state.rows = { target = {}, source = {} }
    if group then
      local cutoff = state.days and (os.time() - state.days * 86400) or nil
      for _, item in ipairs(data.target) do
        if
          vim.tbl_contains(item.issues, group.id)
          and (item.status == "unmatched" or not cutoff or item.time >= cutoff)
        then
          if #state.rows.target > 0 then
            table.insert(state.rows.target, false)
            table.insert(target_lines, "")
          end
          local number = ("%d. "):format(math.floor((#state.rows.target + 1) / 3) + 1)
          table.insert(state.rows.target, item)
          table.insert(state.rows.target, item)
          table.insert(
            target_lines,
            ("%s%s %s  %s  %s"):format(
              number,
              markers[item.status],
              item.sha:sub(1, 8),
              os.date("%Y-%m-%d", item.time),
              item.author
            )
          )
          table.insert(target_lines, string.rep(" ", #number + 4) .. item.subject)
          target_fields[#target_lines - 1] = { item = item, number = number, prefix = "" }
        end
      end
      for _, item in ipairs(group.commits) do
        if #state.rows.source > 0 then
          table.insert(state.rows.source, false)
          table.insert(source_lines, "")
        end
        local number = ("%d. "):format(math.floor((#state.rows.source + 1) / 3) + 1)
        table.insert(state.rows.source, item)
        table.insert(state.rows.source, item)
        local prefix = item.status == "unmatched"
            and (state.selected[item.sha] and "[x] " or "[ ] ")
          or ""
        table.insert(
          source_lines,
          ("%s%s%s %s  %s  %s"):format(
            number,
            prefix,
            markers[item.status],
            item.sha:sub(1, 8),
            os.date("%Y-%m-%d", item.time),
            item.author
          )
        )
        source_fields[#source_lines] = { item = item, number = number, prefix = prefix }
        table.insert(source_lines, string.rep(" ", #number + #prefix + 4) .. item.subject)
      end
    end
    put(target_buf, target_lines)
    put(source_buf, source_lines)
    for row, field in pairs(source_fields) do
      if state.selected[field.item.sha] then
        for _, line in ipairs({ row - 1, row }) do
          vim.api.nvim_buf_set_extmark(source_buf, ns, line, 0, {
            line_hl_group = "GitBranchCompareSelected",
            priority = 110,
          })
        end
      end
    end
    ---Highlight commit fields independently of their merge status.
    local function highlight_fields(buf, fields)
      for row, field in pairs(fields) do
        local item, number, prefix = field.item, field.number, field.prefix
        if item.status == "included" or item.status == "equivalent" then
          for _, line in ipairs({ row - 1, row }) do
            vim.api.nvim_buf_set_extmark(buf, ns, line, 0, {
              virt_text = { { "▌ ", "GitBranchCompareMerged" } },
              virt_text_pos = "inline",
              line_hl_group = "GitBranchCompareMergedBackground",
              priority = 90,
            })
          end
        end
        local col = #number + #prefix
        vim.api.nvim_buf_add_highlight(buf, ns, "GitBranchCompareIndex", row - 1, 0, #number)
        if prefix ~= "" then
          vim.api.nvim_buf_add_highlight(
            buf,
            ns,
            state.selected[item.sha] and "DiagnosticWarn" or "Normal",
            row - 1,
            #number,
            #number + 3
          )
        end
        vim.api.nvim_buf_add_highlight(buf, ns, colors[item.status], row - 1, col, col + 1)
        col = col + 2
        local sha = item.sha:sub(1, 8)
        vim.api.nvim_buf_add_highlight(buf, ns, "DiagnosticWarn", row - 1, col, col + #sha)
        col = col + #sha + 2
        vim.api.nvim_buf_add_highlight(buf, ns, "DiagnosticHint", row - 1, col, col + 10)
        col = col + 12
        vim.api.nvim_buf_add_highlight(buf, ns, "DiagnosticInfo", row - 1, col, -1)
        vim.api.nvim_buf_add_highlight(buf, ns, "GitBranchCompareMessage", row, 0, -1)
      end
    end
    highlight_fields(target_buf, target_fields)
    highlight_fields(source_buf, source_fields)
    draw_separators()
    vim.wo[target_win].cursorline = #state.rows.target > 0
    vim.wo[source_win].cursorline = #state.rows.source > 0
    for _, win in ipairs({ target_win, source_win }) do
      if
        vim.api.nvim_win_get_cursor(win)[1] == 1
        and vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(win)) > 1
      then
        vim.api.nvim_win_set_cursor(win, { 2, 0 })
      end
    end
    titles()
  end
  local function render()
    local all_groups = model.groups(data.source, state.days and state.days * 86400, os.time())
    local pending = 0
    state.groups = {}
    local filter = vim.fn.tolower(state.filters[state.view])
    for _, group in ipairs(all_groups) do
      if group.state ~= "included" then
        pending = pending + 1
      end
      if
        (state.view == "all" or group.state ~= "included")
        and vim.fn.tolower(group.id):find(filter, 1, true)
      then
        table.insert(state.groups, group)
      end
    end
    if
      not vim.tbl_contains(
        vim.tbl_map(function(group)
          return group.id
        end, state.groups),
        state.issue
      )
    then
      state.issue = state.groups[1] and state.groups[1].id or nil
    end
    local issue_width, count_width = vim.fn.strdisplaywidth("Issue ↑"), #"Merged"
    for _, group in ipairs(state.groups) do
      issue_width = math.max(issue_width, vim.fn.strdisplaywidth(group.id))
      count_width = math.max(count_width, #(group.included .. "/" .. #group.commits))
    end
    local function pad(text, width)
      return text .. string.rep(" ", math.max(0, width - vim.fn.strdisplaywidth(text)))
    end
    local range = state.days and (tostring(state.days) .. "d") or "all"
    local header = {
      ("Merged History: %s (R)ange (b)ranch"):format(range),
      "Help: g?",
      "",
      ("Pending (%d)  All (%d)"):format(pending, #all_groups),
      "",
      pad("Issue ↑", issue_width) .. "  " .. pad("Merged", count_width) .. "  Dep  Status",
    }
    local lines, colors, dependency_marks = {}, {}, {}
    local markers = { included = "A", partial = "P", unmatched = "U" }
    for _, group in ipairs(state.groups) do
      local count = group.included .. "/" .. #group.commits
      local dependency = state.issue_dependencies and state.issue_dependencies[group.id]
      local entry = state.issue_index[group.id]
      local has_dependency = entry and next(entry.dependencies) ~= nil
      local marker = has_dependency and ((dependency or state.dependency_error) and "↳" or "…")
        or ""
      local prefix = pad(group.id, issue_width) .. "  " .. pad(count, count_width) .. "  "
      if marker ~= "" then
        dependency_marks[#lines + 1] = { start = #prefix, text = marker }
      end
      table.insert(
        lines,
        prefix
          .. pad(marker, 3)
          .. "  "
          .. markers[group.state]
          .. (group.limited and " (limited)" or "")
      )
      colors[#lines] = group.state == "included" and "GitBranchCompareMerged"
        or group.state == "partial" and "DiagnosticWarn"
        or "DiagnosticError"
    end
    if #state.groups == 0 then
      table.insert(
        lines,
        filter ~= "" and "No matching issues"
          or state.view == "pending" and "No pending issues"
          or "No issues"
      )
      colors[#lines] = "Comment"
    end
    put(issue_buf, lines, colors)
    for index, group in ipairs(state.groups) do
      local dependency = state.issue_dependencies and state.issue_dependencies[group.id]
      local marker = dependency_marks[index]
      if marker then
        local color = state.dependency_error and "DiagnosticError"
          or not dependency and "DiagnosticInfo"
          or dependency.status == "unknown" and "DiagnosticError"
          or dependency.status == "pending" and "DiagnosticWarn"
          or "GitBranchCompareMerged"
        vim.api.nvim_buf_add_highlight(
          issue_buf,
          ns,
          color,
          index - 1,
          marker.start,
          marker.start + #marker.text
        )
      end
    end
    put(header_buf, header, { [2] = "Comment", [issue_header] = "Title" })
    local function accent(row, text, group)
      local start = header[row]:find(text, 1, true)
      if start then
        vim.api.nvim_buf_add_highlight(header_buf, ns, group, row - 1, start - 1, start - 1 + #text)
      end
    end
    accent(1, "Merged History:", "Comment")
    accent(1, "ange", "GitBranchCompareHintText")
    accent(1, "ranch", "GitBranchCompareHintText")
    accent(1, range, "GitBranchCompareRange")
    accent(1, "(R)", "DiagnosticWarn")
    accent(1, "(b)", "DiagnosticWarn")
    accent(2, "g?", "DiagnosticInfo")
    accent(
      4,
      state.view == "pending" and ("Pending (" .. pending .. ")") or ("All (" .. #all_groups .. ")"),
      "GitBranchCompareHelpHeading"
    )
    for index, group in ipairs(state.groups) do
      if group.id == state.issue then
        if vim.api.nvim_win_is_valid(issue_win) then
          vim.api.nvim_win_set_cursor(issue_win, { index, 0 })
        end
        break
      end
    end
    if vim.api.nvim_win_is_valid(issue_win) then
      if #state.groups == 0 then
        vim.api.nvim_win_set_cursor(issue_win, { 1, 0 })
      end
      update_issue_footer()
    end
    render_commits()
  end
  ---Calculate Issue dependency states without blocking the initial render.
  local function refresh_issue_dependencies()
    state.issue_dependencies = nil
    state.dependency_error = nil
    state.issue_index = model.issue_index(data.source)
    local snapshot = data
    local index = state.issue_index
    local groups = model.groups(snapshot.source, nil, os.time())
    local results, position = {}, 1
    local function batch()
      if not vim.api.nvim_tabpage_is_valid(tab) or data ~= snapshot then
        return
      end
      local ok, err = pcall(function()
        for _ = 1, 10 do
          local group = groups[position]
          if not group then
            break
          end
          results[group.id] = model.issue_dependencies(snapshot.source, group.id, index)
          position = position + 1
        end
      end)
      if not ok then
        state.dependency_error = tostring(err)
        render()
      elseif position > #groups then
        state.issue_dependencies = results
        render()
      else
        vim.schedule(batch)
      end
    end
    vim.schedule(batch)
  end
  local function current_commit()
    local win = vim.api.nvim_get_current_win()
    local rows = win == source_win and state.rows.source or win == target_win and state.rows.target
    return rows and rows[vim.api.nvim_win_get_cursor(win)[1] - 1]
  end
  local function preview()
    local item = current_commit()
    if not item then
      return
    end
    git.run(
      data.root,
      { "show", "--no-ext-diff", "--format=fuller", "--stat", "--patch", item.sha },
      function(out, err)
        if err then
          return vim.notify(err, vim.log.levels.ERROR)
        end
        if not vim.api.nvim_tabpage_is_valid(tab) or vim.api.nvim_get_current_tabpage() ~= tab then
          return
        end
        local buf = vim.api.nvim_create_buf(false, true)
        vim.bo[buf].bufhidden = "wipe"
        vim.bo[buf].buftype = "nofile"
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(out, "\n", { plain = true }))
        vim.bo[buf].filetype = "git"
        vim.bo[buf].modifiable = false
        vim.cmd("botright new")
        vim.api.nvim_win_set_buf(0, buf)
        vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, desc = "Close commit preview" })
      end
    )
  end
  ---Show possible prior commits without changing the active conflict until confirmed.
  local function show_conflict_candidates(result, aborted)
    if not vim.api.nvim_tabpage_is_valid(tab) then
      return
    end
    local lines, highlights =
      {
        ("%d conflict %s · %d possible related %s"):format(#result.files, #result.files == 1 and "file" or "files", #result.candidates, #result.candidates == 1 and "commit" or "commits"),
        "",
      }, {}
    table.insert(highlights, { 0, "GitBranchCompareConflictSummary", 0, -1 })
    if #result.candidates == 0 then
      table.insert(lines, "No related commits found that may need to be applied first.")
      table.insert(
        lines,
        aborted and "After restarting the cherry-pick, resolve any conflicts manually."
          or "Resolve the conflict manually."
      )
      table.insert(lines, "")
      table.insert(lines, "Conflict files:")
      for _, file in ipairs(result.files) do
        table.insert(lines, "   " .. file)
        table.insert(highlights, { #lines - 1, "GitBranchCompareConflictFile", 0, -1 })
      end
    else
      table.insert(lines, "These commits may need to be applied first.")
      table.insert(lines, "")
    end
    for index, candidate in ipairs(result.candidates) do
      if index > 1 then
        table.insert(lines, "")
      end
      local item = candidate.commit
      local number = ("%d. "):format(index)
      table.insert(lines, number .. item.sha:sub(1, 8) .. "  " .. item.subject)
      local row = #lines - 1
      table.insert(highlights, { row, "GitBranchCompareIndex", 0, #number })
      table.insert(highlights, { row, "DiagnosticWarn", #number, #number + 8 })
      table.insert(highlights, { row, "GitBranchCompareMessage", #number + 10, -1 })
      if #item.issues > 0 then
        table.insert(lines, "   Issues: " .. table.concat(item.issues, ", "))
        table.insert(highlights, { #lines - 1, "DiagnosticInfo", 0, -1 })
      end
      for _, file in ipairs(candidate.files) do
        table.insert(lines, "   " .. file)
        table.insert(highlights, { #lines - 1, "GitBranchCompareConflictFile", 0, -1 })
      end
    end
    local buf = buffer()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    for _, highlight in ipairs(highlights) do
      vim.api.nvim_buf_add_highlight(
        buf,
        ns,
        highlight[2],
        highlight[1],
        highlight[3],
        highlight[4]
      )
    end
    vim.bo[buf].modifiable = false
    local width = math.max(1, math.min(vim.o.columns - 4, 100))
    local height = math.max(1, math.min(vim.o.lines - vim.o.cmdheight - 4, #lines))
    local win = vim.api.nvim_open_win(buf, true, {
      relative = "editor",
      row = math.max(0, math.floor((vim.o.lines - vim.o.cmdheight - height - 2) / 2)),
      col = math.floor((vim.o.columns - width) / 2),
      width = width,
      height = height,
      style = "minimal",
      border = "rounded",
      title = " Possible related commits ",
      footer = aborted and " (q / Esc) Close "
        or " (a / Esc) Abort cherry-pick  (q) Keep conflict ",
      footer_pos = "center",
    })
    vim.wo[win].wrap = true
    local function close()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end
    vim.keymap.set("n", "q", close, { buffer = buf, desc = "Close conflict candidates" })
    if aborted then
      vim.keymap.set("n", "<Esc>", close, { buffer = buf, desc = "Close conflict candidates" })
    else
      local function confirm_abort()
        vim.ui.select({ "Keep conflict", "Abort entire batch" }, {
          prompt = "Abort the entire batch? Picked commits and conflict edits may be discarded.",
        }, function(choice)
          if choice ~= "Abort entire batch" then
            return
          end
          git.run(data.root, { "rev-parse", "HEAD", "CHERRY_PICK_HEAD" }, function(output, err)
            if err or vim.trim(output) ~= result.head .. "\n" .. result.conflict then
              return vim.notify("Cherry-pick state changed; abort cancelled", vim.log.levels.ERROR)
            end
            git.run(data.root, { "cherry-pick", "--abort" }, function(_, abort_err)
              if abort_err then
                return vim.notify("Cherry-pick abort failed: " .. abort_err, vim.log.levels.ERROR)
              end
              refresh_picks()
              git.load(data.root, data.source_ref, function(updated, load_err)
                if load_err then
                  return vim.notify(
                    "Failed to refresh comparison: " .. load_err,
                    vim.log.levels.ERROR
                  )
                end
                if not vim.api.nvim_tabpage_is_valid(tab) then
                  return
                end
                data, state.data, state.selected = updated, updated, {}
                refresh_issue_dependencies()
                render()
                close()
                show_conflict_candidates(result, true)
              end)
            end)
          end)
        end)
      end
      for _, key in ipairs({ "a", "<Esc>" }) do
        vim.keymap.set("n", key, confirm_abort, { buffer = buf, desc = "Abort cherry-pick batch" })
      end
    end
  end

  local function pick()
    local commits = model.ordered_selection(data.source, state.selected)
    if #commits == 0 then
      return vim.notify("Select source commits with Space", vim.log.levels.WARN)
    end
    git.resolve_dependencies(data, commits, function()
      if not vim.api.nvim_tabpage_is_valid(tab) or vim.api.nvim_get_current_tabpage() ~= tab then
        return
      end
      local warnings =
        model.dependencies(data.source, data.target, commits, data.extra, data.resolved)
      local selected, issues = {}, {}
      for _, sha in ipairs(commits) do
        selected[sha] = true
      end
      for _, item in ipairs(data.source) do
        if selected[item.sha] then
          for _, issue in ipairs(item.issues or {}) do
            issues[issue] = true
          end
        end
      end
      local graphs = {}
      if not state.issue_dependencies then
        table.insert(warnings, {
          kind = state.dependency_error and "check_failed" or "checking",
          ref = state.dependency_error and (state.dependency_error .. "; refresh to retry")
            or "Dependency check in progress; retry shortly",
        })
      else
        for issue in pairs(issues) do
          local graph = state.issue_dependencies[issue]
          if graph then
            table.insert(graphs, graph)
            vim.list_extend(warnings, graph.warnings)
          else
            table.insert(warnings, { kind = "missing_issue", ref = issue })
          end
        end
      end
      local lines, highlights = {}, {}
      for index, sha in ipairs(commits) do
        for _, item in ipairs(data.source) do
          if item.sha == sha then
            if #lines > 0 then
              table.insert(lines, "")
            end
            local date = os.date("%Y-%m-%d", item.time)
            local number = ("%d. "):format(index)
            table.insert(lines, number .. ("%s  %s  %s"):format(sha:sub(1, 8), date, item.author))
            local row = #lines - 1
            table.insert(highlights, { row, "GitBranchCompareIndex", 0, #number })
            table.insert(highlights, { row, "DiagnosticWarn", #number, #number + 8 })
            table.insert(highlights, { row, "DiagnosticHint", #number + 10, #number + 20 })
            table.insert(highlights, { row, "DiagnosticInfo", #number + 22, -1 })
            table.insert(lines, string.rep(" ", #number + 2) .. item.subject)
            table.insert(highlights, { #lines - 1, "GitBranchCompareMessage", 0, -1 })
            break
          end
        end
      end
      if #warnings > 0 then
        vim.list_extend(lines, { "", "Dependency issues" })
        table.insert(highlights, { #lines - 1, "Title", 0, -1 })
      end
      local displayed_issues, displayed_commits = {}, {}
      local suppressed_issues, suppressed_commits = {}, {}
      local issue_index = model.issue_index(data.source)
      for _, graph in ipairs(graphs) do
        local skip_depth
        for _, node in ipairs(graph.lines) do
          if skip_depth and node.depth <= skip_depth then
            skip_depth = nil
          end
          if skip_depth or node.status == "ready" then
            suppressed_issues[node.id] = true
            local entry = issue_index[node.id]
            for _, item in ipairs(entry and entry.commits or {}) do
              suppressed_commits[item.sha] = true
            end
          end
          if not skip_depth then
            if node.status == "ready" then
              skip_depth = node.depth
            else
              local indent = string.rep("  ", node.depth + 1)
              local label = node.status == "pending" and "not completed" or node.status
              table.insert(lines, indent .. node.id .. " — " .. label)
              displayed_issues[node.id] = true
              local entry = issue_index[node.id]
              for _, item in ipairs(entry and entry.commits or {}) do
                if item.status ~= "included" and item.status ~= "equivalent" then
                  table.insert(lines, indent .. "  " .. item.sha:sub(1, 8) .. "  " .. item.subject)
                  displayed_commits[item.sha] = true
                end
              end
            end
          end
        end
      end
      local descriptions = {
        unmatched_issue = "Issue not completed",
        missing_issue = "Issue not found; status unknown",
        cycle = "Dependency cycle",
        unmatched = "Commit not included",
        unresolved_commit = "Commit dependency cannot be resolved",
        ambiguous_commit = "Commit dependency is ambiguous",
        checking = "Checking dependencies",
        check_failed = "Dependency check failed",
      }
      for _, warning in ipairs(warnings) do
        if
          not (warning.kind == "unmatched_issue" and displayed_issues[warning.ref])
          and not (warning.kind == "unmatched" and displayed_commits[warning.sha])
        then
          if warning.kind == "unmatched" then
            for _, item in ipairs(data.source) do
              if item.sha == warning.sha and item.issues and item.issues[1] then
                table.insert(lines, "  " .. item.issues[1] .. " — not completed")
                break
              end
            end
          end
          local ref = warning.chain or warning.ref or warning.sha or ""
          if warning.kind == "unmatched" then
            ref = ref:sub(1, 8)
          end
          table.insert(
            lines,
            ("  %s: %s %s"):format(
              descriptions[warning.kind] or warning.kind,
              ref,
              warning.subject or ""
            )
          )
          table.insert(highlights, { #lines - 1, "DiagnosticWarn", 0, -1 })
        end
      end
      local buf = buffer()
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      for _, highlight in ipairs(highlights) do
        vim.api.nvim_buf_add_highlight(
          buf,
          ns,
          highlight[2],
          highlight[1],
          highlight[3],
          highlight[4]
        )
      end
      vim.bo[buf].modifiable = false
      local width = math.max(1, math.min(vim.o.columns - 4, math.floor(vim.o.columns * 0.8), 100))
      local available_height = vim.o.lines - vim.o.cmdheight
      local warning_line = #warnings > 0 and 1 or 0
      local height = math.max(1, math.min(available_height - 2 - warning_line, #lines))
      local win = vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        row = math.max(0, math.floor((available_height - height - 2) / 2)),
        col = math.floor((vim.o.columns - width) / 2),
        width = width,
        height = height,
        style = "minimal",
        border = "rounded",
        title = {
          { " Cherry-pick ", "Title" },
          { ("%d %s"):format(#commits, #commits == 1 and "commit" or "commits"), "DiagnosticInfo" },
          { " → ", "Title" },
          { data.branch .. " ", "DiagnosticWarn" },
        },
        title_pos = "left",
        footer = {
          { " (y) Cherry-pick ", "DiagnosticOk" },
          { " (q / Esc) Cancel ", "DiagnosticError" },
        },
        footer_pos = "center",
      })
      vim.wo[win].wrap = true
      vim.wo[win].winhighlight = "FloatBorder:GitBranchCompareMerged"
      if #warnings > 0 then
        vim.wo[win].winbar = ("%%#DiagnosticWarn# ⚠ %d dependencies need attention"):format(
          #warnings
        )
      end
      local function close()
        if vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_win_close(win, true)
        end
      end
      vim.keymap.set("n", "q", close, { buffer = buf, desc = "Cancel cherry-pick" })
      vim.keymap.set("n", "<Esc>", close, { buffer = buf, desc = "Cancel cherry-pick" })
      do
        vim.keymap.set("n", "y", function()
          vim.cmd.redraw()
          local last = vim.api.nvim_buf_line_count(buf) - 1
          local last_text = vim.api.nvim_buf_get_lines(buf, last - 1, last, false)[1]
          local pos = vim.fn.screenpos(win, last, math.max(1, #last_text))
          if vim.fn.line("w$") < last or pos.row == 0 then
            return vim.notify("Review all items before cherry-picking", vim.log.levels.WARN)
          end
          close()
          config.emit(
            "before_cherry_pick",
            { root = data.root, branch = data.branch, commits = commits }
          )
          git.pick(data.root, data.branch, data.head_sha, commits, function(err)
            refresh_picks()
            if err then
              return git.conflict_candidates(data, function(result, conflict_err)
                if result then
                  config.emit(
                    "after_cherry_pick",
                    { status = "conflict", error = err, commits = commits }
                  )
                  show_conflict_candidates(result, false)
                else
                  config.emit(
                    "after_cherry_pick",
                    { status = "failed", error = err, commits = commits }
                  )
                  vim.notify("Cherry-pick stopped: " .. err, vim.log.levels.ERROR)
                  if conflict_err and not conflict_err:find("CHERRY_PICK_HEAD", 1, true) then
                    vim.notify("Conflict analysis failed: " .. conflict_err, vim.log.levels.WARN)
                  end
                end
              end)
            end
            config.emit("after_cherry_pick", { status = "success", commits = commits })
            git.load(data.root, data.source_ref, function(updated, load_err)
              if load_err then
                return vim.notify(
                  "Failed to refresh comparison: " .. load_err,
                  vim.log.levels.ERROR
                )
              end
              if not vim.api.nvim_tabpage_is_valid(tab) then
                return
              end
              data = updated
              state.data = updated
              config.emit("on_refresh", updated)
              state.selected = {}
              refresh_issue_dependencies()
              render()
            end)
          end)
        end, { buffer = buf, desc = "Confirm cherry-pick" })
      end
    end)
  end
  ---Show the issue sidebar at its configured width and focus it.
  local function focus_issues()
    if not vim.api.nvim_win_is_valid(issue_win) then
      vim.api.nvim_set_current_win(target_win)
      vim.cmd("leftabove vsplit")
      issue_win = vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_buf(issue_win, issue_buf)
      vim.wo[issue_win].number = false
      vim.wo[issue_win].relativenumber = false
      vim.wo[issue_win].wrap = false
      vim.wo[issue_win].cursorline = true
      vim.api.nvim_win_set_width(issue_win, math.floor(width))
      vim.wo[issue_win].winfixwidth = true
      open_issue_header()
      open_issue_summary()
      render_picks()
      update_issue_footer()
      balance_panels()
      titles()
    end
    vim.api.nvim_set_current_win(issue_win)
  end
  ---Toggle the issue sidebar without discarding its buffer or selection.
  local function toggle_issues()
    if vim.api.nvim_win_is_valid(issue_win) then
      if header_win and vim.api.nvim_win_is_valid(header_win) then
        vim.api.nvim_win_close(header_win, true)
      end
      if summary_win and vim.api.nvim_win_is_valid(summary_win) then
        vim.api.nvim_win_close(summary_win, true)
      end
      vim.api.nvim_win_close(issue_win, true)
      update_issue_scrollbar()
      balance_panels()
    else
      focus_issues()
    end
  end
  ---Toggle selection of the current source commit when it is unmatched.
  local function toggle_commit()
    local item = current_commit()
    if item and item.status == "unmatched" then
      state.selected[item.sha] = not state.selected[item.sha] or nil
      render_commits()
    end
  end
  ---Move between commit headers, skipping their indented message lines.
  local function move_commit(direction)
    local win = vim.api.nvim_get_current_win()
    local rows = win == source_win and state.rows.source or state.rows.target
    local count = math.floor((#rows + 1) / 3)
    if count == 0 then
      return
    end
    local line = vim.api.nvim_win_get_cursor(win)[1]
    local index = math.max(1, math.floor((line - 2) / 3) + 1)
    if line > 1 then
      index = index + direction * vim.v.count1
    end
    index = math.max(1, math.min(count, index))
    vim.api.nvim_win_set_cursor(win, { 2 + (index - 1) * 3, 0 })
  end
  ---Show unpushed cherry-picks and their associated issues.
  local function show_picks()
    local picks = state.unpushed
    local lines = {}
    local highlights = {}
    local width = math.max(1, math.min(vim.o.columns - 4, 100))
    if picks.status ~= "ready" then
      table.insert(
        lines,
        picks.status == "no_upstream" and "Upstream not configured"
          or picks.status == "loading" and "Checking cherry-picks…"
          or "Cherry-pick status unavailable; press r to retry"
      )
    else
      local issues = {}
      for _, item in ipairs(picks.commits) do
        for _, issue in ipairs(item.issues) do
          issues[issue] = true
        end
      end
      local commit_count, issue_count = #picks.commits, vim.tbl_count(issues)
      local summary = ("%d commit%s · %d issue%s"):format(
        commit_count,
        commit_count == 1 and "" or "s",
        issue_count,
        issue_count == 1 and "" or "s"
      )
      local padding = math.max(0, math.floor((width - vim.fn.strdisplaywidth(summary)) / 2))
      table.insert(lines, string.rep(" ", padding) .. summary)
      table.insert(highlights, { #lines - 1, "GitBranchCompareConflictSummary", padding, -1 })
      local separator = width >= 3 and (" " .. string.rep("─", width - 2) .. " ")
        or string.rep("─", width)
      table.insert(lines, separator)
      table.insert(highlights, { #lines - 1, "WinSeparator", 0, -1 })
      for index, item in ipairs(picks.commits) do
        if index > 1 then
          table.insert(lines, "")
        end
        local prefix = ("%d. "):format(index)
        local sha = item.sha:sub(1, 8)
        local date = os.date("%Y-%m-%d", item.time)
        local date_col = #prefix + #sha + 2
        local author_col = date_col + #date + 2
        local message_col = author_col + #item.author + 2
        table.insert(
          lines,
          prefix .. sha .. "  " .. date .. "  " .. item.author .. "  " .. item.subject
        )
        local row = #lines - 1
        table.insert(highlights, { row, "GitBranchCompareIndex", 0, #prefix })
        table.insert(highlights, { row, "DiagnosticWarn", #prefix, #prefix + #sha })
        table.insert(highlights, { row, "DiagnosticHint", date_col, date_col + #date })
        table.insert(highlights, { row, "DiagnosticInfo", author_col, author_col + #item.author })
        table.insert(highlights, { row, "GitBranchCompareMessage", message_col, -1 })
        table.insert(
          lines,
          "   " .. (#item.issues > 0 and table.concat(item.issues, ", ") or "No issue")
        )
        table.insert(
          highlights,
          { #lines - 1, #item.issues > 0 and "DiagnosticInfo" or "Comment", 3, -1 }
        )
      end
    end
    local buf = buffer()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    for _, highlight in ipairs(highlights) do
      vim.api.nvim_buf_add_highlight(
        buf,
        ns,
        highlight[2],
        highlight[1],
        highlight[3],
        highlight[4]
      )
    end
    vim.bo[buf].modifiable = false
    local height = math.max(1, math.min(vim.o.lines - vim.o.cmdheight - 4, #lines))
    local win = vim.api.nvim_open_win(buf, true, {
      relative = "editor",
      row = math.max(0, math.floor((vim.o.lines - vim.o.cmdheight - height - 2) / 2)),
      col = math.floor((vim.o.columns - width) / 2),
      width = width,
      height = height,
      style = "minimal",
      border = "rounded",
      title = " Unpushed cherry-picks ",
      footer = " (q / Esc) Close ",
      footer_pos = "center",
    })
    vim.wo[win].wrap = true
    for _, key in ipairs({ "q", "<Esc>" }) do
      vim.keymap.set("n", key, function()
        if vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_win_close(win, true)
        end
      end, { buffer = buf, desc = "Close unpushed cherry-picks" })
    end
  end
  ---Open shortcut help for the currently focused comparison panel.
  local function show_help()
    local help = buffer()
    local lines = {
      "j / k       Move through the current list",
      "Ctrl-w h/l  Switch panels",
      ",b          Toggle issue sidebar",
      ",e          Focus issue sidebar",
      "H           Show unpushed cherry-picks",
    }
    local current = vim.api.nvim_get_current_buf()
    table.insert(lines, 1, "            ── Keyboard shortcuts")
    if current == issue_buf then
      vim.list_extend(lines, {
        "Enter / o   Focus source commits for the issue",
        "gg / G      Jump to first / last issue",
        "Tab         Switch Pending / All",
        "/           Filter issues by name",
        "Esc         Clear current issue filter",
        "y           Copy issue or related commits",
        "D           Show Issue dependencies",
        "b           Choose a source branch",
        "R           Change merged-history range",
        "q           Close comparison",
      })
    else
      vim.list_extend(lines, {
        "d           Show commit message and diff",
        "D           Show dependencies and their status",
        "y           Copy the full commit ID",
      })
      if current == source_buf then
        vim.list_extend(lines, {
          "Space       Select or deselect a source commit",
          "p           Review and cherry-pick selected commits",
          "r           Refresh comparison",
        })
      end
    end
    table.insert(lines, "g?          Show this help")
    if current == issue_buf then
      vim.list_extend(lines, {
        "",
        "            ── Issue Status",
        "A           All commits included",
        "P           Some commits included",
        "U           No commits included",
        "↳ green     All Issue dependencies completed",
        "↳ yellow    Issue dependency not completed",
        "↳ red       Issue dependency status unknown or cyclic",
        "…           Checking dependencies",
        "",
        "            ── Sorting",
        "Issue ↑     Issue ID in string ascending order",
      })
    else
      vim.list_extend(lines, {
        "",
        "            ── Commit Status",
        "I           Original commit included",
        "E           Equivalent change included",
        "U           No matching commit found",
      })
    end
    vim.api.nvim_buf_set_lines(help, 0, -1, false, lines)
    vim.bo[help].modifiable = false
    local help_width = math.max(1, math.min(vim.o.columns - 4, 62))
    local help_height = math.max(1, math.min(vim.o.lines - 4, #lines))
    local win = vim.api.nvim_open_win(help, true, {
      relative = "editor",
      row = math.floor((vim.o.lines - help_height) / 2) - 1,
      col = math.floor((vim.o.columns - help_width) / 2),
      width = help_width,
      height = help_height,
      style = "minimal",
      border = "rounded",
      title = { { " Keybindings ", "GitBranchCompareHelpHeading" } },
      title_pos = "left",
    })
    for index = 1, #lines do
      local stop = (lines[index]:find("  ", 1, true) or 1) - 1
      local marker = lines[index]:match("^([AIEPU])  ")
      local status_colors = {
        A = "GitBranchCompareMerged",
        I = "GitBranchCompareMerged",
        E = "GitBranchCompareMerged",
        P = "DiagnosticWarn",
        U = "DiagnosticError",
      }
      local dependency_colors = {
        green = "GitBranchCompareMerged",
        yellow = "DiagnosticWarn",
        red = "DiagnosticError",
      }
      local dependency_color = lines[index]:match("^↳ (%a+)  ")
      local group = dependency_colors[dependency_color] or status_colors[marker] or "DiagnosticInfo"
      local heading_start = lines[index]:find("── ", 1, true)
      if heading_start then
        local text_start = heading_start + #"── "
        vim.api.nvim_buf_add_highlight(
          help,
          ns,
          "GitBranchCompareMerged",
          index - 1,
          heading_start - 1,
          text_start - 1
        )
        vim.api.nvim_buf_add_highlight(
          help,
          ns,
          "GitBranchCompareHelpHeading",
          index - 1,
          text_start - 1,
          -1
        )
      else
        vim.api.nvim_buf_add_highlight(help, ns, group, index - 1, 0, stop)
      end
    end
    local function close()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end
    for _, key in ipairs({ "q", "<Esc>", "g?" }) do
      vim.keymap.set("n", key, close, { buffer = help, desc = "Close comparison help" })
    end
  end
  for _, buf in ipairs({ issue_buf, target_buf, source_buf }) do
    local function map(key, fn, desc)
      vim.keymap.set("n", key, fn, { buffer = buf, desc = desc, nowait = true })
    end
    map("<leader>b", toggle_issues, "Toggle issue sidebar")
    map("<leader>e", focus_issues, "Focus issue sidebar")
    map("H", show_picks, "Show unpushed cherry-picks")
    if buf == issue_buf then
      ---Jump to an issue and immediately update both commit panels.
      local function jump_issue(index)
        local group = state.groups[index]
        if group then
          vim.api.nvim_win_set_cursor(issue_win, { index, 0 })
          if state.issue ~= group.id then
            state.issue = group.id
            render_commits()
          end
        end
      end
      map("gg", function()
        jump_issue(1)
      end, "First issue")
      map("G", function()
        jump_issue(#state.groups)
      end, "Last issue")
      map("k", function()
        local index = vim.api.nvim_win_get_cursor(issue_win)[1]
        jump_issue(math.max(1, index - vim.v.count1))
      end, "Previous issue")
      map("<Tab>", function()
        state.view = state.view == "pending" and "all" or "pending"
        render()
      end, "Switch issue view")
      ---Filter issue IDs live and restore the previous view when cancelled.
      local function filter_issues()
        local view, previous, selected = state.view, state.filters[state.view], state.issue
        local changed = vim.api.nvim_create_autocmd("CmdlineChanged", {
          callback = function()
            state.filters[view] = vim.fn.getcmdline()
            render()
          end,
        })
        local cancelled = "\0cancelled"
        local ok, result = pcall(
          vim.fn.input,
          { prompt = "Filter issue(s): ", default = previous, cancelreturn = cancelled }
        )
        vim.api.nvim_del_autocmd(changed)
        if not ok or result == cancelled then
          state.filters[view], state.issue = previous, selected
        else
          state.filters[view] = result
        end
        render()
      end
      map("/", filter_issues, "Filter issues")
      ---Copy the selected Issue or all its Source commits to the clipboard.
      local function copy_issue_menu()
        local group = state.groups[vim.api.nvim_win_get_cursor(issue_win)[1]]
        if not group then
          return vim.notify("No issue selected", vim.log.levels.WARN)
        end
        local menu = buffer()
        vim.api.nvim_buf_set_lines(
          menu,
          0,
          -1,
          false,
          { "  Issue", "c Related commits", "  Cancel" }
        )
        vim.api.nvim_buf_add_highlight(menu, ns, "GitBranchCompareKeys", 1, 0, 1)
        vim.bo[menu].modifiable = false
        local menu_width =
          math.max(1, math.min(100, math.floor(vim.o.columns * 0.8), vim.o.columns - 4))
        local win = vim.api.nvim_open_win(menu, true, {
          relative = "editor",
          row = math.max(0, math.floor((vim.o.lines - vim.o.cmdheight - 5) / 2)),
          col = math.max(0, math.floor((vim.o.columns - menu_width) / 2)),
          width = menu_width,
          height = 3,
          style = "minimal",
          border = "rounded",
          title = { { " Copy to clipboard ", "GitBranchCompareHelpHeading" } },
          title_pos = "left",
          footer = { { " 1 of 3 ", "GitBranchCompareMerged" } },
          footer_pos = "right",
        })
        vim.wo[win].cursorline = true
        vim.wo[win].winhighlight = "FloatBorder:GitBranchCompareMerged"
        vim.api.nvim_win_set_cursor(win, { 1, 0 })
        local function close()
          if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
          end
        end
        local function copy(commits)
          local value, message = group.id, "Copied issue"
          if commits then
            local shas = {}
            for index = #data.source, 1, -1 do
              local item = data.source[index]
              if vim.tbl_contains(item.issues or {}, group.id) then
                table.insert(shas, item.sha)
              end
            end
            if #shas == 0 then
              return vim.notify("No related commits", vim.log.levels.WARN)
            end
            value = table.concat(shas, "\n")
            message = ("Copied %d related commit%s"):format(#shas, #shas == 1 and "" or "s")
          end
          vim.fn.setreg('"', value)
          local available = pcall(vim.fn.setreg, "+", value)
          close()
          if available then
            vim.notify(message, vim.log.levels.INFO)
          else
            vim.notify("Copied to unnamed register; clipboard unavailable", vim.log.levels.WARN)
          end
        end
        vim.keymap.set("n", "<CR>", function()
          local row = vim.api.nvim_win_get_cursor(win)[1]
          if row == 3 then
            close()
          else
            copy(row == 2)
          end
        end, { buffer = menu, desc = "Copy selected item" })
        vim.keymap.set("n", "c", function()
          copy(true)
        end, { buffer = menu, desc = "Copy related commits" })
        for _, entry in ipairs({ { "j", 1 }, { "<Down>", 1 }, { "k", -1 }, { "<Up>", -1 } }) do
          vim.keymap.set("n", entry[1], function()
            local row = vim.api.nvim_win_get_cursor(win)[1]
            row = math.max(1, math.min(3, row + entry[2]))
            vim.api.nvim_win_set_cursor(win, { row, 0 })
            vim.api.nvim_win_set_config(win, {
              footer = { { (" %d of 3 "):format(row), "GitBranchCompareMerged" } },
            })
          end, { buffer = menu, desc = "Choose copy option" })
        end
        for _, key in ipairs({ "q", "<Esc>" }) do
          vim.keymap.set("n", key, close, { buffer = menu, desc = "Close copy menu" })
        end
      end
      map("y", copy_issue_menu, "Copy issue or related commits")
      map("<Esc>", function()
        if state.filters[state.view] ~= "" then
          state.filters[state.view] = ""
          render()
        end
      end, "Clear issue filter")
      ---Focus the source panel for the issue under the cursor.
      local function focus_source()
        local group = state.groups[vim.api.nvim_win_get_cursor(issue_win)[1]]
        if group then
          if state.issue ~= group.id then
            state.issue = group.id
            render_commits()
          end
          vim.api.nvim_set_current_win(source_win)
        end
      end
      map("<CR>", focus_source, "Focus source commits for issue")
      map("o", focus_source, "Focus source commits for issue")
      map("q", function()
        vim.cmd.tabclose()
      end, "Close branch comparison")
    else
      map("y", function()
        local item = current_commit()
        if item then
          vim.fn.setreg('"', item.sha)
          if not pcall(vim.fn.setreg, "+", item.sha) then
            vim.notify("Copied to unnamed register; clipboard unavailable", vim.log.levels.WARN)
          else
            vim.notify("Copied commit ID", vim.log.levels.INFO)
          end
        end
      end, "Copy commit ID")
      map("j", function()
        move_commit(1)
      end, "Next commit")
      map("k", function()
        move_commit(-1)
      end, "Previous commit")
      if buf == source_buf then
        map("<Space>", toggle_commit, "Toggle source commit selection")
      end
    end
    map("d", preview, "Preview commit")
    map("p", pick, "Cherry-pick selected commits")
    map("r", function()
      refresh_picks()
      git.load(data.root, data.source_ref, function(updated, err)
        if err then
          return vim.notify(err, vim.log.levels.ERROR)
        end
        if not vim.api.nvim_tabpage_is_valid(tab) or vim.api.nvim_get_current_tabpage() ~= tab then
          return
        end
        config.emit("on_refresh", updated)
        vim.cmd.tabclose()
        M.open(updated)
      end)
    end, "Refresh branch comparison")
    map("b", function()
      git.branches(data.root, function(branches, err)
        if err then
          return vim.notify(err, vim.log.levels.ERROR)
        end
        if #branches == 0 then
          return vim.notify("No other branches found", vim.log.levels.WARN)
        end
        require("git-branch-flow.select").branch(branches, function(branch)
          if not branch then
            return
          end
          git.load(data.root, branch, function(updated, load_err)
            if load_err then
              return vim.notify(load_err, vim.log.levels.ERROR)
            end
            if
              not vim.api.nvim_tabpage_is_valid(tab)
              or vim.api.nvim_get_current_tabpage() ~= tab
            then
              return
            end
            vim.cmd.tabclose()
            M.open(updated)
          end)
        end)
      end)
    end, "Choose source branch")
    map("D", function()
      if buf == issue_buf then
        local graph = state.issue_dependencies and state.issue_dependencies[state.issue]
        local lines = { state.issue or "No issue selected", "" }
        local colors = { [1] = "Title" }
        if not graph then
          table.insert(
            lines,
            state.dependency_error and (state.dependency_error .. "; refresh to retry")
              or "Dependency check in progress; retry shortly"
          )
          colors[#lines] = state.dependency_error and "DiagnosticError" or "DiagnosticInfo"
        elseif not graph.has_dependencies then
          table.insert(lines, "No Issue dependencies")
        else
          for _, dependency in ipairs(graph.lines) do
            local descriptions = {
              ready = "included",
              pending = "not completed",
              unknown = "not found; status unknown",
              cycle = "cycle detected",
            }
            table.insert(
              lines,
              string.rep("  ", dependency.depth + 1)
                .. "↳ "
                .. dependency.id
                .. "  "
                .. descriptions[dependency.status]
            )
            colors[#lines] = dependency.status == "ready" and "GitBranchCompareMerged"
              or dependency.status == "pending" and "DiagnosticWarn"
              or "DiagnosticError"
          end
          for _, warning in ipairs(graph.warnings) do
            if warning.chain then
              table.insert(lines, "Cycle: " .. warning.chain)
              colors[#lines] = "DiagnosticError"
            end
          end
        end
        table.insert(lines, "")
        table.insert(lines, "q / Esc  Close")
        local detail = buffer()
        put(detail, lines, colors)
        local width = math.max(1, math.min(vim.o.columns - 4, 80))
        local height = math.max(1, math.min(vim.o.lines - 4, #lines))
        local win = vim.api.nvim_open_win(detail, true, {
          relative = "editor",
          row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
          col = math.floor((vim.o.columns - width) / 2),
          width = width,
          height = height,
          style = "minimal",
          border = "rounded",
          title = " Issue dependencies ",
        })
        for _, key in ipairs({ "q", "<Esc>" }) do
          vim.keymap.set("n", key, function()
            if vim.api.nvim_win_is_valid(win) then
              vim.api.nvim_win_close(win, true)
            end
          end, { buffer = detail, desc = "Close Issue dependencies" })
        end
        return
      end
      local item = current_commit()
      if not item then
        return
      end
      git.resolve_dependencies(data, { item.sha }, function()
        if not vim.api.nvim_tabpage_is_valid(tab) or vim.api.nvim_get_current_tabpage() ~= tab then
          return
        end
        local warnings, related =
          model.dependencies(data.source, data.target, { item.sha }, data.extra, data.resolved)
        local issue_refs = table.concat(item.depends_on or {}, ", ")
        local commit_refs = table.concat(item.depends_on_commits or {}, ", ")
        local lines = {
          "Declared dependencies",
          "  Issues:  " .. (issue_refs ~= "" and issue_refs or "None"),
          "  Commits: " .. (commit_refs ~= "" and commit_refs or "None"),
          "",
          "Dependency commits",
        }
        local colors = { [1] = "Title", [5] = "Title" }
        local shown = {}
        for _, dep in ipairs(related) do
          shown[dep.sha] = true
          table.insert(
            lines,
            ("  %-10s  %s  %s"):format(dep.status or "unknown", dep.sha:sub(1, 8), dep.author or "")
          )
          local color = (dep.status == "included" or dep.status == "equivalent")
              and "GitBranchCompareMerged"
            or "DiagnosticError"
          colors[#lines] = color
          table.insert(lines, "              " .. (dep.subject or ""))
          colors[#lines] = color
        end
        if #related == 0 then
          table.insert(lines, "  None")
        end
        local extra_warnings = {}
        for _, warning in ipairs(warnings) do
          if warning.kind ~= "unmatched" or not shown[warning.sha] then
            table.insert(extra_warnings, warning)
          end
        end
        if #extra_warnings > 0 then
          vim.list_extend(lines, { "", "Attention" })
          colors[#lines] = "DiagnosticWarn"
        end
        for _, warning in ipairs(extra_warnings) do
          table.insert(
            lines,
            ("  %s: %s %s"):format(
              warning.kind,
              warning.sha or warning.ref or "",
              warning.subject or ""
            )
          )
          colors[#lines] = "DiagnosticError"
        end
        vim.list_extend(lines, { "", "q / Esc  Close" })
        local detail = buffer()
        vim.api.nvim_buf_set_lines(detail, 0, -1, false, lines)
        for row, color in pairs(colors) do
          vim.api.nvim_buf_add_highlight(detail, ns, color, row - 1, 0, -1)
        end
        vim.bo[detail].modifiable = false
        local width = math.max(1, math.min(vim.o.columns - 4, 100))
        local height = math.max(1, math.min(vim.o.lines - 4, #lines))
        local win = vim.api.nvim_open_win(detail, true, {
          relative = "editor",
          row = math.floor((vim.o.lines - height) / 2) - 1,
          col = math.floor((vim.o.columns - width) / 2),
          width = width,
          height = height,
          style = "minimal",
          border = "rounded",
          title = " Dependencies ",
        })
        for _, key in ipairs({ "q", "<Esc>" }) do
          vim.keymap.set("n", key, function()
            vim.api.nvim_win_close(win, true)
          end, { buffer = detail, desc = "Close dependencies" })
        end
      end)
    end, "Show commit dependencies")
    map("R", function()
      vim.ui.select(
        { "30 days", "90 days", "365 days", "All history" },
        { prompt = "Merged history range" },
        function(choice)
          if choice then
            state.days = ({ ["30 days"] = 30, ["90 days"] = 90, ["365 days"] = 365 })[choice]
            render()
          end
        end
      )
    end, "Set history range")
    map("g?", show_help, "Comparison help")
  end
  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = issue_buf,
    callback = function()
      local group = state.groups[vim.api.nvim_win_get_cursor(issue_win)[1]]
      if group and group.id ~= state.issue then
        state.issue = group.id
        render_commits()
      end
      update_issue_footer()
    end,
  })
  local scroll_autocmd = vim.api.nvim_create_autocmd("WinScrolled", {
    callback = function(event)
      if not vim.api.nvim_tabpage_is_valid(tab) then
        pcall(vim.api.nvim_del_autocmd, event.id)
      elseif vim.api.nvim_get_current_tabpage() == tab then
        update_issue_footer()
      end
    end,
  })
  local tab_autocmd = vim.api.nvim_create_autocmd("TabEnter", {
    callback = function()
      if vim.api.nvim_get_current_tabpage() == tab then
        update_issue_footer()
      end
    end,
  })
  local resize_autocmd = vim.api.nvim_create_autocmd("WinResized", {
    callback = function(event)
      if not vim.api.nvim_tabpage_is_valid(tab) then
        vim.api.nvim_del_autocmd(event.id)
      elseif vim.api.nvim_get_current_tabpage() == tab then
        if vim.api.nvim_win_is_valid(issue_win) then
          vim.api.nvim_win_set_width(issue_win, math.floor(width))
        end
        balance_panels()
        draw_separators()
        update_issue_footer()
      end
    end,
  })
  vim.api.nvim_create_autocmd("TabClosed", {
    callback = function(event)
      if not vim.api.nvim_tabpage_is_valid(tab) then
        pcall(vim.api.nvim_del_autocmd, resize_autocmd)
        pcall(vim.api.nvim_del_autocmd, scroll_autocmd)
        pcall(vim.api.nvim_del_autocmd, tab_autocmd)
        if vim.api.nvim_buf_is_valid(issue_buf) then
          vim.api.nvim_buf_delete(issue_buf, { force = true })
        end
        if vim.api.nvim_buf_is_valid(header_buf) then
          vim.api.nvim_buf_delete(header_buf, { force = true })
        end
        if vim.api.nvim_buf_is_valid(summary_buf) then
          vim.api.nvim_buf_delete(summary_buf, { force = true })
        end
        if scrollbar_buf and vim.api.nvim_buf_is_valid(scrollbar_buf) then
          vim.api.nvim_buf_delete(scrollbar_buf, { force = true })
        end
        vim.api.nvim_del_autocmd(event.id)
      end
    end,
  })
  render()
  refresh_issue_dependencies()
  refresh_picks()
end

return M
