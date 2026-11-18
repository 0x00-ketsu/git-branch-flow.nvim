local M = {}

-- Read comma-separated issue identifiers without restricting their format.
local function identifiers(value)
  local result, seen = {}, {}
  local pattern = require("git-branch-flow.config").options.issue.pattern
  local function add(id)
    if id ~= "" and not seen[id] then
      seen[id] = true
      table.insert(result, id)
    end
  end
  for _, part in ipairs(vim.split(value, ",", { plain = true })) do
    local id = vim.trim(part)
    local matches = {}
    if id:find("%s") then
      for match in id:gmatch(pattern) do
        table.insert(matches, match:upper())
      end
    end
    if #matches > 0 then
      for _, match in ipairs(matches) do
        add(match)
      end
    else
      add(id:match("^" .. pattern .. "$") and id:upper() or id)
    end
  end
  return result
end

-- Parse commit metadata while retaining unresolved commit dependency references.
function M.parse_log(output)
  local result = {}
  for record in output:gmatch("([^\30]+)") do
    local fields = vim.split(record, "\0", { plain = true })
    if #fields >= 5 then
      local sha, timestamp, author, subject, body = unpack(fields)
      sha = vim.trim(sha)
      local item =
        { sha = sha, time = tonumber(timestamp) or 0, author = author, subject = subject }
      item.issues, item.depends_on, item.depends_on_commits = {}, {}, {}
      for line in (body .. "\n"):gmatch("([^\n]*)\n") do
        local tag, value = line:match("^%s*([%w-]+):%s*(.-)%s*$")
        if tag then
          tag = tag:lower()
          local target = tag == "issue" and item.issues or tag == "depends-on" and item.depends_on
          if target then
            for _, id in ipairs(identifiers(value)) do
              if not vim.tbl_contains(target, id) then
                table.insert(target, id)
              end
            end
          elseif tag == "depends-on-commit" then
            for _, ref in ipairs(vim.split(value, ",", { plain = true, trimempty = true })) do
              ref = vim.trim(ref)
              if ref ~= "" and not vim.tbl_contains(item.depends_on_commits, ref) then
                table.insert(item.depends_on_commits, ref)
              end
            end
          end
        end
      end
      local extract = require("git-branch-flow.config").options.issue.extract
      if extract then
        item.issues =
          extract({ sha = sha, time = item.time, author = author, subject = subject, body = body })
      end
      table.insert(result, item)
    end
  end
  return result
end

return M
