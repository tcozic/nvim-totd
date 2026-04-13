-- lua/totd/progress.lua
--- Handles learning progress, state persistence, and the random weighting algorithm.
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

--- Increment the view count
--- @param filename string
function M.track_view(filename)
	local state = M.load()
	state[filename] = (state[filename] or 0) + 1
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

--- Calculates the probability weight for a tip (Pure 1:1 migration).
--- @param tip_data table The parsed tip object
--- @param context_ft string|nil The current buffer's filetype
--- @param state table The loaded state database
--- @return number weight
function M.calculate_weight(tip_data, context_ft, state)
	local filename = vim.fn.fnamemodify(tip_data.path, ":t")
	
	if state["suspend:" .. filename] then
		return 0 
	end

	local views = state[filename] or 0
	local weight = 100 / (views + 1)

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
