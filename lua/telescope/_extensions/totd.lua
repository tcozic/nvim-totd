local has_telescope, telescope = pcall(require, "telescope")
-- FIX: Return silently if Telescope isn't installed to prevent startup crashes
if not has_telescope then
  return
end

local finders = require("telescope.finders")
local pickers = require("telescope.pickers")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local previewers = require("telescope.previewers")
local totd = require("totd")

local function totd_picker(opts)
  opts = opts or {}
  local items = totd.list()

  pickers.new(opts, {
    prompt_title = "Tip of the Day",
    finder = finders.new_table({
      results = items,
      entry_maker = function(entry)
        local tags = type(entry.tags) == "table" and table.concat(entry.tags, " ") or ""
        
        return {
          value = entry,
          display = string.format("%-30s | %-10s | %s", entry.title, entry.complexity, tags),
          ordinal = entry.title .. " " .. tags .. " " .. entry.mode,
          -- FIX: Only assign 'path' if it's a real file so Telescope doesn't try to open virtuals
          path = not entry.path:match("^virtual:") and entry.path or nil,
          -- Store the real identifier for our custom previewer/opener
          tip_path = entry.path, 
        }
      end,
    }),
    sorter = conf.generic_sorter(opts),
    -- FIX: Custom previewer that flawlessly renders both physical and virtual tips
    previewer = previewers.new_buffer_previewer({
      title = "Tip Preview",
      define_preview = function(self, entry)
        local lines = totd.get_formatted_body(entry.tip_path)
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
        require("telescope.previewers.utils").highlighter(self.state.bufnr, "markdown")
      end,
    }),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        if selection then
          totd.open(selection.tip_path)
        end
      end)
      return true
    end,
  }):find()
end

return telescope.register_extension({
  exports = {
    totd = totd_picker,
  },
})
