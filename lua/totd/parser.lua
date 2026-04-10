--- lua/totd/parser.lua
--- Responsible for reading and parsing tip Markdown files.
local M = {}

--- Extract YAML frontmatter, body, and sandbox from raw file content.
--- @param content string Raw file content
--- @return table|nil frontmatter, string|nil body, string|nil sandbox, string|nil lang
function M.parse(content)
	if not content or content == "" then
		return nil, nil, nil
	end

	local yaml_block, body = content:match("^%-%-%-\n(.-)\n%-%-%-\n?(.*)")
	if not yaml_block then
		return nil, content, nil
	end

	local frontmatter = M._parse_yaml(yaml_block)

  -- Extract the sandbox for "Practice Mode"
	local sandbox = nil
	-- FIX: Replace (.-) with ([^\0]-) to guarantee newline capturing
  local lang, code = body:match("```(%w*)\n(.-)\n```%s*$")
	if code then
		sandbox = vim.trim(code)
	else
		-- Fallback for older files: grab everything after "## Test it"
		local test_block = body:match("## Test it\n(.*)$")
		sandbox = test_block and vim.trim(test_block) or ""
	end

	return frontmatter, body, sandbox, lang
end

--- A more robust YAML parser that handles scalar and array fields.
--- @param yaml string Raw YAML block content
--- @return table
function M._parse_yaml(yaml)
	local result = {}
	local current_key = nil

	for line in (yaml .. "\n"):gmatch("([^\n]*)\n") do
		-- Skip empty lines and comments
		if line:match("^%s*$") or line:match("^%s*#") then
		-- nothing

		-- Array item: "  - value"
		elseif line:match("^%s+%-%s+(.+)$") then
			local item = line:match("^%s+%-%s+(.+)$")
			if current_key and type(result[current_key]) == "table" then
				table.insert(result[current_key], item)
			end

		-- Key with no inline value → next lines are array items
		elseif line:match("^(%w[%w_]-):%s*$") then
			current_key = line:match("^(%w[%w_]-):%s*$")
			result[current_key] = {}

		-- Key with inline value → scalar
		elseif line:match("^(%w[%w_]-):%s+(.+)$") then
			local k, v = line:match("^(%w[%w_]-):%s+(.+)$")
			-- Strip surrounding quotes if present
			v = v:gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")
			result[k] = v
			current_key = k
		end
	end

	return result
end

--- Fallback: ordered list of known array keys for the legacy parser path.
function M._array_keys()
	return { "tags", "related" }
end

--- Read a file from disk and return its content.
--- @param path string Absolute file path
--- @return string|nil content, string|nil err
function M.read_file(path)
	local f = io.open(path, "r")
	if not f then
		return nil, "Cannot open file: " .. path
	end
	local content = f:read("*a")
	f:close()
	return content, nil
end

return M
