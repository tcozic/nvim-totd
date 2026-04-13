--- lua/totd/ui.lua
--- Handles all display logic: floating windows, splits, and scratch buffers.
local M = {}

local config = require("totd.config")

--- Compute floating window dimensions and position.
--- @return number width, number height, number row, number col
local function float_dimensions()
	local ui_cfg = config.options.ui
	local W = math.floor(vim.o.columns * (ui_cfg.width or 0.7))
	local H = math.floor(vim.o.lines * (ui_cfg.height or 0.75))
	local row = math.floor((vim.o.lines - H) / 2)
	local col = math.floor((vim.o.columns - W) / 2)
	return W, H, row, col
end

--- Create a read-only scratch buffer pre-filled with lines.
--- @param lines table List of strings
--- @return number buf Buffer handle
local function make_scratch_buf(lines)
	local buf = vim.api.nvim_create_buf(false, true) -- unlisted, scratch
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].filetype = "markdown"
	return buf
end

--- Set keymaps that close/hide the totd window.
--- @param buf number
--- @param win number|nil (only needed for float)
local function set_close_keymaps(buf, win)
	local opts = { buffer = buf, nowait = true, silent = true }
	local function close()
		-- Close the window if it still exists
		if win and vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
		-- Wipe the buffer if it still exists
		if vim.api.nvim_buf_is_valid(buf) then
			vim.api.nvim_buf_delete(buf, { force = true })
		end
	end
	vim.keymap.set("n", "q", close, opts)
	vim.keymap.set("n", "<Esc>", close, opts)
	vim.keymap.set("n", "<CR>", close, opts)
end

--- Renders the tip in a floating window with an optional connected practice sandbox.
--- @param lines table Array of formatted string lines
--- @param sandbox string|nil Optional practice code block
--- @param lang string|nil Captured language for syntax highlighting
--- @param fm table|nil Parsed frontmatter data
--- @param path string|nil The identifier/path of the tip for editing and masking
function M.float(lines, sandbox, lang, fm, path)
	-- 1. Calculate window size
	local width = math.floor(vim.o.columns * 0.8)
	local height = math.floor(vim.o.lines * 0.8)
	local col = math.floor((vim.o.columns - width) / 2)
	local row = math.floor((vim.o.lines - height) / 2)

	-- ─────────────────────────────────────────────────────────────
	-- INJECT VISUAL KEYMAP HINTS (FOOTER)
	-- ─────────────────────────────────────────────────────────────
	table.insert(lines, "")
	table.insert(lines, string.rep("─", 72))

  local hints = { "[q] close", "[1] hard", "[2] good", "[e] edit" }
	
	if fm and fm.is_suspended then
		table.insert(hints, "[m] unmask")
	else
		table.insert(hints, "[m] mask")
	end
	-- Ensure sandbox actually has content (not just an empty string)
	if sandbox and sandbox ~= "" then
		table.insert(hints, "[<leader>sb] sandbox")
    table.insert(hints, "[<leader>y] yank") -- Updated hint
	end
	if fm and type(fm.related) == "table" and #fm.related > 0 then
		table.insert(hints, "[R] related")
	end

	table.insert(lines, "  " .. table.concat(hints, "   "))

	-- 2. Create the main Tip buffer
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false
	vim.bo[buf].filetype = "markdown"

	-- 3. Open the floating window
	local win_opts = {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		style = "minimal",
		border = "rounded",
		title = " 💡 Tip of the Day ",
		title_pos = "center",
	}
	local win = vim.api.nvim_open_win(buf, true, win_opts)

	-- 4. Standard Keymaps
	vim.keymap.set("n", "q", "<cmd>close<CR>", { buffer = buf, desc = "Close Tip" })

  -- ─────────────────────────────────────────────────────────────
	-- NEW: Edit Tip Keymap & Scoring Behaviors
	-- ─────────────────────────────────────────────────────────────
	if path then
		local function handle_behavior()
			-- Read the config dynamically so it always respects the user's choice
			local behavior = require("totd.config").options.ui.scoring_behavior or "close"
			
			if behavior == "keep_open" then
				return -- Do nothing, leave the window open
			elseif behavior == "reroll" then
				vim.cmd("close")
				-- 150ms delay ensures the async DB save finishes before weighting the next random tip
				vim.defer_fn(function() require("totd.api").pick_random() end, 150)
			elseif behavior == "open_next" then
				vim.cmd("close")
				vim.defer_fn(function() require("totd.api").random() end, 150)
			else -- "close" (fallback)
				vim.cmd("close")
			end
		end

		vim.keymap.set("n", "1", function()
			require("totd.api").score(path, 1)
			handle_behavior()
		end, { buffer = buf, desc = "Score: Hard" })

		vim.keymap.set("n", "2", function()
			require("totd.api").score(path, 2)
			handle_behavior()
		end, { buffer = buf, desc = "Score: Good" })

		vim.keymap.set("n", "m", function()
			-- Pass `true` as the second argument so the API doesn't force a redraw
			require("totd.api").toggle_suspend(path, true)
			handle_behavior()
		end, { buffer = buf, desc = "Toggle Mask/Suspend" })

		vim.keymap.set("n", "e", function()
			vim.cmd("close")
			require("totd.api").edit(path)
		end, { buffer = buf, desc = "Edit Tip" })
	end
	-- ─────────────────────────────────────────────────────────────
	-- The Practice Sandbox Setup
	-- ─────────────────────────────────────────────────────────────
	if sandbox and sandbox ~= "" then
		vim.keymap.set("n", "<leader>sb", function()
			vim.cmd("tabnew")
			local tab_page = vim.api.nvim_get_current_tabpage()

			local tip_buf = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_set_lines(tip_buf, 0, -1, false, lines)
			vim.bo[tip_buf].modifiable = false
			vim.bo[tip_buf].filetype = "markdown"
			vim.api.nvim_win_set_buf(0, tip_buf)

			vim.cmd("vsplit")
			local s_buf = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_set_lines(s_buf, 0, -1, false, vim.split(sandbox, "\n"))

			vim.bo[s_buf].filetype = lang or "text"
			vim.api.nvim_win_set_buf(0, s_buf)

			vim.api.nvim_create_autocmd("WinClosed", {
				buffer = s_buf,
				once = true,
				callback = function()
					if vim.api.nvim_tabpage_is_valid(tab_page) then
						vim.cmd("tabclose")
					end
				end,
			})
		end, { buffer = buf, desc = "Open Practice Sandbox" })
    vim.keymap.set("n", "<leader>y", function()
			vim.fn.setreg('"', sandbox)
			vim.notify("[totd] Sandbox yanked to unnamed register", vim.log.levels.INFO)
		end, { buffer = buf, desc = "Yank Sandbox" })
	end

	-- ─────────────────────────────────────────────────────────────
	-- The Related Navigation Setup
	-- ─────────────────────────────────────────────────────────────
	if fm and type(fm.related) == "table" and #fm.related > 0 then
		vim.keymap.set("n", "R", function()
			vim.ui.select(fm.related, {
				prompt = "Related Tips:",
				format_item = function(item)
					return "💡 " .. item
				end,
			}, function(choice)
				if choice then
					require("totd").open(choice)
				end
			end)
		end, { buffer = buf, desc = "Open Related Tip" })
	end
end

--- @param lines table Array of formatted string lines
--- @param sandbox string|nil (Unused in split mode)
--- @param lang string|nil (Unused in split mode)
--- @param fm table|nil (Unused in split mode)
function M.split(lines)
	vim.cmd("botright 20new")
	local buf = vim.api.nvim_get_current_buf()
	local win = vim.api.nvim_get_current_win()

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].filetype = "markdown"
	vim.bo[buf].buflisted = false
	vim.wo[win].wrap = true

	set_close_keymaps(buf, win)
end

--- Display content in a full-screen scratch buffer (like :help style).
--- @param lines table Array of formatted string lines
--- @param sandbox string|nil (Unused in scratch mode)
--- @param lang string|nil (Unused in scratch mode)
--- @param fm table|nil (Unused in scratch mode)
function M.scratch(lines)
	vim.cmd("enew")
	local buf = vim.api.nvim_get_current_buf()
	local win = vim.api.nvim_get_current_win()

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].filetype = "markdown"
	vim.bo[buf].buflisted = false
	vim.wo[win].wrap = true

	set_close_keymaps(buf, win)
end

--- Main entry point for rendering a tip. Routes to float, split, or scratch.
--- @param lines table Array of formatted string lines for the tip body
--- @param sandbox string|nil Optional code block to load into the practice area
--- @param lang string|nil Optional language identifier for the sandbox filetype
--- @param fm table|nil Parsed frontmatter data, used for related navigation
--- @param display string|nil Override the default display mode ("float" | "split" | "scratch")
function M.render(lines, sandbox, lang, fm, display, path)
	local method = display or config.options.ui.default_display or "float"
	if M[method] then
		M[method](lines, sandbox, lang, fm, path)
	else
		vim.notify("[totd] Unknown display method: " .. method, vim.log.levels.WARN)
		M.float(lines, sandbox, lang, fm, path)
	end
end

--- Format a parsed tip into display lines.
--- @param frontmatter table
--- @param body string
--- @return table lines
function M.format_tip(frontmatter, body)
	local lines = {}

	-- Header metadata bar
	local tags = type(frontmatter.tags) == "table" and table.concat(frontmatter.tags, "  ") or (frontmatter.tags or "")
	local mask_badge = frontmatter.is_suspended and "   [MASKED]" or ""

	table.insert(
		lines,
		string.format(
			"  mode: %-10s  complexity: %-12s  tags: %s%s",
			frontmatter.mode or "—",
			frontmatter.complexity or "—",
			tags ~= "" and tags or "—",
			mask_badge
		)
	)
	if frontmatter.source and frontmatter.source ~= "" then
		table.insert(lines, string.format("  source: %s", frontmatter.source))
	end

	table.insert(lines, string.rep("─", 72))
	table.insert(lines, "")

	-- Body content
	for line in (body or ""):gmatch("[^\n]*") do
		table.insert(lines, line)
	end

	return lines
end

return M
