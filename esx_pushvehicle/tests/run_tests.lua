-- Behavioural tests for esx_pushvehicle.
--
-- Loads config.lua and client/main.lua into a stubbed FiveM runtime
-- (tests/mock_fivem.lua) and drives them frame by frame with simulated key
-- presses, asserting on what the script asks the game to do.
--
-- Run from the resource root:  lua5.4 tests/run_tests.lua

local root = (arg[0]:match('^(.*)/tests/[^/]+$')) or '.'
local mock = dofile(root .. '/tests/mock_fivem.lua')

local SPRINT, W, A, D = 21, 32, 34, 35

local passed, failed = 0, 0

local function check(label, ok, detail)
    if ok then
        passed = passed + 1
        print(('  ok   %s'):format(label))
    else
        failed = failed + 1
        print(('  FAIL %s%s'):format(label, detail and ('  -> ' .. tostring(detail)) or ''))
    end
end

local function near(a, b, tol)
    return math.abs(a - b) <= (tol or 0.0001)
end

-- Loads a fresh copy of the resource into a fresh world.
local function loadResource()
    mock.reset()
    dofile(root .. '/config.lua')
    dofile(root .. '/client/main.lua')
    mock.ticks(3) -- let the detection loop spin up
end

-- The detection loop idles at 750ms between scans, so world changes need
-- more than that much virtual time before the script can have noticed them.
local function settle()
    mock.ticks(55)
end

local function lastForce()
    return mock.log.forces[#mock.log.forces]
end

local function startPush()
    mock.press(SPRINT)
    mock.runCommand('+esx_pushvehicle')
    mock.release(SPRINT)
    mock.ticks(2)
end

-- ── Detection ──────────────────────────────────────────────────────────
print('\ndetection')

do
    loadResource()
    mock.addVehicle { x = 0.0, y = 0.0 }
    mock.ped.x, mock.ped.y = 25.0, 25.0 -- far away
    settle()
    check('no prompt when far from any vehicle', mock.helpText == nil, mock.helpText)
end

do
    loadResource()
    local veh = mock.addVehicle {}
    mock.placePedAtBumper(veh, 'rear', 0.5)
    settle()
    check('prompt shown standing at the rear bumper', mock.helpText == Config.HelpText, mock.helpText)
end

do
    loadResource()
    local veh = mock.addVehicle {}
    mock.placePedAtBumper(veh, 'front', 0.5)
    settle()
    check('prompt shown standing at the front bumper', mock.helpText == Config.HelpText, mock.helpText)
end

do
    loadResource()
    local veh = mock.addVehicle {}
    -- Alongside the driver door, not at either bumper.
    mock.ped.x, mock.ped.y = veh.x + 1.4, veh.y
    settle()
    check('no prompt standing at the side of the vehicle', mock.helpText == nil, mock.helpText)
end

do
    loadResource()
    local veh = mock.addVehicle {}
    mock.placePedAtBumper(veh, 'rear', 0.5, 1.6) -- offset well past the corner
    settle()
    check('no prompt standing off the rear corner', mock.helpText == nil, mock.helpText)
end

do
    loadResource()
    local veh = mock.addVehicle { class = 14 } -- boat
    mock.placePedAtBumper(veh, 'rear', 0.5)
    settle()
    check('boats are never pushable', mock.helpText == nil, mock.helpText)
end

do
    loadResource()
    local veh = mock.addVehicle { class = 8 } -- motorcycle
    mock.placePedAtBumper(veh, 'rear', 0.5)
    settle()
    check('motorcycles are pushable', mock.helpText == Config.HelpText, mock.helpText)
end

do
    loadResource()
    local veh = mock.addVehicle { driver = 99 }
    mock.placePedAtBumper(veh, 'rear', 0.5)
    settle()
    check('occupied vehicle shows no prompt', mock.helpText == nil, mock.helpText)
end

do
    loadResource()
    local veh = mock.addVehicle { velocity = { x = 0.0, y = 3.0, z = 0.0 } }
    mock.placePedAtBumper(veh, 'rear', 0.5)
    settle()
    check('moving vehicle shows no prompt', mock.helpText == nil, mock.helpText)
end

-- ── Starting a push ────────────────────────────────────────────────────
print('\nstarting a push')

do
    loadResource()
    local veh = mock.addVehicle {}
    mock.placePedAtBumper(veh, 'rear', 0.5)
    settle()
    mock.runCommand('+esx_pushvehicle') -- F without Shift
    mock.ticks(2)
    check('F alone does not start a push', mock.ped.attachedTo == nil)
end

do
    loadResource()
    mock.addVehicle {}
    mock.ped.x, mock.ped.y = 25.0, 25.0
    settle()
    startPush()
    check('Shift+F away from a vehicle does nothing', mock.ped.attachedTo == nil)
end

do
    loadResource()
    local veh = mock.addVehicle {}
    mock.placePedAtBumper(veh, 'rear', 0.5)
    settle()
    startPush()
    check('Shift+F attaches the ped to the vehicle', mock.ped.attachedTo == veh.handle)
    check('push animation is played', #mock.log.anims == 1 and mock.log.anims[1].name == Config.Anim.name)
    check('in-push prompt replaces the start prompt', mock.helpText == Config.HelpTextPushing, mock.helpText)

    local attach = mock.log.attach[1]
    check('ped attaches behind the rear bumper', attach.y < 0, attach.y)
    check('ped faces the same way as the vehicle', near(attach.heading, 0.0), attach.heading)
end

do
    loadResource()
    local veh = mock.addVehicle {}
    mock.placePedAtBumper(veh, 'front', 0.5)
    settle()
    startPush()
    local attach = mock.log.attach[1]
    check('ped attaches ahead of the front bumper', attach.y > 0, attach.y)
    check('ped faces the vehicle when pushing from the front', near(attach.heading, 180.0), attach.heading)
end

do
    loadResource()
    mock.animDictExists = false -- animation unavailable on this build
    local veh = mock.addVehicle {}
    mock.placePedAtBumper(veh, 'rear', 0.5)
    settle()
    startPush()
    mock.press(W)
    mock.ticks(2)
    check('push still works when the animation cannot load',
        mock.ped.attachedTo == veh.handle and #mock.log.anims == 0 and lastForce() ~= nil)
    mock.release(W)
end

do
    loadResource()
    mock.hasNetworkControl = false
    local veh = mock.addVehicle {}
    mock.placePedAtBumper(veh, 'rear', 0.5)
    settle()
    mock.press(SPRINT)
    mock.runCommand('+esx_pushvehicle')
    mock.ticks(80) -- past the 1s control timeout
    check('gives up cleanly without network control',
        mock.ped.attachedTo == nil and #mock.notifications == 1, mock.notifications[1])
    mock.release(SPRINT)
end

-- ── Direction control ──────────────────────────────────────────────────
print('\ndirection control (W / A / D)')

do
    loadResource()
    local veh = mock.addVehicle {}
    mock.placePedAtBumper(veh, 'rear', 0.5)
    settle()
    startPush()

    local before = #mock.log.forces
    mock.ticks(5) -- no keys held
    check('no force is applied while no direction key is held', #mock.log.forces == before)
    check('vehicle is handbraked while idle', veh.handbrake == true)

    veh.velocity = { x = 1.0, y = 1.0, z = -0.5 }
    mock.ticks(1)
    local v = veh.velocity
    check('idle push damps horizontal velocity',
        near(v.x, 1.0 * Config.StationaryDamping) and near(v.y, 1.0 * Config.StationaryDamping),
        ('%.3f, %.3f'):format(v.x, v.y))
    check('idle push leaves vertical velocity alone (gravity still applies)', near(v.z, -0.5), v.z)

    mock.ticks(12) -- keep damping
    check('vehicle ends up fully stationary',
        near(veh.velocity.x, 0.0) and near(veh.velocity.y, 0.0),
        ('%.4f, %.4f'):format(veh.velocity.x, veh.velocity.y))
end

do
    loadResource()
    local veh = mock.addVehicle { heading = 0.0 } -- facing +Y
    mock.placePedAtBumper(veh, 'rear', 0.5)
    settle()
    startPush()
    mock.press(W)
    mock.ticks(2)
    local f = lastForce()
    check('W pushes a rear-pushed vehicle toward its nose',
        f ~= nil and near(f.x, 0.0) and f.y > 0, f and ('%.3f, %.3f'):format(f.x, f.y))
    check('handbrake released while pushing', veh.handbrake == false)
    check('animation runs at full speed while pushing',
        mock.log.animSpeed[#mock.log.animSpeed] == 1.0)
    mock.release(W)
end

do
    loadResource()
    local veh = mock.addVehicle { heading = 90.0 } -- facing -X
    mock.placePedAtBumper(veh, 'rear', 0.5)
    settle()
    startPush()
    mock.press(W)
    mock.ticks(2)
    local f = lastForce()
    check('push direction follows vehicle heading (90 deg)',
        f ~= nil and near(f.x, -Config.PushForce, 0.001) and near(f.y, 0.0, 0.001),
        f and ('%.3f, %.3f'):format(f.x, f.y))
    mock.release(W)
end

do
    loadResource()
    local veh = mock.addVehicle { heading = 0.0 }
    mock.placePedAtBumper(veh, 'front', 0.5)
    settle()
    startPush()
    mock.press(W)
    mock.ticks(2)
    local f = lastForce()
    check('W pushes a front-pushed vehicle toward its trunk',
        f ~= nil and f.y < 0, f and ('%.3f, %.3f'):format(f.x, f.y))
    mock.release(W)
end

do
    loadResource()
    local veh = mock.addVehicle {}
    mock.placePedAtBumper(veh, 'rear', 0.5)
    settle()
    startPush()

    mock.press(A)
    mock.ticks(2)
    check('A steers left', near(veh.steering, Config.SteerAngle), veh.steering)
    check('A also pushes the vehicle', lastForce() ~= nil)
    mock.release(A)

    mock.press(D)
    mock.ticks(2)
    check('D steers right', near(veh.steering, -Config.SteerAngle), veh.steering)
    mock.release(D)

    mock.ticks(2)
    check('steering returns to centre when released', near(veh.steering, 0.0), veh.steering)

    mock.press(A)
    mock.press(D)
    mock.ticks(2)
    check('A and D together cancel out', near(veh.steering, 0.0), veh.steering)
    mock.releaseAll()
end

do
    loadResource()
    local veh = mock.addVehicle {}
    mock.placePedAtBumper(veh, 'front', 0.5)
    settle()
    startPush()
    mock.press(A)
    mock.ticks(2)
    check('steering is mirrored when pushing from the front',
        near(veh.steering, -Config.SteerAngle), veh.steering)
    mock.releaseAll()
end

do
    loadResource()
    local veh = mock.addVehicle {}
    mock.placePedAtBumper(veh, 'rear', 0.5)
    settle()
    startPush()
    veh.velocity = { x = 0.0, y = Config.MaxPushSpeed - 0.05, z = 0.0 }
    mock.press(W)
    local before = #mock.log.forces
    mock.ticks(1)
    check('force still applied just below the speed cap', #mock.log.forces > before)

    veh.velocity = { x = 0.0, y = Config.MaxPushSpeed + 0.05, z = 0.0 }
    before = #mock.log.forces
    mock.ticks(1)
    check('force stops at the speed cap', #mock.log.forces == before)
    mock.releaseAll()
end

-- ── Ending a push ──────────────────────────────────────────────────────
print('\nending a push')

do
    loadResource()
    local veh = mock.addVehicle {}
    mock.placePedAtBumper(veh, 'rear', 0.5)
    settle()
    startPush()
    mock.press(W)
    mock.press(A) -- stop mid-turn, so centring the wheels is observable
    mock.ticks(2)
    assert(not near(veh.steering, 0.0), 'setup: expected the wheels to be turned')

    mock.runCommand('+esx_pushvehicle') -- F again, no Shift needed
    mock.ticks(2)
    check('pressing F again detaches the ped', mock.ped.attachedTo == nil)
    check('steering is centred on release', near(veh.steering, 0.0), veh.steering)
    check('vehicle is left handbraked', veh.handbrake == true)

    local before = #mock.log.forces
    mock.ticks(5)
    check('no force after the push ends even with W held', #mock.log.forces == before)
    mock.releaseAll()
end

do
    loadResource()
    local veh = mock.addVehicle {}
    mock.placePedAtBumper(veh, 'rear', 0.5)
    settle()
    startPush()
    veh.driver = 42 -- someone jumps in
    mock.ticks(2)
    check('push stops when a driver gets in', mock.ped.attachedTo == nil)
    check('player is told why', mock.notifications[1] == Config.Locales.occupied, mock.notifications[1])
end

do
    loadResource()
    local veh = mock.addVehicle {}
    mock.placePedAtBumper(veh, 'rear', 0.5)
    settle()
    startPush()
    veh.exists = false -- vehicle deleted underneath the player
    mock.ticks(2)
    check('push stops when the vehicle disappears', mock.ped.attachedTo == nil)
end

do
    loadResource()
    local veh = mock.addVehicle {}
    mock.placePedAtBumper(veh, 'rear', 0.5)
    settle()
    startPush()
    mock.ped.dead = true
    mock.ticks(2)
    check('push stops when the player dies', mock.ped.attachedTo == nil)
end

do
    loadResource()
    local veh = mock.addVehicle {}
    mock.placePedAtBumper(veh, 'rear', 0.5)
    settle()
    startPush()
    veh.velocity = { x = 0.0, y = Config.MaxPushSpeed + Config.RunawaySpeedMargin + 0.2, z = 0.0 }
    mock.ticks(2)
    check('push stops if the vehicle runs away', mock.ped.attachedTo == nil)
end

do
    loadResource()
    local veh = mock.addVehicle {}
    mock.placePedAtBumper(veh, 'rear', 0.5)
    settle()
    startPush()
    mock.fireEvent('onResourceStop', 'esx_pushvehicle')
    check('resource stop detaches the ped', mock.ped.attachedTo == nil)
end

do
    loadResource()
    local veh = mock.addVehicle {}
    mock.placePedAtBumper(veh, 'rear', 0.5)
    settle()
    startPush()
    mock.fireEvent('onResourceStop', 'some_other_resource')
    check('another resource stopping is ignored', mock.ped.attachedTo == veh.handle)
end

-- ── Key binding ────────────────────────────────────────────────────────
print('\nkey binding')

do
    loadResource()
    check('command is bound to F on the keyboard',
        mock.keyMapping and mock.keyMapping.key == 'F' and mock.keyMapping.mapper == 'keyboard',
        mock.keyMapping and mock.keyMapping.key)
    check('release half of the keybind is registered', mock.commands['-esx_pushvehicle'] ~= nil)
end

print(('\n%d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
