-- esx_launchguard/client/main.lua
--
-- Samples the local player every frame, hands the motion to the detector,
-- and applies whatever correction it asks for.
--
-- Why client side: a ped's position is authoritative on its owner's
-- client. Whatever route the cheat takes - forced entity control, an
-- invisible explosion, a punt object, a straight coord set - the result
-- has to pass through the victim's own physics before it becomes a
-- position the anticheat sees. Cancelling it here means the launch never
-- reaches the anticheat as a suspicious position in the first place.

local ESX = nil

CreateThread(function()
    local attempts = 0
    while ESX == nil and attempts < 50 do
        TriggerEvent('esx:getSharedObject', function(obj) ESX = obj end)
        attempts = attempts + 1
        Wait(200)
    end
end)

local function Notify(msg)
    if ESX and ESX.ShowNotification then
        ESX.ShowNotification(msg)
    else
        BeginTextCommandThefeedPost('STRING')
        AddTextComponentSubstringPlayerName(msg)
        EndTextCommandThefeedPostTicker(false, true)
    end
end

local function DebugPrint(...)
    if Config.Debug then
        print('[launchguard]', ...)
    end
end

-- Some state natives are absent on older builds. Missing ones degrade to
-- "false" rather than erroring out mid-frame.
local function optional(name)
    local fn = _G[name]
    if type(fn) == 'function' then return fn end
    DebugPrint('native unavailable, treated as false:', name)
    return function() return false end
end

local IsPedClimbingFn        = optional('IsPedClimbing')
local IsPedVaultingFn        = optional('IsPedVaulting')
local IsPedSwimmingFn        = optional('IsPedSwimming')
local IsPedFreeFallFn        = optional('IsPedInParachuteFreeFall')
local IsSwitchInProgressFn   = optional('IsPlayerSwitchInProgress')
local GetParachuteStateFn    = optional('GetPedParachuteState')
local IsPedInAnyPlaneFn      = optional('IsPedInAnyPlane')
local IsPedInAnyHeliFn       = optional('IsPedInAnyHeli')

-- ── State ──────────────────────────────────────────────────────────────
local detector       = LaunchDetector.new(Config, 0)
local suppressedUntil = 0
local lastPed        = nil
local wasDead        = false
local incidents      = 0

-- ── Exports ────────────────────────────────────────────────────────────
-- Other resources call this around a legitimate teleport or scripted
-- launch so the guard stands down:
--   exports['esx_launchguard']:SuppressFor(1500)
local function SuppressFor(ms)
    ms = tonumber(ms) or 0
    if ms <= 0 then return end
    local until_ = GetGameTimer() + math.min(ms, 30000)
    if until_ > suppressedUntil then suppressedUntil = until_ end
    DebugPrint('suppressed for', ms, 'ms')
end

exports('SuppressFor', SuppressFor)
exports('IsSuppressed', function() return GetGameTimer() < suppressedUntil end)
exports('GetIncidentCount', function() return incidents end)

-- Event form, for resources that would rather not depend on the export.
RegisterNetEvent('esx_launchguard:suppress')
AddEventHandler('esx_launchguard:suppress', SuppressFor)

-- Live alerts for staff, sent by the server to players holding the ACE.
RegisterNetEvent('esx_launchguard:staffAlert')
AddEventHandler('esx_launchguard:staffAlert', function(text)
    if type(text) == 'string' then Notify(text) end
end)

-- ── Sampling ───────────────────────────────────────────────────────────
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
        aircraft     = IsPedInAnyPlaneFn(ped) or IsPedInAnyHeliFn(ped),
        grounded     = not IsEntityInAir(ped),
        swimming     = IsPedSwimmingFn(ped),
        climbing     = IsPedClimbingFn(ped) or IsPedVaultingFn(ped),
        parachuting  = IsPedFreeFallFn(ped) or (GetParachuteStateFn(ped) or -1) > 0,
        switchActive = IsSwitchInProgressFn(),
        suppressed   = now < suppressedUntil,
    }
end

-- ── Correction ─────────────────────────────────────────────────────────
local function applyCorrection(ped, action)
    -- Cap upward velocity only. Downward motion is left alone so gravity,
    -- falling and fall damage all behave normally.
    local vel = GetEntityVelocity(ped)
    if vel.z > action.clampVerticalTo then
        SetEntityVelocity(ped, vel.x, vel.y, action.clampVerticalTo)
    end

    if action.restore then
        if Config.DetachOnCorrect and IsEntityAttached(ped) then
            DetachEntity(ped, true, false)
        end

        SetEntityCoordsNoOffset(ped, action.restore.x, action.restore.y, action.restore.z,
            false, false, false)
        SetEntityVelocity(ped, 0.0, 0.0, 0.0)

        if Config.ClearRagdollOnCorrect and IsPedRagdoll(ped) then
            ClearPedTasksImmediately(ped)
        end
    end
end

local function reportIncident(report)
    incidents = incidents + 1

    DebugPrint(('blocked launch: %s magnitude=%.1f vz=%.1f rise=%.1f'):format(
        report.reason, report.magnitude or 0.0, report.verticalVel or 0.0, report.rise or 0.0))

    if Config.ReportToServer then
        TriggerServerEvent('esx_launchguard:report', {
            reason    = report.reason,
            magnitude = report.magnitude,
            verticalVelocity = report.verticalVel,
            rise      = report.rise,
            inVehicle = report.inVehicle,
        })
    end

    if Config.NotifyVictim then
        Notify(Config.VictimMessage)
    end
end

-- ── Ownership hardening (optional) ─────────────────────────────────────
local function lockOwnership(ped)
    if not Config.LockNetworkOwnership then return end
    if not NetworkGetEntityIsNetworked(ped) then return end

    local netId = PedToNet(ped)
    if netId and netId ~= 0 then
        SetNetworkIdCanMigrate(netId, false)
    end
end

-- ── Main loop ──────────────────────────────────────────────────────────
CreateThread(function()
    while true do
        Wait(0)

        local ped = PlayerPedId()
        local now = GetGameTimer()

        -- New ped (respawn, model change): motion history from the old one
        -- is meaningless and would read as a teleport.
        if ped ~= lastPed then
            lastPed = ped
            detector:reset(now, Config.RespawnGraceMs)
            lockOwnership(ped)
        end

        -- Coming back from death is a teleport by definition.
        local dead = IsPedDeadOrDying(ped, true)
        if wasDead and not dead then
            detector:reset(now, Config.RespawnGraceMs)
            lockOwnership(ped)
        end
        wasDead = dead

        local action = detector:update(sampleFrame(ped, now))
        if action then
            applyCorrection(ped, action)
            if action.report then
                reportIncident(action.report)
            end
        end
    end
end)

-- Ownership is re-asserted periodically: a cheat can request control
-- repeatedly, and other resources may reset the flag.
CreateThread(function()
    while true do
        Wait(5000)
        if Config.LockNetworkOwnership then
            lockOwnership(PlayerPedId())
        end
    end
end)
