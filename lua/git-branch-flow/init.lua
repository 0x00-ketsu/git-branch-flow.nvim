local git = require("git-branch-flow.git")
local M = {}

---Configure comparison behavior and lifecycle hooks.
function M.setup(opts)
  require("git-branch-flow.config").setup(opts)
end

---Choose a local or remote-tracking source branch and open its comparison.
function M.open()
  local cwd = vim.fn.getcwd()
  git.branches(cwd, function(branches, err)
    if err then
      return vim.notify(err, vim.log.levels.ERROR, { title = "Branch comparison" })
    end
    if #branches == 0 then
      return vim.notify("No branches found", vim.log.levels.WARN, { title = "Branch comparison" })
    end
    require("git-branch-flow.select").branch(branches, function(branch)
      if not branch then
        return
      end
      git.load(cwd, branch, function(data, load_err)
        if load_err then
          return vim.notify(load_err, vim.log.levels.ERROR, { title = "Branch comparison" })
        end
        require("git-branch-flow.ui").open(data)
      end)
    end)
  end)
end

return M
