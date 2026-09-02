-- Minimal FiveM/GTA runtime stub so the client script can be executed and
-- driven frame by frame in plain Lua. Only what esx_pushvehicle touches is
-- implemented; everything records what the script asked the game to do so
-- tests can assert on it.

local mock = {}

-- ── vector3 ────────────────────────────────────────────────────────────
local vec_mt = {}
vec_mt.__index = vec_mt
vec_mt.__sub = function(a, b) return vector3(a.x - b.x, a.y - b.y, a.z - b.z) end
vec_mt.__unm = function(a) return vector3(-a.x, -a.y, -a.z) end
vec_mt.__len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end
vec_mt.__tostring = function(a) return ('(%.3f, %.3f, %.3f)'):format(a.x, a.y, a.z) end

function vector3(x, y, z)
    return setmetatable({ x = x, y = y, z = z }, vec_mt)
end

-- ── Scheduler ──────────────────────────────────────────────────────────
mock.time = 0
local threads = {}

function CreateThread(fn)
    threads[#threads + 1] = { co = coroutine.create(fn), wake = mock.time }
end

function Wait(ms)
    coroutine.yield(ms or 0)
end

function GetGameTimer()
    return mock.time
end

-- Advances one frame: clears per-frame control disables, then resumes every
-- thread whose wait has elapsed.
function mock.tick(dt)
    mock.time = mock.time + (dt or 16)
    mock.disabled = {}
    mock.helpText = nil -- help text must be re-issued every frame to stay up

    local i = 1
    while i <= #threads do
        local t = threads[i]
        if coroutine.status(t.co) == 'dead' then
            table.remove(threads, i)
        elseif mock.time >= t.wake then
            local ok, ms = coroutine.resume(t.co)
            if not ok then error(ms, 0) end
            if coroutine.status(t.co) == 'dead' then
                table.remove(threads, i)
            else
                t.wake = mock.time + (tonumber(ms) or 0)
                i = i + 1
            end
        else
            i = i + 1
        end
    end
end

function mock.ticks(n, dt)
    for _ = 1, (n or 1) do mock.tick(dt) end
end

-- ── World ──────────────────────────────────────────────────────────────
mock.entities = {}
local nextHandle = 1

local function newEntity(t)
    t.handle = nextHandle
    nextHandle = nextHandle + 1
    t.x = t.x or 0.0
    t.y = t.y or 0.0
    t.z = t.z or 0.0
    t.heading = t.heading or 0.0
    t.velocity = t.velocity or { x = 0.0, y = 0.0, z = 0.0 }
    t.exists = (t.exists ~= false)
    mock.entities[t.handle] = t
    return t
end

function mock.reset()
    mock.time = 0
    threads = {}
    mock.entities = {}
    nextHandle = 1
    mock.keys = {}
    mock.disabled = {}
    mock.commands = {}
    mock.eventHandlers = {}
    mock.helpText = nil
    mock.notifications = {}
    mock.animDictExists = true
    mock.animDictLoads = true
    mock.hasNetworkControl = true
    mock.log = { forces = {}, steering = {}, handbrake = {}, attach = {}, detach = 0, anims = {}, animSpeed = {} }

    mock.ped = newEntity { kind = 'ped', x = 0.0, y = 0.0, z = 0.0 }
    return mock.ped
end

-- Creates a vehicle. `length`/`width` are the model bounding box size.
function mock.addVehicle(opts)
    opts = opts or {}
    local length = opts.length or 4.4
    local width  = opts.width or 1.9
    return newEntity {
        kind = 'vehicle',
        x = opts.x or 0.0, y = opts.y or 0.0, z = opts.z or 0.0,
        heading = opts.heading or 0.0,
        class = opts.class or 0,
        driver = opts.driver or nil,
        dead = opts.dead or false,
        attached = opts.attached or false,
        handbrake = true,
        steering = 0.0,
        dims = {
            min = vector3(-width / 2, -length / 2, -0.7),
            max = vector3(width / 2, length / 2, 0.8),
        },
        velocity = opts.velocity or { x = 0.0, y = 0.0, z = 0.0 },
    }
end

-- Places the ped `distance` meters off the given end of the vehicle,
-- respecting the vehicle's heading. side: 'rear' or 'front'.
function mock.placePedAtBumper(vehicle, side, distance, lateral)
    local halfLength = (vehicle.dims.max.y - vehicle.dims.min.y) / 2
    local localY = (halfLength + (distance or 0.5)) * (side == 'front' and 1 or -1)
    local localX = lateral or 0.0
    local h = math.rad(vehicle.heading)
    -- local -> world rotation
    mock.ped.x = vehicle.x + (localX * math.cos(h) - localY * math.sin(h))
    mock.ped.y = vehicle.y + (localX * math.sin(h) + localY * math.cos(h))
    mock.ped.z = vehicle.z
end

function mock.press(control) mock.keys[control] = true end
function mock.release(control) mock.keys[control] = nil end
function mock.releaseAll() mock.keys = {} end

-- Runs a registered command the way FiveM does: inside a thread.
function mock.runCommand(name)
    local handler = mock.commands[name]
    assert(handler, 'command not registered: ' .. name)
    CreateThread(function() handler(0, {}, name) end)
    mock.tick()
end

function mock.fireEvent(name, ...)
    for _, fn in ipairs(mock.eventHandlers[name] or {}) do fn(...) end
end

-- ── Natives ────────────────────────────────────────────────────────────
local function ent(handle) return mock.entities[handle] end

function PlayerPedId() return mock.ped.handle end
function GetCurrentResourceName() return 'esx_pushvehicle' end

function DoesEntityExist(h) return ent(h) ~= nil and ent(h).exists end
function IsEntityDead(h) return ent(h) ~= nil and ent(h).dead == true end
function IsEntityAttached(h) return ent(h) ~= nil and ent(h).attached == true end
function IsEntityAttachedToEntity(a, b)
    local e = ent(a)
    return e ~= nil and e.attachedTo == b
end

function GetEntityCoords(h)
    local e = ent(h)
    return vector3(e.x, e.y, e.z)
end

function GetEntityModel(h) return h end

function GetModelDimensions(h)
    local e = ent(h)
    return e.dims.min, e.dims.max
end

-- GTA convention: heading 0 faces +Y, and the forward vector is
-- (-sin h, cos h, 0).
function GetEntityForwardVector(h)
    local rad = math.rad(ent(h).heading)
    return vector3(-math.sin(rad), math.cos(rad), 0.0)
end

function GetOffsetFromEntityGivenWorldCoords(h, wx, wy, wz)
    local e = ent(h)
    local dx, dy = wx - e.x, wy - e.y
    local rad = math.rad(e.heading)
    local lx = dx * math.cos(rad) + dy * math.sin(rad)
    local ly = -dx * math.sin(rad) + dy * math.cos(rad)
    return vector3(lx, ly, wz - e.z)
end

function GetEntityVelocity(h)
    local v = ent(h).velocity
    return vector3(v.x, v.y, v.z)
end

function SetEntityVelocity(h, x, y, z)
    ent(h).velocity = { x = x, y = y, z = z }
end

function GetEntitySpeed(h)
    local v = ent(h).velocity
    return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
end

function GetGamePool(kind)
    local out = {}
    if kind == 'CVehicle' then
        for handle, e in pairs(mock.entities) do
            if e.kind == 'vehicle' then out[#out + 1] = handle end
        end
        table.sort(out)
    end
    return out
end

function GetVehicleClass(h) return ent(h).class end
function IsVehicleSeatFree(h, seat) return ent(h).driver == nil and seat == -1 end

function SetVehicleSteeringAngle(h, angle)
    ent(h).steering = angle
    mock.log.steering[#mock.log.steering + 1] = angle
end

function SetVehicleHandbrake(h, toggle)
    ent(h).handbrake = toggle
    mock.log.handbrake[#mock.log.handbrake + 1] = toggle
end

function ApplyForceToEntity(h, forceType, x, y, z, ...)
    mock.log.forces[#mock.log.forces + 1] = { entity = h, forceType = forceType, x = x, y = y, z = z }
end

function AttachEntityToEntity(e1, e2, bone, x, y, z, rx, ry, rz, ...)
    ent(e1).attachedTo = e2
    mock.log.attach[#mock.log.attach + 1] = { entity = e1, target = e2, x = x, y = y, z = z, heading = rz }
end

function DetachEntity(h)
    ent(h).attachedTo = nil
    mock.log.detach = mock.log.detach + 1
end

function DoesAnimDictExist() return mock.animDictExists end
function RequestAnimDict() end
function HasAnimDictLoaded() return mock.animDictLoads end

function TaskPlayAnim(ped, dict, name, ...)
    mock.log.anims[#mock.log.anims + 1] = { dict = dict, name = name }
end

function StopAnimTask() end
function ClearPedTasks() end

function SetEntityAnimSpeed(ped, dict, name, speed)
    mock.log.animSpeed[#mock.log.animSpeed + 1] = speed
end

function IsPedInAnyVehicle() return mock.ped.inVehicle == true end
function IsPedRagdoll() return mock.ped.ragdoll == true end
function IsPedDeadOrDying() return mock.ped.dead == true end

function NetworkHasControlOfEntity() return mock.hasNetworkControl end
function NetworkRequestControlOfEntity() end

function DisableControlAction(_, control) mock.disabled[control] = true end
function IsControlPressed(_, control)
    return mock.keys[control] == true and not mock.disabled[control]
end
function IsDisabledControlPressed(_, control) return mock.keys[control] == true end

function AddTextEntry(_, text) mock.pendingHelp = text end
function BeginTextCommandDisplayHelp() end
function EndTextCommandDisplayHelp() mock.helpText = mock.pendingHelp end

function BeginTextCommandThefeedPost() end
function AddTextComponentSubstringPlayerName(msg) mock.pendingNotification = msg end
function EndTextCommandThefeedPostTicker()
    mock.notifications[#mock.notifications + 1] = mock.pendingNotification
end

function RegisterCommand(name, handler) mock.commands[name] = handler end
function RegisterKeyMapping(command, description, mapper, key)
    mock.keyMapping = { command = command, description = description, mapper = mapper, key = key }
end

function AddEventHandler(name, fn)
    mock.eventHandlers[name] = mock.eventHandlers[name] or {}
    table.insert(mock.eventHandlers[name], fn)
end

function TriggerEvent() end

return mock
