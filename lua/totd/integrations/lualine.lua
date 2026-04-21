-- lua/totd/integrations/lualine.lua
local M = {}

--- Returns a configured Lualine component for TotD
--- @param opts table|nil Configuration options (icon, max_length, hide_in_narrow)
function M.component(opts)
	opts = opts or {}
	local icon = opts.icon or "💡"
	local max_length = opts.max_length or 40
	local hide_in_narrow = opts.hide_in_narrow == nil and true or opts.hide_in_narrow

	return {
		-- The main function that returns the text
		function()
			local ok, totd = pcall(require, "totd")
			if not ok then
				return ""
			end

			local tip = totd.get_current()
			if not tip then
				return ""
			end

			local title = tip.title
			local char_count = vim.fn.strchars(title)
			if char_count > max_length then
				title = vim.fn.strcharpart(title, 0, max_length - 3) .. "..."
			end
			return icon .. " " .. title
		end,

		-- Optional: Hide the tip if the Neovim window gets too narrow
		cond = function()
			if not hide_in_narrow then
				return true
			end
			return vim.o.columns > 100
		end,

		-- Bonus: Allow the user to click the statusline to open the tip!
		on_click = function()
			local ok, totd = pcall(require, "totd")
			if ok then
				local current = totd.get_current()
				if current then
					totd.open(current.path)
				end
			end
		end,
	}
end

return M
