local M = {}

---Return selected commits in the reverse of Git's newest-first topological order.
---@param commits table[]
---@param selected table<string, boolean>
---@return string[]
function M.ordered_selection(commits, selected)
  local result = {}
  for i = #commits, 1, -1 do
    if selected[commits[i].sha] then
      table.insert(result, commits[i].sha)
    end
  end
  return result
end

---Classify source commits using ancestry and Git's patch-equivalence output.
---@param shas string[]
---@param reachable table<string, boolean>
---@param cherry_output string
---@return table<string, string>
function M.classify(shas, reachable, cherry_output)
  local equivalent = {}
  for sha in cherry_output:gmatch("%- (%x+)") do
    equivalent[sha] = true
  end
  local result = {}
  for _, sha in ipairs(shas) do
    result[sha] = reachable[sha] and "included" or equivalent[sha] and "equivalent" or "unmatched"
  end
  return result
end

---Group visible source commits by Issue without concealing truncated history.
---@param commits table[]
---@param window_seconds integer|nil
---@param now integer
---@return table[]
function M.groups(commits, window_seconds, now)
  local groups = {}
  for _, commit in ipairs(commits) do
    for _, issue in ipairs(commit.issues) do
      local group = groups[issue] or { id = issue, commits = {}, included = 0, limited = false }
      groups[issue] = group
      if commit.status ~= "unmatched" and window_seconds and commit.time < now - window_seconds then
        group.limited = true
      else
        table.insert(group.commits, commit)
        if commit.status ~= "unmatched" then
          group.included = group.included + 1
        end
      end
    end
  end
  local result = {}
  for _, group in pairs(groups) do
    if #group.commits > 0 then
      group.state = group.included == 0 and "unmatched"
        or group.included == #group.commits and "included"
        or "partial"
      table.insert(result, group)
    end
  end
  table.sort(result, function(a, b)
    return a.id < b.id
  end)
  return result
end

---Find unresolved recursive dependencies of the selected commits.
---@param source table[]
---@param target table[]
---@param selected string[]
---@param extra table[]|nil
---@param resolved table<string, string|boolean>|nil
---@return table[]
---@return table[]
function M.dependencies(source, target, selected, extra, resolved)
  local by_sha, by_issue = {}, {}
  for _, item in ipairs(extra or {}) do
    by_sha[item.sha] = item
  end
  for _, item in ipairs(target) do
    local copy = vim.deepcopy(item)
    copy.status = "included"
    by_sha[item.sha] = copy
  end
  for _, item in ipairs(source) do
    by_sha[item.sha] = item
    for _, issue in ipairs(item.issues) do
      by_issue[issue] = by_issue[issue] or {}
      table.insert(by_issue[issue], item)
    end
  end
  local done, active, warnings, warning_seen, related, related_seen = {}, {}, {}, {}, {}, {}
  local function warn(key, value)
    if not warning_seen[key] then
      warning_seen[key] = true
      table.insert(warnings, value)
    end
  end
  local visit
  visit = function(item)
    if active[item.sha] then
      warn("cycle:" .. item.sha, { kind = "cycle", sha = item.sha })
      return
    end
    if done[item.sha] then
      return
    end
    active[item.sha] = true
    local function dependency(ref)
      if not related_seen[ref.sha] then
        related_seen[ref.sha] = true
        table.insert(related, ref)
      end
      if ref.status ~= "included" and ref.status ~= "equivalent" then
        warn(ref.sha, { kind = "unmatched", sha = ref.sha, subject = ref.subject })
      end
      visit(ref)
    end
    for _, issue in ipairs(item.depends_on or {}) do
      local matches = by_issue[issue]
      if not matches then
        warn("issue:" .. issue, { kind = "missing_issue", ref = issue })
      else
        for _, ref in ipairs(matches) do
          dependency(ref)
        end
      end
    end
    for _, hash in ipairs(item.depends_on_commits or {}) do
      local matches = {}
      local verified = resolved and resolved[hash]
      if type(verified) == "string" and by_sha[verified] then
        table.insert(matches, by_sha[verified])
      elseif not resolved and hash:match("^%x%x%x%x%x*$") then
        for sha, ref in pairs(by_sha) do
          if sha:sub(1, #hash) == hash:lower() then
            table.insert(matches, ref)
          end
        end
      end
      if #matches ~= 1 then
        warn(
          "commit:" .. hash,
          { kind = #matches == 0 and "unresolved_commit" or "ambiguous_commit", ref = hash }
        )
      else
        dependency(matches[1])
      end
    end
    active[item.sha], done[item.sha] = nil, true
  end
  for _, sha in ipairs(selected) do
    if by_sha[sha] then
      visit(by_sha[sha])
    end
  end
  return warnings, related
end

---Index Issue commits and declarations from the complete source history.
---@param source table[]
---@return table
function M.issue_index(source)
  local issues = {}
  for _, item in ipairs(source) do
    for _, id in ipairs(item.issues or {}) do
      local entry = issues[id] or { commits = {}, dependencies = {} }
      issues[id] = entry
      table.insert(entry.commits, item)
      for _, ref in ipairs(item.depends_on or {}) do
        entry.dependencies[ref] = true
      end
    end
  end
  return issues
end

---Resolve an Issue's transitive dependencies against the complete source history.
---@param source table[]
---@param root string
---@param index table|nil
---@return table
function M.issue_dependencies(source, root, index)
  local issues = index or M.issue_index(source)
  local result = { status = "ready", has_dependencies = false, lines = {}, warnings = {} }
  local active, expanded, path, warned = {}, {}, {}, {}
  local function warning(kind, ref, chain)
    local key = kind .. ":" .. ref
    if not warned[key] then
      warned[key] = true
      table.insert(result.warnings, { kind = kind, ref = ref, chain = chain })
    end
    if kind == "unmatched_issue" then
      if result.status == "ready" then
        result.status = "pending"
      end
    else
      result.status = "unknown"
    end
  end
  local visit
  visit = function(id, depth)
    local entry = issues[id]
    if not entry then
      return
    end
    active[id] = true
    table.insert(path, id)
    local refs = vim.tbl_keys(entry.dependencies)
    table.sort(refs)
    for _, ref in ipairs(refs) do
      result.has_dependencies = true
      local dependency = issues[ref]
      local cycle = active[ref]
      local status = "ready"
      if cycle then
        status = "cycle"
        local chain = vim.deepcopy(path)
        table.insert(chain, ref)
        warning("cycle", ref, table.concat(chain, " → "))
      elseif not dependency then
        status = "unknown"
        warning("missing_issue", ref)
      else
        for _, commit in ipairs(dependency.commits) do
          if commit.status ~= "included" and commit.status ~= "equivalent" then
            status = "pending"
            warning("unmatched_issue", ref)
            break
          end
        end
      end
      table.insert(result.lines, { id = ref, depth = depth, status = status })
      if dependency and not cycle and not expanded[ref] then
        visit(ref, depth + 1)
      end
    end
    path[#path] = nil
    active[id] = nil
    expanded[id] = true
  end
  visit(root, 0)
  return result
end

return M
