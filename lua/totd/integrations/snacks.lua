local M = {}

--- Returns a fully configured Snacks picker for TotD
function M.picker()
	local ok, snacks = pcall(require, "snacks")
	if not ok then
		vim.notify("[totd] Snacks.nvim is not installed", vim.log.levels.ERROR)
		return
	end

	local totd = require("totd")
	local progress = require("totd.progress") -- Load the progress module
	local state = progress.load() -- Load the current Anki state

	snacks.picker({
		title = "Tip of the Day",
		layout = { preset = "default" },
		items = (function()
			local items = {}
			for _, tip in ipairs(totd.list()) do
				local is_virtual = tip.path:match("^virtual:")

				-- Define the filename so we can check the state
				local filename = vim.fn.fnamemodify(tip.path, ":t")
				local is_masked = state["suspend:" .. filename] == true

				table.insert(items, {
					text = tip.title .. " " .. tip.mode .. " " .. tip.complexity,
					file = not is_virtual and tip.path or nil,
					tip_data = tip,
					is_masked = is_masked, -- Save the flag to the item
				})
			end
			return items
		end)(),
		format = function(item, _)
			local t = item.tip_data
			-- If masked, use "Comment" (grey) for everything
			local main_hl = item.is_masked and "Comment" or "Normal"
			local detail_hl = item.is_masked and "Comment"
				or (
					t.complexity == "beginner" and "DiagnosticInfo"
					or t.complexity == "intermediate" and "DiagnosticWarn"
					or "DiagnosticError"
				)
			return {
				{ t.title, main_hl },
				{ " [" .. t.mode .. "] ", "Comment" },
				{ t.complexity, detail_hl },
			}
		end,
		actions = {
			mask_tip = function(picker, item)
				if not item then
					return
				end
				-- 1. Toggle the backend state silently
				require("totd").toggle_suspend(item.tip_data.path, true)

				-- 2. Flip the state of the item currently in memory
				item.is_masked = not item.is_masked

				-- 3. Force the picker's list to redraw instantly to apply the new color
				if picker.list and type(picker.list.update) == "function" then
					picker.list:update({ force = true })
				end
			end,
		},
		win = {
			-- Map directly to the input window, where your cursor actually lives!
			input = {
				keys = {
					-- Alt+m toggles the mask instantly in both Insert and Normal modes
					["<a-m>"] = { "mask_tip", mode = { "i", "n" }, desc = "Toggle Mask" },

					-- If you strictly want a Normal mode only key, use Shift+M
					["M"] = { "mask_tip", mode = { "n" }, desc = "Toggle Mask" },
				},
			},
		},
		preview = function(ctx)
			local tip = ctx.item.tip_data
			if tip.path:match("^virtual:") then
				local lines = totd.get_formatted_body(tip.path)
				ctx.preview:set_lines(lines)
				ctx.preview:highlight({ ft = "markdown" })
			else
				return snacks.picker.preview.file(ctx)
			end
		end,
		confirm = function(picker, item)
			picker:close()
			if item and item.tip_data then
				totd.open(item.tip_data.path)
			end
		end,
	})
end

--- Returns a dynamic Snacks dashboard section function
--- @param opts table|nil Allows users to override default width and keymap hint
function M.dashboard_section(opts)
	opts = opts or {}
	local width = opts.width or 50
	local action_key = opts.action_key or " <leader>te"

	return function()
		local ok, totd = pcall(require, "totd")
		if not ok then
			return { align = "center", padding = 2, text = { { "Plugin loading...", hl = "Comment" } } }
		end

		local tip = totd.get_current()
		local data = totd.get_teaser_data(tip)
		local ui_text = {}

		local function wrap(text, max_w)
			local lines, current_line = {}, ""
			for word in text:gmatch("%S+") do
				if #current_line + #word + 1 > max_w then
					table.insert(lines, current_line)
					current_line = word
				else
					current_line = current_line == "" and word or current_line .. " " .. word
				end
			end
			if current_line ~= "" then
				table.insert(lines, current_line)
			end
			return lines
		end

		-- 1. TITLE
		local title_str = "  💡 " .. data.title
		local title_pad = math.max(0, width - vim.fn.strdisplaywidth(title_str))
		table.insert(ui_text, { title_str .. string.rep(" ", title_pad) .. "\n\n", hl = "Title" })

		-- 2. SYNOPSIS
		local wrapped_synopsis = wrap(data.synopsis, width - 4)
		for _, line in ipairs(wrapped_synopsis) do
			local line_pad = math.max(0, (width - 4) - vim.fn.strdisplaywidth(line))
			table.insert(ui_text, { "  ┃ ", hl = "Comment" })
			table.insert(ui_text, { line .. string.rep(" ", line_pad) .. "\n", hl = "SnacksDashboardDesc" })
		end

		-- 3. ACTION
		local action_desc = "open "
		local action_prefix = "    "
		local used_width = vim.fn.strdisplaywidth(action_prefix .. action_desc .. action_key)
		local pad_str = string.rep(" ", math.max(0, width - used_width))

		table.insert(ui_text, { "\n" .. action_prefix, hl = "Normal" })
		table.insert(ui_text, { action_desc, hl = "SnacksDashboardDesc" })
		table.insert(ui_text, { pad_str, hl = "Comment" })
		table.insert(ui_text, { action_key, hl = "SnacksDashboardKey" })

		return {
			align = "center",
			padding = 2,
			text = ui_text,
		}
	end
end

return M
