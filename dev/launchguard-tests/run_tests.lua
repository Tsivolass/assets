-- Test runner for esx_launchguard.
--   lua5.4 dev/launchguard-tests/run_tests.lua [detector|client|server]

local here = arg[0]:match('^(.*)/[^/]+$') or '.'
local paths = {
    tests    = here,
    resource = here .. '/../../esx_launchguard',
}

local t = { passed = 0, failed = 0, failures = {} }

function t.group(name)
    print('\n' .. name)
end

function t.check(name, fn)
    local ok, err = pcall(fn)
    if ok then
        t.passed = t.passed + 1
        print(('  ok   %s'):format(name))
    else
        t.failed = t.failed + 1
        t.failures[#t.failures + 1] = name
        print(('  FAIL %s\n         %s'):format(name, tostring(err)))
    end
end

function t.assert(cond, msg)
    if not cond then error(msg or 'assertion failed', 2) end
end

function t.equal(got, want, msg)
    if got ~= want then
        error(('%sexpected %s, got %s'):format(msg and (msg .. ': ') or '',
            tostring(want), tostring(got)), 2)
    end
end

function t.near(got, want, tol, msg)
    tol = tol or 0.0001
    if math.abs(got - want) > tol then
        error(('%sexpected %s (+-%s), got %s'):format(msg and (msg .. ': ') or '',
            tostring(want), tostring(tol), tostring(got)), 2)
    end
end

local only = arg[1]
local suites = { 'detector', 'client', 'server' }

for _, name in ipairs(suites) do
    if not only or only == name then
        local path = ('%s/%s_spec.lua'):format(here, name)
        local f = io.open(path, 'r')
        if f then
            f:close()
            dofile(path)(t, paths)
        end
    end
end

print(('\n%d passed, %d failed'):format(t.passed, t.failed))
if t.failed > 0 then
    print('failing: ' .. table.concat(t.failures, ', '))
end
os.exit(t.failed == 0 and 0 or 1)
