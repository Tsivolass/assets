-- FiveM runtime stub: enough of the client API for the resource to be
-- executed and driven frame by frame outside the game.
--
-- Natives the resource must never call (notifications, server events,
-- network ownership) are stubbed too, so tests can assert they stay unused.

local mock = {}

local vec_mt = {}
vec_mt.__index = vec_mt
vec_mt.__sub = function(a, b) return vector3(a.x - b.x, a.y - b.y, a.z - b.z) end
vec_mt.__len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end

function vector3(x, y, z)
    return setmetatable({ x = x, y = y, z = z }, vec_mt)
end

local threads = {}
mock.time = 0
mock.frameTime = 1 / 60

function CreateThread(fn)
    threads[#threads + 1] = { co = coroutine.create(fn), wake = mock.time }
end

function Wait(ms) coroutine.yield(ms or 0) end
function GetGameTimer() return math.floor(mock.time) end
function GetFrameTime() return mock.frameTime end

function mock.tick(dtMs)
    dtMs = dtMs or (mock.frameTime * 1000)
    mock.frameTime = dtMs / 1000
    mock.time = mock.time + dtMs

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

function mock.ticks(n, dtMs)
    for _ = 1, (n or 1) do mock.tick(dtMs) end
end

function mock.reset()
    mock.time = 0
    mock.frameTime = 1 / 60
    threads = {}

    mock.ped = {
        handle = 1,
        pos = { x = 0.0, y = 0.0, z = 30.0 },
        vel = { x = 0.0, y = 0.0, z = 0.0 },
        dead = false, inVehicle = false, inAir = false, swimming = false,
        inPlane = false, inHeli = false, climbing = false, vaulting = false,
        freeFall = false, parachute = -1, ragdoll = false, attachedTo = nil,
        networked = true, netId = 77,
    }

    mock.switchActive = false
    mock.exports = {}
    mock.events = {}
    mock.netEvents = {}
    mock.serverEvents = {}
    mock.notifications = {}
    mock.log = { velocitySets = {}, coordSets = {}, detaches = 0,
                 clearTasks = 0, migrateLocks = {} }
end

function mock.lastVelocitySet() return mock.log.velocitySets[#mock.log.velocitySets] end
function mock.lastCoordSet() return mock.log.coordSets[#mock.log.coordSets] end

function PlayerPedId() return mock.ped.handle end

function GetEntityCoords()
    local p = mock.ped.pos
    return vector3(p.x, p.y, p.z)
end

function GetEntityVelocity()
    local v = mock.ped.vel
    return vector3(v.x, v.y, v.z)
end

function SetEntityVelocity(_, x, y, z)
    mock.ped.vel = { x = x, y = y, z = z }
    mock.log.velocitySets[#mock.log.velocitySets + 1] = { x = x, y = y, z = z }
end

function SetEntityCoordsNoOffset(_, x, y, z)
    mock.ped.pos = { x = x, y = y, z = z }
    mock.log.coordSets[#mock.log.coordSets + 1] = { x = x, y = y, z = z }
end

function IsPedDeadOrDying() return mock.ped.dead end
function IsPedInAnyVehicle() return mock.ped.inVehicle end
function IsPedInAnyPlane() return mock.ped.inPlane end
function IsPedInAnyHeli() return mock.ped.inHeli end
function IsEntityInAir() return mock.ped.inAir end
function IsPedSwimming() return mock.ped.swimming end
function IsPedClimbing() return mock.ped.climbing end
function IsPedVaulting() return mock.ped.vaulting end
function IsPedInParachuteFreeFall() return mock.ped.freeFall end
function GetPedParachuteState() return mock.ped.parachute end
function IsPlayerSwitchInProgress() return mock.switchActive end
function IsPedRagdoll() return mock.ped.ragdoll end
function IsEntityAttached() return mock.ped.attachedTo ~= nil end

function DetachEntity()
    mock.ped.attachedTo = nil
    mock.log.detaches = mock.log.detaches + 1
end

function ClearPedTasksImmediately()
    mock.ped.ragdoll = false
    mock.log.clearTasks = mock.log.clearTasks + 1
end

function NetworkGetEntityIsNetworked() return mock.ped.networked end
function PedToNet() return mock.ped.netId end
function SetNetworkIdCanMigrate(netId, toggle)
    mock.log.migrateLocks[#mock.log.migrateLocks + 1] = { netId = netId, toggle = toggle }
end

function BeginTextCommandThefeedPost() end
function AddTextComponentSubstringPlayerName(msg) mock.pendingNotification = msg end
function EndTextCommandThefeedPostTicker()
    mock.notifications[#mock.notifications + 1] = mock.pendingNotification
end

function TriggerEvent(name, ...)
    for _, fn in ipairs(mock.events[name] or {}) do fn(...) end
end

function AddEventHandler(name, fn)
    mock.events[name] = mock.events[name] or {}
    table.insert(mock.events[name], fn)
    return { name = name }
end

function RegisterNetEvent(name) mock.netEvents[name] = true end

function TriggerServerEvent(name, payload)
    mock.serverEvents[#mock.serverEvents + 1] = { name = name, payload = payload }
end

exports = setmetatable({}, {
    __call = function(_, name, fn) mock.exports[name] = fn end,
    __index = function()
        return setmetatable({}, {
            __index = function(_, name)
                return function(_, ...) return mock.exports[name](...) end
            end,
        })
    end,
})

return mock
