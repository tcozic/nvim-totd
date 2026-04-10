local M = {}

M.defaults = {
  db_path = vim.fn.stdpath("data") .. "/totd",
  enabled_sources = { "local", "tutor", "help" },
  custom_sources = {},
  ui = {
    default_display = "float", 
    border = "rounded",
    width = 0.7,   
    height = 0.75, 
    sandbox_split_direction = "vertical",
  },
  template = {
    default_mode = "normal",
    default_complexity = "beginner",
    default_tags = { "general" },
    default_source = "User",
  },
  show_on_startup = false,
}
M.options = {}
M.options = vim.deepcopy(M.defaults)
function M.setup(opts)
  opts = opts or {}
  M.options = vim.tbl_deep_extend("force", M.defaults, opts)
end
return M
