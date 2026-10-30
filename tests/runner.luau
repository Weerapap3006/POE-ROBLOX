--[[
   Master Test Runner
   Run all tests: lune run tests/runner.luau
]]

local fs = require("@lune/fs")
local process = require("@lune/process")

print("========================================")
print("🚀 RUNNING AUTOMATED UNIT TESTS (LUNE)")
print("========================================\n")

local files = fs.readDir("tests")
local totalFiles = 0
local failedSuites = 0

for _, file in ipairs(files) do
	if file:match("^test_.*%.luau$") then
		totalFiles += 1
		local path = "tests/" .. file
		local result = process.exec("lune", { "run", path })
		print(result.stdout)
		if not result.ok then
			print(result.stderr)
			failedSuites += 1
		end
	end
end

print("========================================")
if failedSuites > 0 then
	print(string.format("❌ SUMMARY: %d test suite(s) FAILED out of %d", failedSuites, totalFiles))
	process.exit(1)
else
	print(string.format("✨ SUMMARY: ALL %d test suite(s) PASSED!", totalFiles))
	process.exit(0)
end
