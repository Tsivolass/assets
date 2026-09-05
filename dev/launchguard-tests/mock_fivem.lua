-- FiveM runtime stub: enough of the client/server API for esx_launchguard
-- to be executed and driven frame by frame outside the game.

local mock = {}
mock.consoleLog = {}

-- ── vector3 ────────────────────────────────────────────────────────────
local vec_mt = {}
vec_mt.__index = vec_mt
vec_mt.__sub = function(a, b) return vector3(a.x - b.x, a.y - b.y, a.z - b.z) end
vec_mt.__len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end

function vector3(x, y, z)
    return setmetatable({ x = x, y = y, z = z }, vec_mt)
end

-- ── Scheduler ──────────────────────────────────────────────────────────
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

-- ── World ──────────────────────────────────────────────────────────────
function mock.reset()
    mock.time = 0
    mock.frameTime = 1 / 60
    threads = {}

    mock.ped = {
        handle = 1,
        pos = { x = 0.0, y = 0.0, z = 30.0 },
        vel = { x = 0.0, y = 0.0, z = 0.0 },
        dead = false, inVehicle = false, inAir = false, swimming = false,
        inPlane = false, inHeli = false,
        climbing = false, vaulting = false, freeFall = false, parachute = -1,
        ragdoll = false, attachedTo = nil, networked = true, netId = 77,
    }

    mock.switchActive = false
    mock.exports = {}
    mock.events = {}
    mock.netEvents = {}
    mock.serverEvents = {}   -- what the client sent to the server
    mock.clientEvents = {}   -- what the server sent to clients
    mock.notifications = {}
    mock.httpPosts = {}
    mock.commands = {}
    mock.acePerms = {}
    mock.players = {}        -- server side: id -> {name, ped, coords}
    mock.log = { velocitySets = {}, coordSets = {}, detaches = 0,
                 clearTasks = 0, migrateLocks = {} }
end

-- Places the ped and its velocity for the next sampled frame.
function mock.setMotion(pos, vel)
    if pos then mock.ped.pos = pos end
    if vel then mock.ped.vel = vel end
end

function mock.lastVelocitySet() return mock.log.velocitySets[#mock.log.velocitySets] end
function mock.lastCoordSet() return mock.log.coordSets[#mock.log.coordSets] end
function mock.lastServerEvent()
    return mock.serverEvents[#mock.serverEvents]
end

-- ── Shared natives ─────────────────────────────────────────────────────
function PlayerPedId() return mock.ped.handle end
function GetCurrentResourceName() return 'esx_launchguard' end

-- Client: the local ped. Server: any player's ped handle.
function GetEntityCoords(entity)
    if entity == nil or entity == mock.ped.handle then
        local p = mock.ped.pos
        return vector3(p.x, p.y, p.z)
    end
    for _, pl in pairs(mock.players) do
        if pl.ped == entity then
            return vector3(pl.coords.x, pl.coords.y, pl.coords.z)
        end
    end
    return vector3(0.0, 0.0, 0.0)
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

-- Server side: fire an event as if a specific client sent it, setting the
-- implicit `source` the handler reads.
function mock.triggerFromClient(name, src, payload)
    source = src
    for _, fn in ipairs(mock.events[name] or {}) do fn(payload) end
    source = nil
end

-- Minimal json.encode, enough for the webhook body.
json = {
    encode = function(v)
        local function enc(x)
            local tx = type(x)
            if tx == 'nil' then return 'null'
            elseif tx == 'boolean' then return tostring(x)
            elseif tx == 'number' then return tostring(x)
            elseif tx == 'string' then return '"' .. x:gsub('["\\]', '\\%0') .. '"'
            elseif tx == 'table' then
                if #x > 0 then
                    local parts = {}
                    for _, item in ipairs(x) do parts[#parts + 1] = enc(item) end
                    return '[' .. table.concat(parts, ',') .. ']'
                end
                local parts = {}
                for k, item in pairs(x) do
                    parts[#parts + 1] = '"' .. tostring(k) .. '":' .. enc(item)
                end
                return '{' .. table.concat(parts, ',') .. '}'
            end
            return 'null'
        end
        return enc(v)
    end,
}

function TriggerServerEvent(name, payload)
    mock.serverEvents[#mock.serverEvents + 1] = { name = name, payload = payload }
end

function TriggerClientEvent(name, target, payload)
    mock.clientEvents[#mock.clientEvents + 1] = { name = name, target = target, payload = payload }
end

exports = setmetatable({}, {
    __call = function(_, name, fn) mock.exports[name] = fn end,
    __index = function(_, _resource)
        return setmetatable({}, {
            __index = function(_, name)
                return function(_, ...) return mock.exports[name](...) end
            end,
        })
    end,
})

-- ── Server-only natives ────────────────────────────────────────────────
function GetPlayerName(id) return (mock.players[id] or {}).name end
function GetPlayerPed(id) return (mock.players[id] or {}).ped or 0 end
function GetPlayers()
    local out = {}
    for id in pairs(mock.players) do out[#out + 1] = tostring(id) end
    table.sort(out)
    return out
end

function IsPlayerAceAllowed(id, perm)
    local p = mock.acePerms[tonumber(id)] or mock.acePerms[tostring(id)]
    return p == perm or p == 'all'
end

function RegisterCommand(name, handler) mock.commands[name] = handler end

function PerformHttpRequest(url, cb, method, body, headers)
    mock.httpPosts[#mock.httpPosts + 1] = { url = url, method = method, body = body, headers = headers }
    if cb then cb(200, '', {}) end
end

function GetPlayerIdentifiers(id)
    return (mock.players[id] or {}).identifiers or {}
end

-- print() still reaches the terminal, and is also recorded so resource
-- console output can be asserted on. Snapshot #mock.consoleLog before an
-- action and inspect the entries added after it.
local realPrint = print
function print(...)
    local parts = {}
    for i = 1, select('#', ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    mock.consoleLog[#mock.consoleLog + 1] = table.concat(parts, ' ')
    realPrint(...)
end

return mock
