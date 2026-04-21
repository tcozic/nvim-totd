--- lua/totd/init.lua
--- Plugin entry point. Call require('totd').setup(opts) from your config.
local M = {}

local config = require("totd.config")
local api = require("totd.api")

--- Helper to provide completion for Tip identifiers
--- @param arglead string
--- @return table names
local function complete_identifiers(arglead)
	local tips = api.list()
	local names = {}
	for _, t in ipairs(tips) do
		-- Use the virtual path or the physical filename
		local name = t.path:match("^virtual:") and t.path or vim.fn.fnamemodify(t.path, ":t")
		if name:lower():find(arglead:lower(), 1, true) then
			table.insert(names, name)
		end
	end
	return names
end

--- Bootstrap the plugin. Must be called before using the API.
--- @param opts table|nil User configuration (merged with defaults)
function M.setup(opts)
	config.setup(opts or {})
	-- Automatically listen for internal updates to refresh the Snacks dashboard
	-- Automatically listen for internal updates to refresh UI components
	vim.api.nvim_create_autocmd("User", {
		pattern = "TotdUpdate",
		callback = function()
			vim.schedule(function()
				-- 1. Refresh Snacks Dashboard (if active)
				if package.loaded["snacks"] and require("snacks").dashboard then
					local buf = vim.api.nvim_get_current_buf()
					if vim.bo[buf].filetype == "snacks_dashboard" then
						require("snacks").dashboard.update()
					end
				end

				-- 2. NEW: Refresh Lualine (if active)
				if package.loaded["lualine"] then
					require("lualine").refresh()
				end
			end)
		end,
	})
	-- :TotdRandom [complexity=<c>] [mode=<m>] [tags=<t>]
	vim.api.nvim_create_user_command("TotdRandom", function(cmd_opts)
		local args = {}
		for _, arg in ipairs(vim.split(cmd_opts.args, "%s+")) do
			local k, v = arg:match("^(%w+)=(.+)$")
			if k then
				args[k] = v
			end
		end
		api.random(args)
	end, {
		nargs = "*",
		complete = function(arglead)
			if arglead:match("^tags=") then
				local prefix = "tags="
				local search = arglead:sub(#prefix + 1)
				local tips = api.list()
				local tags = {}
				for _, tip in ipairs(tips) do
					for _, tag in ipairs(tip.tags) do
						if tag:find(search) then
							tags[tag] = true
						end
					end
				end
				local result = {}
				for tag, _ in pairs(tags) do
					table.insert(result, prefix .. tag)
				end
				return result
			end
			return { "complexity=", "mode=", "tags=", "display=", "context=" }
		end,
		desc = "Show a random Tip of the Day",
	})

	-- :TotdCreate [title]
	vim.api.nvim_create_user_command("TotdCreate", function(cmd_opts)
		local title = cmd_opts.args ~= "" and cmd_opts.args or nil
		api.create({ title = title })
	end, {
		nargs = "?",
		desc = "Create a new Tip of the Day",
	})

	-- :TotdOpen <filename>
	vim.api.nvim_create_user_command("TotdOpen", function(cmd_opts)
		if cmd_opts.args == "" then
			vim.notify("[totd] Usage: TotdOpen <filename/identifier>", vim.log.levels.WARN)
			return
		end
		api.open(cmd_opts.args)
	end, {
		nargs = 1,
		complete = complete_identifiers,
		desc = "Open a specific Tip of the Day by filename or identifier",
	})

	-- :TotdList  (prints a quick summary to the messages area)
	vim.api.nvim_create_user_command("TotdList", function()
		local tips = api.list()
		if #tips == 0 then
			vim.notify("[totd] Database is empty.", vim.log.levels.INFO)
			return
		end
		local lines = { string.format("[totd] %d tip(s) found:\n", #tips) }
		for i, t in ipairs(tips) do
			table.insert(lines, string.format("  %2d. %-40s  [%s / %s]", i, t.title, t.mode, t.complexity))
		end
		vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
	end, {
		desc = "List all available tips",
	})

	-- :TotdEdit <filename>
	vim.api.nvim_create_user_command("TotdEdit", function(cmd_opts)
		if cmd_opts.args == "" then
			vim.notify("[totd] Usage: TotdEdit <filename>", vim.log.levels.WARN)
			return
		end
		api.edit(cmd_opts.args)
	end, {
		nargs = 1,
		complete = function(arglead)
			-- Reuse the same completion logic as TotdOpen
			local db = config.options.db_path
			local files = vim.fn.globpath(db, arglead .. "*.md", false, true)
			local names = {}
			for _, f in ipairs(files) do
				table.insert(names, vim.fn.fnamemodify(f, ":t"))
			end
			return names
		end,
		desc = "Edit the raw Markdown of a Tip of the Day",
	})

	-- :TotdImport <filepath> or <glob>
	vim.api.nvim_create_user_command("TotdImport", function(cmd_opts)
		if #cmd_opts.fargs == 0 then
			vim.notify("[totd] Usage: TotdImport <filepath/glob>...", vim.log.levels.WARN)
			return
		end

		local imported_count = 0

		for _, arg in ipairs(cmd_opts.fargs) do
			local files = vim.fn.expand(arg, false, true)
			for _, file in ipairs(files) do
				if vim.fn.isdirectory(file) == 0 then
					api.import(file)
					imported_count = imported_count + 1
				end
			end
		end

		if imported_count == 0 then
			vim.notify("[totd] No valid files found matching: " .. cmd_opts.args, vim.log.levels.WARN)
		else
			vim.notify(string.format("[totd] Successfully processed %d file(s).", imported_count), vim.log.levels.INFO)
		end
	end, {
		nargs = "+",
		complete = "file",
		desc = "Import existing markdown file(s) into the Totd database",
	})

	-- :TotdDelete <filename>
	vim.api.nvim_create_user_command("TotdDelete", function(cmd_opts)
		if cmd_opts.args == "" then
			vim.notify("[totd] Usage: TotdDelete <filename>", vim.log.levels.WARN)
			return
		end
		api.delete(cmd_opts.args)
	end, {
		nargs = 1,
		complete = function(arglead)
			local db = config.options.db_path
			local files = vim.fn.globpath(db, arglead .. "*.md", false, true)
			local names = {}
			for _, f in ipairs(files) do
				table.insert(names, vim.fn.fnamemodify(f, ":t"))
			end
			return names
		end,
		desc = "Delete a Tip of the Day",
	})

	-- :TotdLast
	vim.api.nvim_create_user_command("TotdLast", function(cmd_opts)
		api.last()
	end, { desc = "Show the most recently generated Tip of the Day" })

	-- :TotdReset
	vim.api.nvim_create_user_command("TotdReset", function()
		api.reset_progress()
	end, {
		desc = "Reset all learning progress (Anki view counts) to zero",
	})

	-- lua/totd/init.lua
	-- BUG 9: TotdTeaser now uses get_current() to avoid destructive re-rolls
	vim.api.nvim_create_user_command("TotdTeaser", function()
		local tip = api.get_current()
		local teaser = api.get_teaser_data(tip)
		vim.notify(string.format("%s\n%s", teaser.title, teaser.synopsis), vim.log.levels.INFO)
	end, { desc = "Preview current tip teaser" })

	-- :TotdClearCache
	vim.api.nvim_create_user_command("TotdClearCache", function()
		api.clear_cache()
	end, {
		desc = "Clear disk and memory caches for external web sources",
	})
	-- ── Auto-show on startup ───────────────────────────────────────────────────
	if config.options.show_on_startup then
		vim.api.nvim_create_autocmd("VimEnter", {
			once = true,
			callback = function()
				vim.defer_fn(function()
					api.random()
				end, 200)
			end,
		})
	end
end

-- Re-export the API so callers can do require('totd').random() etc.
M.random = api.random
M.create = api.create
M.open = api.open
M.list = api.list
M.edit = api.edit
M.import = api.import
M.delete = api.delete
M.pick_random = api.pick_random
M.last = api.last
M.reset_progress = api.reset_progress
M.get_teaser_data = api.get_teaser_data
M.get_formatted_body = api.get_formatted_body
M.toggle_suspend = api.toggle_suspend
M.score = api.score
M.clear_cache = api.clear_cache
M.get_current = api.get_current
M.snacks_picker = function()
	require("totd.integrations.snacks").picker()
end

M.snacks_dashboard = function(opts)
	return require("totd.integrations.snacks").dashboard_section(opts)
end
M.lualine_component = function(opts)
	return require("totd.integrations.lualine").component(opts)
end
return M
