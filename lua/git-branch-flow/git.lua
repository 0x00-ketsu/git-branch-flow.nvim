local model = require("git-branch-flow.model")
local parse_log = require("git-branch-flow.parser").parse_log
local M = {}

---Match otherwise unmatched commits with the same author, subject and zero-context patch.
local function match_context_independent(cwd, source, target, callback)
  local candidates, selected = {}, {}
  for _, item in ipairs(target) do
    if item.status == "unmatched" then
      local key = item.author .. "\0" .. item.subject
      candidates[key] = candidates[key] or {}
      table.insert(candidates[key], item)
    end
  end
  for _, item in ipairs(source) do
    local matches = candidates[item.author .. "\0" .. item.subject]
    if item.status == "unmatched" and matches then
      selected[item.sha] = item
      for _, target_item in ipairs(matches) do
        selected[target_item.sha] = target_item
      end
    end
  end
  local shas = vim.tbl_keys(selected)
  if #shas == 0 then
    return callback()
  end
  local args = { "show", "--format=commit %H", "--no-renames", "--unified=0" }
  vim.list_extend(args, shas)
  M.run(cwd, args, function(patches, err)
    if err then
      return callback(err)
    end
    vim.system({ "git", "patch-id", "--stable" }, { text = true, stdin = patches }, function(result)
      vim.schedule(function()
        if result.code ~= 0 then
          return callback(vim.trim(result.stderr or "patch-id failed"))
        end
        local hashes = {}
        for hash, sha in (result.stdout or ""):gmatch("(%x+) (%x+)") do
          hashes[sha] = hash
        end
        for _, item in ipairs(source) do
          local matches = candidates[item.author .. "\0" .. item.subject]
          if item.status == "unmatched" and hashes[item.sha] and matches then
            for _, other in ipairs(matches) do
              if hashes[item.sha] == hashes[other.sha] then
                item.status, other.status = "equivalent", "equivalent"
              end
            end
          end
        end
        callback()
      end)
    end)
  end)
end

---Run Git asynchronously and report errors at the caller's boundary.
---@param cwd string
---@param args string[]
---@param callback fun(output: string|nil, error: string|nil)
function M.run(cwd, args, callback)
  local command = { "git", "-C", cwd, "--no-pager" }
  vim.list_extend(command, args)
  vim.system(command, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        local error = result.stderr or ""
        callback(nil, vim.trim(error ~= "" and error or "Git command failed"))
      else
        callback(result.stdout or "", nil)
      end
    end)
  end)
end

---List local cherry-pick commits not reachable from the current branch's upstream.
---@param cwd string
---@param callback fun(result: table|nil, error: string|nil)
function M.unpushed_picks(cwd, callback)
  M.run(cwd, { "symbolic-ref", "--quiet", "HEAD" }, function(branch, err)
    if err then
      return callback(nil, err)
    end
    M.run(
      cwd,
      { "for-each-ref", "--format=%(upstream)", vim.trim(branch) },
      function(upstream, failure)
        if failure then
          return callback(nil, failure)
        end
        upstream = vim.trim(upstream)
        if upstream == "" then
          return callback({ status = "no_upstream", commits = {} })
        end
        local format = "--format=%x1e%H%x00%ct%x00%an%x00%s%x00%b"
        M.run(cwd, { "log", format, upstream .. "..HEAD" }, function(output, log_err)
          if log_err then
            return callback(nil, log_err)
          end
          local commits = {}
          for record in output:gmatch("([^\30]+)") do
            if ("\n" .. record .. "\n"):match("\n%(cherry picked from commit %x+%)\n") then
              local item = parse_log(record)[1]
              if item then
                table.insert(commits, item)
              end
            end
          end
          callback({ status = "ready", commits = commits })
        end)
      end
    )
  end)
end

---List source branches, excluding the current branch and its origin counterpart.
---@param cwd string
---@param callback fun(branches: string[]|nil, error: string|nil)
function M.branches(cwd, callback)
  M.run(cwd, {
    "for-each-ref",
    "--format=%(refname:short)%00%(symref)%00%(HEAD)",
    "refs/heads",
    "refs/remotes",
  }, function(out, err)
    if err then
      return callback(nil, err)
    end
    local candidates, current = {}, nil
    for line in out:gmatch("[^\n]+") do
      local branch, symbolic, head = line:match("^([^%z]+)%z([^%z]*)%z(.*)$")
      if branch and symbolic == "" then
        table.insert(candidates, branch)
        if head == "*" then
          current = branch
        end
      end
    end
    local branches = {}
    for _, branch in ipairs(candidates) do
      if not current or (branch ~= current and branch ~= "origin/" .. current) then
        table.insert(branches, branch)
      end
    end
    callback(branches, nil)
  end)
end

---Resolve declared commit references against the repository, including other branches.
---@param data table
---@param selected string[]
---@param callback fun()
function M.resolve_dependencies(data, selected, callback)
  local known, by_issue, queue, queued, visited = {}, {}, {}, {}, {}
  data.extra, data.resolved = data.extra or {}, data.resolved or {}
  for _, item in ipairs(data.target) do
    known[item.sha] = item
  end
  for _, item in ipairs(data.source) do
    known[item.sha] = item
    for _, issue in ipairs(item.issues) do
      by_issue[issue] = by_issue[issue] or {}
      table.insert(by_issue[issue], item)
    end
  end
  for _, item in ipairs(data.extra) do
    known[item.sha] = item
  end
  local add
  add = function(item)
    if not item or visited[item.sha] then
      return
    end
    visited[item.sha] = true
    for _, issue in ipairs(item.depends_on or {}) do
      for _, dependency in ipairs(by_issue[issue] or {}) do
        add(dependency)
      end
    end
    for _, ref in ipairs(item.depends_on_commits or {}) do
      if not queued[ref] then
        queued[ref] = true
        table.insert(queue, ref)
      end
    end
  end
  for _, sha in ipairs(selected) do
    add(known[sha])
  end
  local index = 1
  local function next_ref()
    local ref = queue[index]
    index = index + 1
    if not ref then
      return callback()
    end
    if data.resolved[ref] ~= nil then
      add(known[data.resolved[ref]])
      return next_ref()
    end
    if #ref < 4 or #ref > 64 or not ref:match("^%x+$") then
      data.resolved[ref] = false
      return next_ref()
    end
    M.run(
      data.root,
      { "rev-parse", "--verify", "--end-of-options", ref .. "^{commit}" },
      function(out, err)
        if err then
          data.resolved[ref] = false
          return next_ref()
        end
        local sha = vim.trim(out)
        data.resolved[ref] = sha
        if known[sha] then
          add(known[sha])
          return next_ref()
        end
        local format = "--format=%x1e%H%x00%ct%x00%an%x00%s%x00%b"
        M.run(data.root, { "show", "-s", format, sha }, function(commit, show_err)
          if not show_err then
            local item = parse_log(commit)[1]
            if item then
              item.status = data.reachable[sha] and "included" or "unmatched"
              table.insert(data.extra, item)
              known[sha] = item
              add(item)
            end
          end
          next_ref()
        end)
      end
    )
  end
  next_ref()
end

---Load branch histories and classify source commits against the current branch.
---@param cwd string
---@param source string
---@param callback fun(result: table|nil, error: string|nil)
function M.load(cwd, source, callback)
  local data = {}
  local format = "--format=%x1e%H%x00%ct%x00%an%x00%s%x00%b"
  local steps = {
    { { "rev-parse", "--show-toplevel" }, "root" },
    { { "symbolic-ref", "--quiet", "--short", "HEAD" }, "branch" },
    { { "rev-parse", "--verify", "--end-of-options", source .. "^{commit}" }, "source_sha" },
    { { "rev-parse", "--verify", "HEAD" }, "head_sha" },
  }
  local function first(index)
    local step = steps[index]
    if not step then
      return M.run(cwd, { "merge-base", data.head_sha, data.source_sha }, function(base, err)
        if err then
          return callback(nil, "Branches have no common ancestor: " .. err)
        end
        data.base = vim.trim(base)
        local log_args = { "log", "--topo-order", "--no-merges", format }
        local function history(ref, done)
          local args = vim.list_extend(vim.deepcopy(log_args), { ref })
          M.run(cwd, args, done)
        end
        history(data.source_sha, function(source_log, source_err)
          if source_err then
            return callback(nil, source_err)
          end
          history(data.head_sha, function(target_log, target_err)
            if target_err then
              return callback(nil, target_err)
            end
            M.run(cwd, { "rev-list", data.head_sha }, function(reachable, reachable_err)
              if reachable_err then
                return callback(nil, reachable_err)
              end
              M.run(cwd, { "cherry", data.head_sha, data.source_sha }, function(cherry, cherry_err)
                if cherry_err then
                  return callback(nil, cherry_err)
                end
                local present = {}
                for sha in reachable:gmatch("%x+") do
                  present[sha] = true
                end
                data.source, data.target = parse_log(source_log), parse_log(target_log)
                local shas = vim.tbl_map(function(item)
                  return item.sha
                end, data.source)
                local status = model.classify(shas, present, cherry)
                for _, item in ipairs(data.source) do
                  item.status = status[item.sha]
                end
                M.run(
                  cwd,
                  { "cherry", data.source_sha, data.head_sha },
                  function(reverse, reverse_err)
                    if reverse_err then
                      return callback(nil, reverse_err)
                    end
                    local source_present = {}
                    for _, item in ipairs(data.source) do
                      source_present[item.sha] = true
                    end
                    local target_shas = vim.tbl_map(function(item)
                      return item.sha
                    end, data.target)
                    local target_status = model.classify(target_shas, source_present, reverse)
                    for _, item in ipairs(data.target) do
                      item.status = target_status[item.sha]
                    end
                    match_context_independent(cwd, data.source, data.target, function(match_err)
                      if match_err then
                        return callback(nil, match_err)
                      end
                      data.source_ref = source
                      data.reachable, data.extra, data.resolved = present, {}, {}
                      callback(data, nil)
                    end)
                  end
                )
              end)
            end)
          end)
        end)
      end)
    end
    M.run(cwd, step[1], function(output, err)
      if err then
        if step[2] == "branch" then
          return callback(nil, "Current repository is in detached HEAD or has no branch")
        end
        return callback(nil, err)
      end
      data[step[2]] = vim.trim(output)
      first(index + 1)
    end)
  end
  first(1)
end

---Find unmerged source ancestors that changed files involved in an active cherry-pick conflict.
---@param data table
---@param callback fun(result: table|nil, error: string|nil)
function M.conflict_candidates(data, callback)
  M.run(data.root, { "rev-parse", "--verify", "CHERRY_PICK_HEAD" }, function(conflict, conflict_err)
    if conflict_err then
      return callback(nil, nil)
    end
    conflict = vim.trim(conflict)
    M.run(data.root, { "diff", "--name-only", "--diff-filter=U", "-z" }, function(output, err)
      if err then
        return callback(nil, err)
      end
      local files = vim.split(output, "\0", { plain = true, trimempty = true })
      if #files == 0 then
        return callback(nil, nil)
      end
      M.load(data.root, data.source_ref, function(updated, load_err)
        if load_err then
          return callback(nil, load_err)
        end
        local touched, index = {}, 1
        local function next_file()
          local file = files[index]
          index = index + 1
          if not file then
            local candidates = {}
            for i = #updated.source, 1, -1 do
              local item = updated.source[i]
              if item.status == "unmatched" and touched[item.sha] then
                table.insert(candidates, { commit = item, files = touched[item.sha] })
              end
            end
            return callback({
              files = files,
              candidates = candidates,
              conflict = conflict,
              head = updated.head_sha,
              branch = updated.branch,
            })
          end
          M.run(data.root, {
            "log",
            "--follow",
            "--format=%H",
            conflict .. "^",
            "--",
            file,
          }, function(history, history_err)
            if history_err then
              return callback(nil, history_err)
            end
            for sha in history:gmatch("%x+") do
              touched[sha] = touched[sha] or {}
              table.insert(touched[sha], file)
            end
            next_file()
          end)
        end
        next_file()
      end)
    end)
  end)
end

---Cherry-pick commits only while the branch, HEAD, and tracked files remain unchanged.
---@param cwd string
---@param expected_branch string
---@param expected_head string
---@param commits string[]
---@param callback fun(error: string|nil)
function M.pick(cwd, expected_branch, expected_head, commits, callback)
  if #commits == 0 then
    return callback("No commits selected")
  end
  local function unsaved()
    local root = vim.fs.normalize(vim.uv.fs_realpath(cwd) or cwd)
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].modified then
        local name = vim.api.nvim_buf_get_name(buf)
        local path = vim.fs.normalize(vim.uv.fs_realpath(name) or name)
        if path == root or vim.startswith(path, root .. "/") then
          return name
        end
      end
    end
  end
  local edited = unsaved()
  if edited then
    return callback("Repository has unsaved buffer: " .. edited)
  end
  M.run(cwd, { "symbolic-ref", "--quiet", "--short", "HEAD" }, function(branch, branch_err)
    if branch_err or vim.trim(branch) ~= expected_branch then
      return callback("Current branch changed; refresh before cherry-picking")
    end
    M.run(cwd, { "rev-parse", "HEAD" }, function(head, head_err)
      if head_err or vim.trim(head) ~= expected_head then
        return callback("HEAD changed; refresh before cherry-picking")
      end
      M.run(cwd, { "status", "--porcelain", "--untracked-files=no" }, function(status, status_err)
        if status_err then
          return callback(status_err)
        end
        if status ~= "" then
          return callback("Working tree has uncommitted changes")
        end
        local paths = {
          "CHERRY_PICK_HEAD",
          "MERGE_HEAD",
          "REVERT_HEAD",
          "rebase-merge",
          "rebase-apply",
          "sequencer",
        }
        local function check(index)
          if not paths[index] then
            local changed = unsaved()
            if changed then
              return callback("Repository has unsaved buffer: " .. changed)
            end
            local args = { "cherry-pick", "-x" }
            vim.list_extend(args, commits)
            return M.run(cwd, args, function(_, err)
              callback(err)
            end)
          end
          M.run(cwd, { "rev-parse", "--git-path", paths[index] }, function(path, err)
            if err then
              return callback(err)
            end
            path = vim.trim(path)
            if not vim.startswith(path, "/") then
              path = cwd .. "/" .. path
            end
            if vim.uv.fs_stat(path) then
              return callback("Git operation already in progress: " .. paths[index])
            end
            check(index + 1)
          end)
        end
        check(1)
      end)
    end)
  end)
end

return M
