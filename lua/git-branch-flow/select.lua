local M = {}

---Choose a source branch using a compact picker sized to the available results.
---@param branches string[]
---@param callback fun(branch: string|nil)
function M.branch(branches, callback)
  vim.ui.select(branches, {
    prompt = "Compare source branch",
    snacks = {
      layout = {
        layout = { width = 0.4, min_width = 40, max_width = 70 },
        config = function(layout)
          for _, box in ipairs(layout.layout) do
            if box.win == "list" and not box.height then
              box.height = math.max(1, math.min(#branches, math.floor(vim.o.lines * 0.8) - 10))
            end
          end
        end,
      },
    },
  }, callback)
end

return M
