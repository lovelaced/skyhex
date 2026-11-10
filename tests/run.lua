-- tests/run.lua
-- Plain LuaJIT spec runner for the Skyhex engine. Run from the repo root:
--   luajit tests/run.lua [pattern]
-- Each spec file gets a fresh engine namespace loaded in TOC order.

package.path = "tests/?.lua;" .. package.path

local pattern = arg[1]
local TOC = "Skyhex/Skyhex.toc"

local function loadEngine()
  local ns = {}
  for line in io.lines(TOC) do
    local path = line:match("^(Engine[\\/][%w_]+%.lua)")
    if path then
      local chunk = assert(loadfile("Skyhex/" .. path:gsub("\\", "/")))
      chunk("Skyhex", ns)
    end
  end
  return ns
end

local results = { pass = 0, fail = 0, failures = {} }
local stack = {}

local T = {}
function T.describe(name, fn)
  stack[#stack + 1] = name
  fn()
  stack[#stack] = nil
end

function T.it(name, fn)
  local full = table.concat(stack, " > ") .. " > " .. name
  local ok, err = xpcall(fn, debug.traceback)
  if ok then
    results.pass = results.pass + 1
  else
    results.fail = results.fail + 1
    results.failures[#results.failures + 1] = full .. "\n    " .. tostring(err):gsub("\n", "\n    ")
  end
end

local function show(v)
  if type(v) == "string" then return string.format("%q", v) end
  return tostring(v)
end

function T.eq(actual, expected, msg)
  if actual ~= expected then
    error((msg and (msg .. ": ") or "") .. "expected " .. show(expected) .. ", got " .. show(actual), 2)
  end
end

function T.ok(cond, msg)
  if not cond then error(msg or "expected a true value", 2) end
end

local specs = {}
for f in io.popen("ls tests/spec/*_spec.lua"):lines() do
  if not pattern or f:find(pattern, 1, true) then specs[#specs + 1] = f end
end

local t0 = os.clock()
for _, file in ipairs(specs) do
  local ns = loadEngine()
  local chunk = assert(loadfile(file))
  local H = dofile("tests/helpers.lua")(ns, T)
  chunk(ns, T, H)
end

for _, f in ipairs(results.failures) do print("FAIL " .. f) end
print(string.format("%d passed, %d failed (%d spec files, %.2fs)", results.pass, results.fail, #specs, os.clock() - t0))
os.exit(results.fail == 0 and 0 or 1)
