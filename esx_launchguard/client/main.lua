-- Cancels cheat launches on the client of the player being launched.
--
-- A ped's position is authoritative on its owner's client, so however the
-- launch is delivered (forced entity control, an invisible explosion, a punt
-- object, a coord set) the result passes through this client's physics before
-- it becomes a position anyone else sees. Cancelling it here means the jump
-- never happens.

local suppressedUntil = 0
local lastPed = nil
local wasDead = false
local incidents = 0

local detector = LaunchDetector.new(Config, 0)

local function debugPrint(...)
    if Config.Debug then print(...) end
end

-- A few state natives are absent on older builds. Missing ones read as false
-- rather than erroring out mid frame.
local function optional(name)
    local fn = _G[name]
    if type(fn) == 'function' then return fn end
    debugPrint('state native unavailable, treated as false:', name)
    return function() return false end
end

local isClimbing     = optional('IsPedClimbing')
local isVaulting     = optional('IsPedVaulting')
local isSwimming     = optional('IsPedSwimming')
local isFreeFalling  = optional('IsPedInParachuteFreeFall')
local isSwitching    = optional('IsPlayerSwitchInProgress')
local parachuteState = optional('GetPedParachuteState')
local isInPlane      = optional('IsPedInAnyPlane')
local isInHeli       = optional('IsPedInAnyHeli')

-- Other resources call this around a legitimate teleport or scripted launch so
-- the guard stands down:  exports['esx_launchguard']:SuppressFor(1500)
local function suppressFor(ms)
    ms = tonumber(ms) or 0
    if ms <= 0 then return end

    local until_ = GetGameTimer() + math.min(ms, 30000)
    if until_ > suppressedUntil then
        suppressedUntil = until_
    end
end

exports('SuppressFor', suppressFor)
exports('IsSuppressed', function() return GetGameTimer() < suppressedUntil end)
exports('GetIncidentCount', function() return incidents end)

RegisterNetEvent('esx_launchguard:suppress')
AddEventHandler('esx_launchguard:suppress', suppressFor)

local function sampleFrame(ped, now)
    local pos = GetEntityCoords(ped)
    local vel = GetEntityVelocity(ped)

    return {
        now = now,
        dt  = GetFrameTime(),
        pos = { x = pos.x, y = pos.y, z = pos.z },
        vel = { x = vel.x, y = vel.y, z = vel.z },

        dead         = IsPedDeadOrDying(ped, true),
        inVehicle    = IsPedInAnyVehicle(ped, false),
        aircraft     = isInPlane(ped) or isInHeli(ped),
        grounded     = not IsEntityInAir(ped),
        swimming     = isSwimming(ped),
        climbing     = isClimbing(ped) or isVaulting(ped),
        parachuting  = isFreeFalling(ped) or (parachuteState(ped) or -1) > 0,
        switchActive = isSwitching(),
        suppressed   = now < suppressedUntil,
    }
end

local function applyCorrection(ped, action)
    -- Only the upward component is capped. Downward motion is left alone so
    -- gravity, falling and fall damage all behave normally.
    local vel = GetEntityVelocity(ped)
    if vel.z > action.clampVerticalTo then
        SetEntityVelocity(ped, vel.x, vel.y, action.clampVerticalTo)
    end

    if action.restore then
        if Config.DetachOnCorrect and IsEntityAttached(ped) then
            DetachEntity(ped, true, false)
        end

        SetEntityCoordsNoOffset(ped, action.restore.x, action.restore.y,
            action.restore.z, false, false, false)
        SetEntityVelocity(ped, 0.0, 0.0, 0.0)

        if Config.ClearRagdollOnCorrect and IsPedRagdoll(ped) then
            ClearPedTasksImmediately(ped)
        end
    end
end

CreateThread(function()
    while true do
        Wait(0)

        local ped = PlayerPedId()
        local now = GetGameTimer()

        -- A new ped means the motion history belongs to someone else.
        if ped ~= lastPed then
            lastPed = ped
            detector:reset(now, Config.RespawnGraceMs)
        end

        local dead = IsPedDeadOrDying(ped, true)
        if wasDead and not dead then
            detector:reset(now, Config.RespawnGraceMs)
        end
        wasDead = dead

        local action = detector:update(sampleFrame(ped, now))
        if action then
            applyCorrection(ped, action)

            if action.detected then
                incidents = incidents + 1
                debugPrint(('blocked launch: %s magnitude=%.1f'):format(
                    action.detected, action.magnitude or 0.0))
            end
        end
    end
end)
