-- lua/totd/progress.lua
--- Handles learning progress, state persistence, and the SRS gravity pool algorithm.
local M = {}

local config = require("totd.config")
local uv = vim.uv or vim.loop

--- Get the path to the hidden state file
--- @return string path
local function get_state_file()
	return config.options.db_path .. "/.totd_state.json"
end

--- Load the state from disk
--- @return table
function M.load()
	local f = io.open(get_state_file(), "r")
	if not f then return {} end
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
	
	local json_str = table.remove(write_queue, 1)
	local filepath = get_state_file()

	uv.fs_open(filepath, "w", 438, function(err, fd)
		if err or not fd then
			vim.schedule(function()
				vim.notify("[totd] Failed to open state file: " .. (err or "unknown"), vim.log.levels.ERROR)
				is_writing = false
				process_queue()
			end)
			return
		end
		
		uv.fs_write(fd, json_str, -1, function(write_err)
			if write_err then
				vim.schedule(function()
					vim.notify("[totd] Failed to write state file: " .. write_err, vim.log.levels.ERROR)
				end)
			end
			
			uv.fs_close(fd, function()
				vim.schedule(function()
					is_writing = false
					process_queue()
				end)
			end)
		end)
	end)
end

--- Save the state to disk asynchronously
--- @param state table
function M.save(state)
	local ok, json_str = pcall(vim.fn.json_encode, state)
	if not ok then
		vim.notify("[totd] Failed to encode state JSON", vim.log.levels.ERROR)
		return
	end
	table.insert(write_queue, json_str)
	process_queue()
end

--- Ensures a tip exists in the state without advancing its schedule.
--- This replaces the old view counter.
--- @param filename string
function M.track_view(filename)
	local state = M.load()
	local record = state[filename]
	
	-- Initialize or migrate legacy integer view counts
	if type(record) ~= "table" then
		state[filename] = { interval = 1, ease = 2.0, next_due = os.time() }
		M.save(state)
	end
end

--- Process a user's validation score (1=Hard, 2=Good)
--- @param identifier string
--- @param score_val number 1 or 2
function M.score(identifier, score_val)
	local state = M.load()
	local filename = vim.fn.fnamemodify(identifier, ":t")
	local record = state[filename]

	-- Fallback if somehow missing
	if type(record) ~= "table" then
		record = { interval = 1, ease = 2.0, next_due = os.time() }
	end

	-- Fallbacks for partially migrated records
	record.interval = record.interval or 1
	record.ease = record.ease or 2.0
	
	local DAY_IN_SECONDS = 86400

	if score_val == 1 then
		-- Hard: Reset interval, penalize ease, due tomorrow
		record.interval = 1
		record.ease = math.max(1.3, record.ease - 0.2)
		record.next_due = os.time() + DAY_IN_SECONDS
		vim.notify(string.format("[totd] Score: Hard. See you tomorrow! (ease: %.1f)", record.ease), vim.log.levels.INFO)
	elseif score_val == 2 then
		-- Good: Push to future, increase interval, ease unchanged
		record.next_due = os.time() + (record.interval * DAY_IN_SECONDS)
		record.interval = record.interval * record.ease
		
		-- Convert the new interval to a human-readable string for the notification
		local days = math.floor(record.interval)
		vim.notify(string.format("[totd] Score: Good. See you in %d day(s).", days), vim.log.levels.INFO)
	end

	state[filename] = record
	M.save(state)
end

--- Check if a tip is currently suspended/masked
--- @param identifier string
--- @return boolean
function M.is_suspended(identifier)
	local state = M.load()
	local filename = vim.fn.fnamemodify(identifier, ":t")
	return state["suspend:" .. filename] == true
end

--- Toggle the suspend/mask state of a tip
--- @param identifier string
--- @return boolean is_now_suspended
function M.toggle_suspend(identifier)
	local state = M.load()
	local filename = vim.fn.fnamemodify(identifier, ":t")
	local sus_key = "suspend:" .. filename
	
	local is_now_suspended = not state[sus_key]
	
	if is_now_suspended then
		state[sus_key] = true
	else
		state[sus_key] = nil
	end
	
	M.save(state)
	return is_now_suspended
end

--- Calculates the probability weight based on the Gravity Pool algorithm.
--- @param tip_data table The parsed tip object
--- @param context_ft string|nil The current buffer's filetype
--- @param state table The loaded state database
--- @return number weight
function M.calculate_weight(tip_data, context_ft, state)
	local filename = vim.fn.fnamemodify(tip_data.path, ":t")
	
	-- 1. Suspended / Mastered Tips
	if state["suspend:" .. filename] then
		return 0 
	end

	local weight = 1
	local record = state[filename]

	-- 2. New vs Due vs Future Math
	if type(record) ~= "table" or not record.next_due then
		-- Brand New Tip
		weight = 50
	else
		local now = os.time()
		if now >= record.next_due then
			-- Due or Overdue: Base 50 + 10 weight per day overdue
			local days_overdue = math.max(0, os.difftime(now, record.next_due) / 86400)
			weight = 50 + (days_overdue * 10)
		else
			-- Future Tip: Not due yet
			weight = 1
		end
	end

	-- 3. Context Multiplier
	if context_ft then
		for _, tag in ipairs(tip_data.tags or {}) do
			if tag:lower() == context_ft:lower() then
				weight = weight * 50
				break
			end
		end
	end

	return weight
end

--- Resets all learning progress
function M.reset()
	M.save({})
end

return M
