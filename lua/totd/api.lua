-- lua/totd/api.lua
--- The public-facing API. All functions are safe to call from keymaps/commands.
local M = {}

local config = require("totd.config")
local parser = require("totd.parser")
local ui = require("totd.ui")
local current_tip_path = nil

local uv = uv or vim.loop
math.randomseed(uv.hrtime())

local cached_tutor_tips = {}
local cached_help_tips = nil
local cached_custom_tips = {}
--- Fetches custom tips and caches them according to source config
local function fetch_custom_source(name, source_cfg)
	local cache_mode = source_cfg.auto_cache or "session"

	-- Mode 1: No caching (always fetch)
	if cache_mode == false or cache_mode == "none" then
		return source_cfg.fetch() or {}
	end

	-- Mode 2: Session caching (in-memory only, current default)
	if cache_mode == "session" then
		if cached_custom_tips[name] then
			return cached_custom_tips[name]
		end
		local results = source_cfg.fetch() or {}
		cached_custom_tips[name] = results
		return results
	end

	-- Mode 3: Disk caching (persistent across Neovim restarts)
	if cache_mode == "disk" then
		local cache_file = config.options.db_path .. "/.cache_source_" .. name .. ".json"

		-- Keep in memory if we've already loaded the disk cache this session
		if cached_custom_tips[name] then
			return cached_custom_tips[name]
		end

		-- Try reading from disk first
		if vim.fn.filereadable(cache_file) == 1 then
			local f = io.open(cache_file, "r")
			if f then
				local content = f:read("*a")
				f:close()
				local ok, parsed = pcall(vim.fn.json_decode, content)
				if ok and type(parsed) == "table" and #parsed > 0 then
					cached_custom_tips[name] = parsed
					return parsed
				end
			end
		end

		-- Cache miss: run the fetch function and write to disk
		local results = source_cfg.fetch() or {}
		if #results > 0 then
			local f = io.open(cache_file, "w")
			if f then
				f:write(vim.fn.json_encode(results))
				f:close()
			end
			cached_custom_tips[name] = results
		end
		return results
	end

	return {}
end
--- Get a specific custom tip by source name and title
local function get_custom_tip(name, title)
	local cfg = config.options.custom_sources and config.options.custom_sources[name]
	if not cfg then
		return nil
	end
	for _, t in ipairs(fetch_custom_source(name, cfg)) do
		if t.fm.title == title then
			return t
		end
	end
	return nil
end
--- Fetches and parses the built-in vim help tips into virtual tips
--- @return table Array of tips
local function fetch_virtual_help_tips()
	if cached_help_tips then
		return cached_help_tips
	end

	local paths = vim.api.nvim_get_runtime_file("doc/tips.txt", false)
	if #paths == 0 then
		return {}
	end

	local lines = vim.fn.readfile(paths[1])
	local results = {}
	local current_title = nil
	local current_tag = nil
	local current_body = {}

	local function save_tip()
		if current_title and #current_body > 0 then
			table.insert(results, {
				fm = {
					title = current_title,
					tag = current_tag,
					mode = "normal",
					tags = { "help", "reference" },
					source = "help-tips",
					complexity = "intermediate",
					related = {},
				},
				body = table.concat(current_body, "\n"),
			})
		end
	end

	for _, line in ipairs(lines) do
		-- Detect section separators
		if line:match("^%s*====+") then
			save_tip()
			current_title = nil
			current_body = {}
		-- Detect Title and Tag (e.g., "Editing C programs *C-editing*")
		elseif not current_title and line:match("^[%w%s,%.]+%s+%*%S+%*") then
			current_title, current_tag = line:match("^([%w%s,%.]+)%s+%*(%S+)%*")
			current_title = vim.trim(current_title)
			table.insert(current_body, "# " .. current_title)
			table.insert(current_body, "")
		elseif current_title then
			-- Clean up Vim help syntax: |tag| -> `tag` and *anchor* -> ""
			local clean_line = line:gsub("|(%S+)|", "`%1`"):gsub("%*%S+%*", "")
			table.insert(current_body, clean_line)
		end
	end
	save_tip()

	cached_help_tips = results
	return cached_help_tips
end
--- Get a specific virtual help tip by tag or title
--- @param tag_or_title string
--- @return table|nil
local function get_virtual_help_tip(tag_or_title)
	for _, t in ipairs(fetch_virtual_help_tips()) do
		if t.fm.tag == tag_or_title or t.fm.title == tag_or_title then
			return t
		end
	end
	return nil
end
--- Fetches and parses the built-in vimtutor lessons into virtual tips
--- @param lang string|nil The ISO language code
--- @return table Array of tips
local function fetch_virtual_tutor(lang)
	-- Default to English if no language is specified
	lang = lang or "en"
	if cached_tutor_tips[lang] then
		return cached_tutor_tips[lang]
	end
	-- 1. Grab ALL .tutor files in the specified language folder
	local paths = vim.api.nvim_get_runtime_file("tutor/" .. lang .. "/*.tutor", true)

	-- Fallback to English if the requested language doesn't have tutor files
	if #paths == 0 and lang ~= "en" then
		paths = vim.api.nvim_get_runtime_file("tutor/en/*.tutor", true)
	end

	-- Legacy fallback for older Neovim versions
	if #paths == 0 then
		paths = vim.api.nvim_get_runtime_file("tutor/tutor", false)
	end

	if #paths == 0 then
		vim.notify("[totd] Could not find any Neovim tutor files.", vim.log.levels.WARN)
		return {}
	end

	local results = {}

	-- 2. Loop through every tutor file found
	for _, tutor_path in ipairs(paths) do
		local lines = vim.fn.readfile(tutor_path)
		local current_title = nil
		local current_body = {}

		local function save_lesson()
			if current_title and #current_body > 0 then
				table.insert(results, {
					fm = {
						title = current_title,
						mode = "normal",
						tags = { "tutor", "basics" },
						source = "vimtutor",
						complexity = "tutor",
						related = {},
					},
					body = table.concat(current_body, "\n"),
				})
			end
		end

		for _, line in ipairs(lines) do
			local lesson_match = line:match("^#*%s*(Lesson%s+%d+.*)")

			if lesson_match then
				save_lesson()
				current_title = vim.trim(lesson_match)
				current_body = { "# " .. current_title, "" }
			elseif current_title then
				-- Strip out horizontal visual dividers native to vimtutor
				if not line:match("^===+") and not line:match("^~+$") then
					local clean_line = line:gsub("(`[^`]+`){%a+}", "%1")
					table.insert(current_body, clean_line)
				end
			end
		end
		-- Save the final lesson from the current file
		save_lesson()
	end

	cached_tutor_tips[lang] = results
	return cached_tutor_tips[lang]
end
--- Get a specific virtual tutor tip by title
--- @param title string
--- @return table|nil
local function get_virtual_tutor_tip(title)
	for _, t in ipairs(fetch_virtual_tutor()) do
		if t.fm.title == title then
			return t
		end
	end
	return nil
end
-- ─────────────────────────────────────────────────────────────────────────────
-- State Management (Anki-lite)
-- ─────────────────────────────────────────────────────────────────────────────

--- Get the path to the hidden state file
--- @return string path
local function get_state_file()
	return config.options.db_path .. "/.totd_state.json"
end

--- Load the view counts from disk
--- @return table<string, number>
local function load_state()
	local f = io.open(get_state_file(), "r")
	if not f then
		return {}
	end
	local content = f:read("*a")
	f:close()
	local ok, parsed = pcall(vim.fn.json_decode, content)
	return ok and parsed or {}
end


-- Queue to prevent concurrent write race conditions
local write_queue = {}
local is_writing = false

local function process_queue()
	if is_writing or #write_queue == 0 then return end
	is_writing = true
	
	-- We now pop a pre-encoded string, no Vimscript functions needed here!
	local json_str = table.remove(write_queue, 1)
	local filepath = get_state_file()

	vim.uv.fs_open(filepath, "w", 438, function(err, fd)
		if err or not fd then
			vim.schedule(function()
				vim.notify("[totd] Failed to open state file: " .. (err or "unknown"), vim.log.levels.ERROR)
				is_writing = false
				process_queue()
			end)
			return
		end
		
		vim.uv.fs_write(fd, json_str, -1, function(write_err)
			if write_err then
				vim.schedule(function()
					vim.notify("[totd] Failed to write state file: " .. write_err, vim.log.levels.ERROR)
				end)
			end
			
			vim.uv.fs_close(fd, function()
				-- Jump back to the main thread before running the next item
				vim.schedule(function()
					is_writing = false
					process_queue()
				end)
			end)
		end)
	end)
end

--- Save the view counts to disk asynchronously
--- @param state table<string, number|boolean>
local function save_state(state)
	-- 1. Encode JSON synchronously on the main thread (100% safe)
	-- 2. This natively creates a snapshot, so we no longer need vim.deepcopy
	local ok, json_str = pcall(vim.fn.json_encode, state)
	if not ok then
		vim.notify("[totd] Failed to encode state JSON", vim.log.levels.ERROR)
		return
	end
	
	table.insert(write_queue, json_str)
	process_queue()
end
--- Increment the view count for a specific tip
--- @param filename string
local function track_view(filename)
	local state = load_state()
	state[filename] = (state[filename] or 0) + 1
	save_state(state)
end
--- Check if a tip is currently suspended/masked
--- @param identifier string
--- @return boolean
local function is_suspended(identifier)
	local state = load_state()
	local filename = vim.fn.fnamemodify(identifier, ":t")
	return state["suspend:" .. filename] == true
end

--- Toggle the suspend/mask state of a tip and reload it
--- @param identifier string
function M.toggle_suspend(identifier)
	local state = load_state()
	local filename = vim.fn.fnamemodify(identifier, ":t")
	local sus_key = "suspend:" .. filename

	if state[sus_key] then
		state[sus_key] = nil
		vim.notify("[totd] Tip UNMASKED. It will now appear in random rolls.", vim.log.levels.INFO)
	else
		state[sus_key] = true
		vim.notify("[totd] Tip MASKED. It is suspended from random rolls.", vim.log.levels.INFO)
	end

	save_state(state)
	M.open(identifier) -- Instantly reload the UI to show the state change
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Internal helpers
-- ─────────────────────────────────────────────────────────────────────────────

--- Ensure the database directory exists, creating it if needed.
--- @return string|nil path, string|nil err
local function ensure_db()
	local path = config.options.db_path
	if vim.fn.isdirectory(path) == 0 then
		local ok = vim.fn.mkdir(path, "p")
		if ok == 0 then
			return nil, "Could not create db_path: " .. path
		end
	end
	return path, nil
end

--- Convert a human title into a safe filename (kebab-case).
--- @param title string
--- @return string
local function title_to_filename(title)
	return title
		:lower()
		:gsub("[^%w%s%-]", "") -- strip non-word, non-space, non-dash
		:gsub("%s+", "-") -- spaces → dashes
		:gsub("%-+", "-") -- collapse multiple dashes
		:gsub("^%-+", "") -- strip leading dash
		:gsub("%-+$", "") -- strip trailing dash
end

--- Check whether a tip's frontmatter matches a filter table.
--- @param fm table Parsed frontmatter
--- @param opts table Filter options (complexity, mode, tags)
--- @return boolean
local function matches(fm, opts)
	if not opts then
		return true
	end

	if opts.complexity and fm.complexity ~= opts.complexity then
		return false
	end

	if opts.mode and fm.mode ~= opts.mode then
		return false
	end

	if opts.tags then
		local tip_tags = type(fm.tags) == "table" and fm.tags or {}
		for _, wanted in ipairs(opts.tags) do
			local found = false
			for _, t in ipairs(tip_tags) do
				if t == wanted then
					found = true
					break
				end
			end
			if not found then
				return false
			end
		end
	end

	return true
end

--- Build the YAML frontmatter + Markdown skeleton for a new tip.
--- @param title string Human-readable title
--- @return string
local function build_template(title)
	local tpl = config.options.template
	local tags_yaml = ""
	for _, tag in ipairs(tpl.default_tags or { "general" }) do
		tags_yaml = tags_yaml .. "\n  - " .. tag
	end

	return string.format(
		[[---
title: %s
mode: %s
tags:%s
source: %s
complexity: %s
related:
---

# %s

**Commands:** `` (brief description)

> **Synopsis:** One-sentence summary of the tip's value proposition.

## Details
In-depth explanation of the mechanics and philosophy behind the tip.

## To go further
Advanced edge cases, related configurations, or common pitfalls.

---
## Test it
Task: Actionable objective
1. Step 1
2. Step 2

```
interactive practice block
```
]],
		title,
		tpl.default_mode or "normal",
		tags_yaml,
		tpl.default_source or "User",
		tpl.default_complexity or "beginner",
		title
	)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Public API
-- ─────────────────────────────────────────────────────────────────────────────

--- Return a filtered list of all tips with their parsed frontmatter.
--- This is the data source for Snacks.picker (or any other picker).
---
--- @param opts table|nil { complexity=string, mode=string, tags=table }
--- @return table Array of { title, mode, complexity, tags, source, related, path }
function M.list(opts)
	local db_path, err = ensure_db()
	if not db_path then
		vim.notify("[totd] " .. (err or "Database path is nil"), vim.log.levels.ERROR)
		return {}
	end

	local results = {}

	-- Build a quick lookup table for enabled sources
	local active_sources = {}
	for _, source in ipairs(config.options.enabled_sources or { "local", "tutor", "help" }) do
		active_sources[source] = true
	end
	for source_name, _ in pairs(config.options.custom_sources or {}) do
		if active_sources[source_name] == nil then
			active_sources[source_name] = true
		end
	end
	-- 1. Inject Local Files
	if active_sources["local"] then
		local handle = uv.fs_scandir(db_path)
		if handle then
			while true do
				local name, ftype = uv.fs_scandir_next(handle)
				if not name then
					break
				end
				if (ftype == "file" or ftype == nil) and name:match("%.md$") then
					local full_path = db_path .. "/" .. name
					local content = parser.read_file(full_path)
					if content then
						local fm, _ = parser.parse(content)
						if fm and matches(fm, opts) then
							table.insert(results, {
								title = fm.title or name,
								mode = fm.mode or "",
								complexity = fm.complexity or "",
								tags = fm.tags or {},
								source = fm.source or "",
								related = fm.related or {},
								path = full_path,
							})
						end
					end
				end
			end
		end
	end

	-- 2. Inject Virtual Tutor Tips
	if active_sources["tutor"] then
		for _, t in ipairs(fetch_virtual_tutor()) do
			local safe_title = title_to_filename(t.fm.title)
			local expected_path = db_path .. "/tutor-" .. safe_title .. ".md"

			if vim.fn.filereadable(expected_path) == 0 then
				if matches(t.fm, opts) then
					table.insert(results, {
						title = t.fm.title,
						mode = t.fm.mode,
						complexity = t.fm.complexity,
						tags = t.fm.tags,
						source = t.fm.source,
						related = t.fm.related,
						path = "virtual:tutor:" .. t.fm.title,
					})
				end
			end
		end
	end

	-- 3. Inject Virtual Help Tips
	if active_sources["help"] then
		for _, t in ipairs(fetch_virtual_help_tips()) do
			local safe_title = title_to_filename(t.fm.title)
			local expected_path = db_path .. "/help-" .. safe_title .. ".md"

			if vim.fn.filereadable(expected_path) == 0 then
				if matches(t.fm, opts) then
					table.insert(results, {
						title = t.fm.title,
						mode = t.fm.mode,
						complexity = t.fm.complexity,
						tags = t.fm.tags,
						source = t.fm.source,
						related = t.fm.related,
						path = "virtual:help:" .. (t.fm.tag or t.fm.title),
					})
				end
			end
		end
	end
	-- 4. Inject Custom Sources
	for source_name, source_cfg in pairs(config.options.custom_sources or {}) do
		if active_sources[source_name] and type(source_cfg.fetch) == "function" then
			for _, t in ipairs(fetch_custom_source(source_name, source_cfg)) do
				local safe_title = title_to_filename(t.fm.title)
				local expected_path = db_path .. "/" .. source_name .. "-" .. safe_title .. ".md"

				if vim.fn.filereadable(expected_path) == 0 then
					if matches(t.fm, opts) then
						table.insert(results, {
							title = t.fm.title,
							mode = t.fm.mode,
							complexity = t.fm.complexity,
							tags = t.fm.tags,
							source = t.fm.source,
							related = t.fm.related,
							path = "virtual:custom:" .. source_name .. ":" .. t.fm.title,
						})
					end
				end
			end
		end
	end

	return results
end

--- Headless function: Picks a weighted random tip, caches it, and returns the data.
--- @param opts table|nil
--- @return table|nil tip_data
--- Headless function: Picks a weighted random tip, caches it, and returns the data.
function M.pick_random(opts)
	opts = opts or {}
	local tips = M.list(opts)

	if #tips == 0 then
		return nil
	end

	local state = load_state()
	local total_weight = 0
	local weighted_tips = {}

	-- Capture the current filetype if context=auto is requested
	local context_ft = nil
	if opts.context == "auto" then
		context_ft = vim.bo.filetype
	end

	for _, tip in ipairs(tips) do
		local filename = vim.fn.fnamemodify(tip.path, ":t")

		if not state["suspend:" .. filename] then
			local views = state[filename] or 0
			local weight = 100 / (views + 1)

			-- Heavily bias the weight if a tag matches the current filetype
			if context_ft then
				for _, tag in ipairs(tip.tags or {}) do
					if tag:lower() == context_ft:lower() then
						weight = weight * 50
						break
					end
				end
			end

			total_weight = total_weight + weight
			table.insert(weighted_tips, { tip = tip, weight = weight })
		end
	end

	if #weighted_tips == 0 then
		return nil
	end

	local target = math.random(1, math.max(1, math.floor(total_weight)))
	-- Safe fallback ignoring suspended tips
	local selected_tip = weighted_tips[1].tip
	for _, item in ipairs(weighted_tips) do
		target = target - item.weight
		if target <= 0 then
			selected_tip = item.tip
			break
		end
	end

	-- Cache state for the dashboard and the "Last" command
	current_tip_path = selected_tip.path
	return selected_tip
end
--- Open and display a random tip.
--- @param opts table|nil { complexity=string, mode=string, tags=table, display=string }
function M.random(opts)
	local tip = M.pick_random(opts)
	if tip then
		M.open(tip.path, opts and opts.display)
	else
		vim.notify("[totd] No tips found. Add some with :TotdCreate!", vim.log.levels.INFO)
	end
end

--- Opens the most recently cached tip (e.g., from the dashboard or last random roll).
--- @param display string|nil
function M.last(display)
	if current_tip_path and (current_tip_path:match("^virtual:") or vim.fn.filereadable(current_tip_path) == 1) then
		M.open(current_tip_path, display)
	else
		vim.notify("[totd] No recent tip in memory. Rolling a new one...", vim.log.levels.INFO)
		M.random({ display = display })
	end
end

--- Extracts standard fenced code blocks from virtual tip bodies
--- @param body string
--- @return string|nil sandbox, string|nil lang
local function extract_virtual_sandbox(body)
	local lang, code = body:match("```(%w*)\n(.-)\n```%s*$")
	if code then
		return vim.trim(code), lang ~= "" and lang or nil
	end
	return nil, nil
end

--- Open a specific tip by filename or absolute path.
---
--- @param identifier string Filename (e.g. "the-dot-formula.md") or absolute path
--- @param display string|nil "float" | "split" | "scratch"
--- Open a specific tip by filename or absolute path.
function M.open(identifier, display)
	if identifier:match("^virtual:help:") then
		local tag = identifier:sub(14)
		local t = get_virtual_help_tip(tag)
		if not t then
			return
		end

		track_view(identifier)
		current_tip_path = identifier
		t.fm.is_suspended = is_suspended(identifier)

		local lines = ui.format_tip(t.fm, t.body)
		-- Help tips use the extractor to grab just the code block
		local sandbox, lang = extract_virtual_sandbox(t.body)
		ui.render(lines, sandbox, lang or "vim", t.fm, display, identifier)
		return
	end

	if identifier:match("^virtual:tutor:") then
		local title = identifier:sub(15)
		local t = get_virtual_tutor_tip(title)
		if not t then
			return
		end

		track_view(identifier)
		current_tip_path = identifier
		t.fm.is_suspended = is_suspended(identifier)

		local lines = ui.format_tip(t.fm, t.body)
		-- Tutor tips bypass the extractor and feed the whole body
		ui.render(lines, t.body, "text", t.fm, display, identifier)
		return
	end
	if identifier:match("^virtual:custom:") then
		local source_name, title = identifier:match("^virtual:custom:([^:]+):(.+)$")
		local t = get_custom_tip(source_name, title)
		if not t then
			return
		end

		track_view(identifier)
		current_tip_path = identifier
		t.fm.is_suspended = is_suspended(identifier)

		local lines = ui.format_tip(t.fm, t.body)

		-- Use custom sandbox extractor if provided, else fallback to standard fenced blocks
		local sandbox, lang
		local source_cfg = config.options.custom_sources and config.options.custom_sources[source_name]

		if source_cfg and source_cfg.extract_sandbox then
			sandbox, lang = source_cfg.extract_sandbox(t.body)
		else
			sandbox, lang = extract_virtual_sandbox(t.body)
		end
		ui.render(lines, sandbox, lang or "text", t.fm, display, identifier)
		return
	end
	local path = identifier:sub(1, 1) == "/" and identifier or (config.options.db_path .. "/" .. identifier)
	track_view(vim.fn.fnamemodify(path, ":t"))

	local content, err = parser.read_file(path)
	if not content then
		vim.notify("[totd] " .. (err or "Could not read tip"), vim.log.levels.ERROR)
		return
	end

	local fm, body, sandbox, lang = parser.parse(content)
	if not fm then
		fm = {}
		body = content
		sandbox = nil
		lang = nil
	end
	fm.is_suspended = is_suspended(identifier)
	local lines = ui.format_tip(fm, body)
	-- Add identifier here!
	ui.render(lines, sandbox, lang, fm, display, identifier)
end

--- Scaffold a new tip file and drop the user into an editing session.
---
--- @param opts table|nil { title=string }
function M.create(opts)
	opts = opts or {}

	local function do_create(title)
		if not title or vim.trim(title) == "" then
			vim.notify("[totd] Aborted: no title provided.", vim.log.levels.INFO)
			return
		end

		local db_path, err = ensure_db()
		if not db_path then
			vim.notify("[totd] " .. err, vim.log.levels.ERROR)
			return
		end

		local filename = title_to_filename(vim.trim(title)) .. ".md"
		local filepath = db_path .. "/" .. filename

		if vim.fn.filereadable(filepath) == 1 then
			vim.notify("[totd] File already exists: " .. filename, vim.log.levels.WARN)
		else
			local f = io.open(filepath, "w")
			if not f then
				vim.notify("[totd] Cannot write to: " .. filepath, vim.log.levels.ERROR)
				return
			end
			f:write(build_template(vim.trim(title)))
			f:close()
		end

		vim.cmd.edit(filepath)

		-- Position cursor at the Synopsis placeholder and enter insert mode
		vim.defer_fn(function()
			-- Search for the placeholder text specifically
			local ok = pcall(vim.cmd, [[/\VOne-sentence summary of the tip's value proposition.]])
			if ok then
				-- 'cgn' changes the search match and drops into Insert mode
				vim.cmd("normal! cgn")
			end
		end, 50)
	end

	if opts.title then
		do_create(opts.title)
	else
		vim.ui.input({ prompt = "Tip title: " }, do_create)
	end
end

--- Opens the raw tip file in the current window for editing.
--- @param identifier string Filename or absolute path
function M.edit(identifier)
	-- Intercept Virtual Tips for Materialization
	if identifier:match("^virtual:") then
		local t, prefix
		if identifier:match("^virtual:tutor:") then
			local title = identifier:sub(15)
			t = get_virtual_tutor_tip(title)
			prefix = "tutor-"
		elseif identifier:match("^virtual:help:") then
			local tag = identifier:sub(14)
			t = get_virtual_help_tip(tag)
			prefix = "help-"
		elseif identifier:match("^virtual:custom:") then
			local source_name, title = identifier:match("^virtual:custom:([^:]+):(.+)$")
			t = get_custom_tip(source_name, title)
			prefix = source_name .. "-"
		end

		if not t then
			return
		end

		local db_path, db_err = ensure_db()
		if not db_path then
			vim.notify("[totd] " .. (db_err or "Could not ensure DB path"), vim.log.levels.ERROR)
			return
		end
		local safe_title = title_to_filename(t.fm.title)
		local dest_path = db_path .. "/" .. prefix .. safe_title .. ".md"

		-- Construct the YAML tags block
		local tags_yaml = ""
		for _, tag in ipairs(t.fm.tags or {}) do
			tags_yaml = tags_yaml .. "\n  - " .. tag
		end

		-- Build the file content, appending " (Edited)" to the source
		local content = string.format(
			[[---
title: "%s"
mode: %s
tags:%s
source: %s (Edited)
complexity: %s
---

%s]],
			t.fm.title,
			t.fm.mode,
			tags_yaml,
			t.fm.source,
			t.fm.complexity,
			t.body
		)

		-- Write the file to disk
		local f = io.open(dest_path, "w")
		if f then
			f:write(content)
			f:close()
			vim.notify("[totd] Materialized virtual tip to: " .. prefix .. safe_title .. ".md", vim.log.levels.INFO)
		end

		-- Open the newly created physical file
		vim.cmd.edit(dest_path)
		return
	end

	-- Existing physical file logic
	local path = identifier:sub(1, 1) == "/" and identifier or (config.options.db_path .. "/" .. identifier)
	if vim.fn.filereadable(path) == 0 then
		vim.notify("[totd] File not found: " .. path, vim.log.levels.ERROR)
		return
	end
	vim.cmd.edit(path)
end

--- Imports an existing Markdown file into the database, naming it correctly based on its title.
--- @param source_path string Path to the external file to import
function M.import(source_path)
	-- 1. Read the source file
	local content, err = parser.read_file(source_path)
	if not content then
		vim.notify("[totd] Cannot read source file: " .. (err or source_path), vim.log.levels.ERROR)
		return
	end

	-- 2. Parse the frontmatter to extract the official title
	local fm, _ = parser.parse(content)
	-- Fallback to the original filename (minus extension) if parsing fails
	local title = (fm and fm.title) and fm.title or vim.fn.fnamemodify(source_path, ":t:r")

	-- 3. Ensure the database exists
	local db_path, db_err = ensure_db()
	if not db_path then
		vim.notify("[totd] " .. db_err, vim.log.levels.ERROR)
		return
	end

	-- 4. Construct the sanitized destination path
	local filename = title_to_filename(title) .. ".md"
	local dest_path = db_path .. "/" .. filename

	-- 5. Prevent accidental overwrites
	if vim.fn.filereadable(dest_path) == 1 then
		vim.notify("[totd] Tip already exists in database: " .. filename, vim.log.levels.WARN)
		return
	end

	-- 6. Write the exact content to the new database file
	local f = io.open(dest_path, "w")
	if not f then
		vim.notify("[totd] Cannot write to: " .. dest_path, vim.log.levels.ERROR)
		return
	end
	f:write(content)
	f:close()

	vim.notify(
		string.format("[totd] Imported '%s' -> '%s'", vim.fn.fnamemodify(source_path, ":t"), filename),
		vim.log.levels.INFO
	)
end

--- Deletes a tip from the database.
--- @param identifier string Filename or absolute path
function M.delete(identifier)
	local path = identifier:sub(1, 1) == "/" and identifier or (config.options.db_path .. "/" .. identifier)

	if vim.fn.filereadable(path) == 0 then
		vim.notify("[totd] File not found: " .. path, vim.log.levels.ERROR)
		return
	end

	-- Polite confirmation prompt
	local filename = vim.fn.fnamemodify(path, ":t")
	local choice = vim.fn.confirm("Delete tip: " .. filename .. "?", "&Yes\n&No", 2)

	if choice == 1 then
		-- vim.fn.delete returns 0 on success
		if vim.fn.delete(path) == 0 then
			vim.notify("[totd] Deleted: " .. filename, vim.log.levels.INFO)
		else
			vim.notify("[totd] Failed to delete: " .. path, vim.log.levels.ERROR)
		end
	else
		vim.notify("[totd] Deletion cancelled.", vim.log.levels.INFO)
	end
end

--- Resets all learning progress by clearing the Anki-lite view counts.
--- This overwrites the hidden state file with an empty table.
function M.reset_progress()
	local choice = vim.fn.confirm("Reset all learning progress?", "&Yes\n&No", 2)
	if choice == 1 then
		save_state({})
		vim.notify("[totd] View counts reset to zero. All tips have weight 100.", vim.log.levels.INFO)
	else
		vim.notify("[totd] Reset cancelled.", vim.log.levels.INFO)
	end
end

--- Returns the full formatted lines (headers + body) for any tip identifier.
--- @param identifier string
--- @return table lines
function M.get_formatted_body(identifier)
	local fm, body
	if identifier:match("^virtual:tutor:") then
		local title = identifier:sub(15)
		local t = get_virtual_tutor_tip(title)
		if not t then
			return { "Lesson not found: " .. title }
		end
		fm, body = t.fm, t.body
	elseif identifier:match("^virtual:help:") then
		local tag = identifier:sub(14)
		local t = get_virtual_help_tip(tag)
		if not t then
			return { "Help tip not found: " .. tag }
		end
		fm, body = t.fm, t.body
	elseif identifier:match("^virtual:custom:") then
		local source_name, title = identifier:match("^virtual:custom:([^:]+):(.+)$")
		local t = get_custom_tip(source_name, title)
		if not t then
			return { "Custom tip not found: " .. title }
		end
		fm, body = t.fm, t.body
	else
		-- Handle physical files
		local path = identifier:sub(1, 1) == "/" and identifier or (config.options.db_path .. "/" .. identifier)
		local content = parser.read_file(path)
		if not content then
			return { "Error reading file: " .. path }
		end
		fm, body = parser.parse(content)
	end

	-- Use your existing UI formatter to keep the look consistent
	return ui.format_tip(fm, body)
end

--- Extracts raw components from a tip for custom dashboard generation.
--- @param tip table|nil The tip data table
--- @return table data { title=string, synopsis=string }
function M.get_teaser_data(tip)
	if not tip or not tip.path then
		return { title = "No Tips Loaded", synopsis = "Run :TotdCreate to start learning." }
	end

	local body = ""
	if tip.path:match("^virtual:help:") then
		local tag = tip.path:sub(14)
		local t = get_virtual_help_tip(tag)
		body = t and t.body or ""
	elseif tip.path:match("^virtual:tutor:") then
		local title = tip.path:sub(15)
		local t = get_virtual_tutor_tip(title)
		body = t and t.body or ""
	elseif tip.path:match("^virtual:custom:") then
		local source_name, title = tip.path:match("^virtual:custom:([^:]+):(.+)$")
		local t = get_custom_tip(source_name, title)
		body = t and t.body or ""
	else
		local content = parser.read_file(tip.path)
		if not content then
			return { title = tip.title, synopsis = "[Error reading file]" }
		end
		_, body = parser.parse(content)
		-- FIX: Prevent nil crash on empty bodies
		body = body or ""
	end

	-- 1. Try to find the explicit synopsis first
	local synopsis = body:match(">%s*%*%*Synopsis:%*%*%s*([^\n]+)")

	-- 2. Fallback: Extract the first X words
	if not synopsis then
		-- Clean the body: Remove the H1 header and any bold/italic markers
		local clean_text = body
			:gsub("^#+[^\n]*\n", "") -- Remove leading # Header
			:gsub("[%*%_]", "") -- Remove * or _ used for bold/italic
			:gsub("\n+", " ") -- Collapse newlines into spaces
			:gsub("^%s+", "") -- Trim leading whitespace

		-- Collect first 15 words
		local words = {}
		local max_words = 15
		for word in clean_text:gmatch("%S+") do
			table.insert(words, word)
			if #words >= max_words then
				break
			end
		end

		synopsis = table.concat(words, " ")

		-- Add ellipsis if the original text was longer than our snippet
		if #clean_text > #synopsis then
			synopsis = synopsis .. "..."
		end
	end

	return {
		title = tip.title,
		synopsis = synopsis,
	}
end

--- Clears all disk caches and in-memory caches for custom sources.
function M.clear_cache()
	local db_path, err = ensure_db()
	if not db_path then
		vim.notify("[totd] " .. (err or "Cannot access database"), vim.log.levels.ERROR)
		return
	end

	local count = 0

	-- 1. Clear in-memory cache
	cached_custom_tips = {}

	-- 2. Clear disk cache files using libuv (ignores glob/dotfile quirks)
	local handle = uv.fs_scandir(db_path)
	if handle then
		while true do
			local name, ftype = uv.fs_scandir_next(handle)
			if not name then
				break
			end

			-- Match files that start with .cache_source_ and end with .json
			if (ftype == "file" or ftype == nil) and name:match("^%.cache_source_.*%.json$") then
				local full_path = db_path .. "/" .. name
				if vim.fn.delete(full_path) == 0 then
					count = count + 1
				end
			end
		end
	end

	if count > 0 then
		vim.notify(
			string.format("[totd] Cleared %d disk cache file(s). Next search will fetch fresh data.", count),
			vim.log.levels.INFO
		)
	else
		vim.notify("[totd] Cache is already empty.", vim.log.levels.INFO)
	end
end

return M
