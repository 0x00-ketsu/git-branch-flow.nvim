local M = {}
local defaults = {
  issue = { pattern = "[%a][%w]*%-%d+", width = nil, extract = nil },
  history_days = 90,
  hooks = {},
}
M.options = vim.deepcopy(defaults)

---Replace plugin settings with defaults merged with user options.
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
end

---Notify an optional observer without interrupting the active operation.
function M.emit(name, event)
  local hook = M.options.hooks[name]
  if not hook then
    return
  end
  local ok, err = pcall(hook, vim.deepcopy(event))
  if not ok then
    vim.schedule(function()
      vim.notify(("git-branch-flow %s hook failed: %s"):format(name, err), vim.log.levels.WARN)
    end)
  end
end

return M
