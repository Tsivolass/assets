-- esx_pushvehicle/client/main.lua
--
-- Push a stationary car or bike while on foot.
--
--   Shift + F   start pushing (while standing at the bumper)
--   W           push the vehicle away from you
--   A / D       steer it left / right while pushing
--   F           stop pushing
--
-- With no direction key held the vehicle is held still, so it will not
-- roll away on a slope while you are braced against it.

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
        print('[esx_pushvehicle]', ...)
    end
end

-- ── Controls ───────────────────────────────────────────────────────────
local CONTROL_SPRINT      = 21  -- LSHIFT
local CONTROL_JUMP        = 22
local CONTROL_ENTER_OLD   = 23  -- legacy "enter vehicle"
local CONTROL_ATTACK      = 24
local CONTROL_AIM         = 25
local CONTROL_MOVE_LR     = 30
local CONTROL_MOVE_UD     = 31
local CONTROL_MOVE_FWD    = 32  -- W
local CONTROL_MOVE_BACK   = 33  -- S
local CONTROL_MOVE_LEFT   = 34  -- A
local CONTROL_MOVE_RIGHT  = 35  -- D
local CONTROL_VEH_ENTER   = 75  -- enter / exit vehicle
local CONTROL_MELEE_LIGHT = 140
local CONTROL_MELEE_HEAVY = 141
local CONTROL_MELEE_ALT   = 142

-- ── State ──────────────────────────────────────────────────────────────
local nearVehicle = nil   -- vehicle currently in push range
local nearSign    = 0     -- +1 push toward the nose, -1 push toward the trunk
local canPush     = false

local isPushing   = false
local pushVehicle = nil
local pushSign    = 0
local animPlaying = false

-- ── Help text ──────────────────────────────────────────────────────────
local function ShowHelpText(text)
    AddTextEntry('ESX_PUSHVEHICLE_HELP', text)
    BeginTextCommandDisplayHelp('ESX_PUSHVEHICLE_HELP')
    EndTextCommandDisplayHelp(0, false, true, -1)
end

-- ── Vehicle detection ──────────────────────────────────────────────────

-- Closest vehicle to `coords` within `maxDistance`, or nil.
local function GetClosestVehicle(coords, maxDistance)
    if ESX and ESX.Game and ESX.Game.GetClosestVehicle then
        local vehicle, dist = ESX.Game.GetClosestVehicle(coords)
        if vehicle and vehicle ~= 0 and dist <= maxDistance then
            return vehicle
        end
        return nil
    end

    local vehicles = GetGamePool('CVehicle')
    local closest, closestDist = nil, maxDistance
    for i = 1, #vehicles do
        local v = vehicles[i]
        local d = #(coords - GetEntityCoords(v))
        if d < closestDist then
            closest, closestDist = v, d
        end
    end
    return closest
end

-- Vehicle classes we allow pushing, per config.
local function IsVehicleClassAllowed(vehicle)
    local class = GetVehicleClass(vehicle)
    -- Motorcycles = 8, Cycles (bicycles) = 13
    if class == 8 or class == 13 then
        return Config.AllowBikes
    end
    -- Boats(14) / Helicopters(15) / Planes(16) can't be pushed like this.
    -- Trains aren't part of the CVehicle pool this script scans, so they
    -- never reach this check.
    if class == 14 or class == 15 or class == 16 then
        return false
    end
    return Config.AllowCars
end

-- Is `ped` standing in the push zone (just past the bumper, roughly
-- centered) of `vehicle`? Returns the push sign: +1 when the ped is at the
-- trunk (vehicle gets pushed toward its nose), -1 when the ped is at the
-- nose (vehicle gets pushed toward its trunk). Returns nil when the ped
-- isn't in a valid push position.
local function GetPushSign(ped, vehicle)
    local minDim, maxDim = GetModelDimensions(GetEntityModel(vehicle))
    local halfLength = (maxDim.y - minDim.y) / 2.0
    local halfWidth  = (maxDim.x - minDim.x) / 2.0

    local pc = GetEntityCoords(ped)
    local offset = GetOffsetFromEntityGivenWorldCoords(vehicle, pc.x, pc.y, pc.z)

    local minY = halfLength - Config.PushZoneInset
    local maxY = halfLength + Config.PushZoneDepth
    local maxX = halfWidth * Config.PushZoneHalfWidth

    if math.abs(offset.x) > maxX then
        return nil
    end

    -- Vehicle-local +Y is the nose/forward direction, -Y is the trunk/rear.
    if offset.y >= minY and offset.y <= maxY then
        return -1 -- ped at the nose -> push the vehicle backwards
    elseif offset.y <= -minY and offset.y >= -maxY then
        return 1  -- ped at the trunk -> push the vehicle forwards
    end

    return nil
end

-- Class / speed / driver eligibility.
local function IsVehiclePushable(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        return false
    end
    if IsEntityDead(vehicle) then
        return false
    end
    if not IsVehicleClassAllowed(vehicle) then
        return false
    end
    if GetEntitySpeed(vehicle) > Config.MaxVehicleSpeed then
        return false
    end
    if Config.RequireEmptyDriverSeat and not IsVehicleSeatFree(vehicle, -1) then
        return false
    end
    if IsEntityAttached(vehicle) then
        return false
    end
    return true
end

-- ── Push helpers ───────────────────────────────────────────────────────

local function LoadAnimDict(dict, timeoutMs)
    if not DoesAnimDictExist(dict) then
        return false
    end
    RequestAnimDict(dict)
    local start = GetGameTimer()
    while not HasAnimDictLoaded(dict) do
        if GetGameTimer() - start > timeoutMs then
            return false
        end
        Wait(0)
    end
    return true
end

-- Bleeds off horizontal velocity so the vehicle holds position while no
-- direction key is held. Vertical velocity is left alone so gravity still
-- applies normally.
local function HoldVehicleStill(vehicle)
    local vel = GetEntityVelocity(vehicle)
    local planar = math.sqrt(vel.x * vel.x + vel.y * vel.y)

    if planar > Config.StationarySnapSpeed then
        SetEntityVelocity(vehicle, vel.x * Config.StationaryDamping, vel.y * Config.StationaryDamping, vel.z)
    elseif planar > 0.0 then
        SetEntityVelocity(vehicle, 0.0, 0.0, vel.z)
    end

    SetVehicleHandbrake(vehicle, true)
end

local function StopPush(reason)
    if not isPushing then return end

    local ped = PlayerPedId()

    if animPlaying then
        StopAnimTask(ped, Config.Anim.dict, Config.Anim.name, 2.0)
        animPlaying = false
    end
    ClearPedTasks(ped)

    if IsEntityAttachedToEntity(ped, pushVehicle or 0) then
        DetachEntity(ped, true, false)
    end

    if pushVehicle and DoesEntityExist(pushVehicle) then
        SetVehicleSteeringAngle(pushVehicle, 0.0)
        SetVehicleHandbrake(pushVehicle, true)
    end

    DebugPrint('push stopped:', reason)

    isPushing   = false
    pushVehicle = nil
    pushSign    = 0

    if reason == 'occupied' then
        Notify(Config.Locales.occupied)
    elseif reason == 'too_fast' then
        Notify(Config.Locales.too_fast)
    end
end

-- One frame of an active push: reads W/A/D, applies force and steering, or
-- holds the vehicle still when nothing is held.
local function PushTick()
    local vehicle = pushVehicle

    -- Movement/interaction controls are disabled so the ped doesn't fight
    -- the attachment; they're read back with IsDisabledControlPressed.
    DisableControlAction(0, CONTROL_MOVE_LR, true)
    DisableControlAction(0, CONTROL_MOVE_UD, true)
    DisableControlAction(0, CONTROL_MOVE_FWD, true)
    DisableControlAction(0, CONTROL_MOVE_BACK, true)
    DisableControlAction(0, CONTROL_MOVE_LEFT, true)
    DisableControlAction(0, CONTROL_MOVE_RIGHT, true)
    DisableControlAction(0, CONTROL_JUMP, true)
    DisableControlAction(0, CONTROL_ATTACK, true)
    DisableControlAction(0, CONTROL_AIM, true)
    DisableControlAction(0, CONTROL_ENTER_OLD, true)
    DisableControlAction(0, CONTROL_VEH_ENTER, true)
    DisableControlAction(0, CONTROL_MELEE_LIGHT, true)
    DisableControlAction(0, CONTROL_MELEE_HEAVY, true)
    DisableControlAction(0, CONTROL_MELEE_ALT, true)

    ShowHelpText(Config.HelpTextPushing)

    local forward = IsDisabledControlPressed(0, CONTROL_MOVE_FWD)
    local left    = IsDisabledControlPressed(0, CONTROL_MOVE_LEFT)
    local right   = IsDisabledControlPressed(0, CONTROL_MOVE_RIGHT)

    -- Steering: A = left, D = right. Positive steering angle turns left in
    -- GTA, and the mapping is mirrored when pushing from the nose so that
    -- "left" always means the player's left.
    local steer = 0.0
    if left and not right then
        steer = 1.0
    elseif right and not left then
        steer = -1.0
    end
    if Config.InvertSteer then
        steer = -steer
    end
    SetVehicleSteeringAngle(vehicle, steer * Config.SteerAngle * pushSign)

    local pushing = forward or left or right

    if pushing then
        SetVehicleHandbrake(vehicle, false)

        if GetEntitySpeed(vehicle) < Config.MaxPushSpeed then
            -- Recomputed every frame so the push follows the vehicle as it
            -- turns under steering.
            local dir = GetEntityForwardVector(vehicle)
            ApplyForceToEntity(
                vehicle, 3,
                dir.x * pushSign * Config.PushForce,
                dir.y * pushSign * Config.PushForce,
                0.0,
                0.0, 0.0, 0.0,
                0, false, true, true, false, true
            )
        end
    else
        HoldVehicleStill(vehicle)
    end

    if animPlaying then
        SetEntityAnimSpeed(PlayerPedId(), Config.Anim.dict, Config.Anim.name, pushing and 1.0 or 0.0)
    end
end

local function StartPush(ped, vehicle, sign)
    if isPushing then return end
    if not IsVehiclePushable(vehicle) then return end

    -- Take network control so the vehicle moves smoothly for every player,
    -- not just locally.
    if not NetworkHasControlOfEntity(vehicle) then
        local start = GetGameTimer()
        NetworkRequestControlOfEntity(vehicle)
        while not NetworkHasControlOfEntity(vehicle) do
            if GetGameTimer() - start > 1000 then
                Notify(Config.Locales.no_control)
                return
            end
            NetworkRequestControlOfEntity(vehicle)
            Wait(0)
        end
    end

    isPushing   = true
    pushVehicle = vehicle
    pushSign    = sign

    local minDim, maxDim = GetModelDimensions(GetEntityModel(vehicle))
    local halfLength = (maxDim.y - minDim.y) / 2.0
    -- sign +1 means the ped stands at the trunk (negative local Y).
    local attachY = -sign * (halfLength + 0.35)
    local headingOffset = (sign == 1) and 0.0 or 180.0

    animPlaying = LoadAnimDict(Config.Anim.dict, Config.Anim.loadTimeoutMs)
    if not animPlaying then
        DebugPrint(Config.Locales.anim_load_failed)
    end

    AttachEntityToEntity(
        ped, vehicle, 0,
        0.0, attachY, 0.0,
        0.0, 0.0, headingOffset,
        false, false, false, false, 2, true
    )

    if animPlaying then
        TaskPlayAnim(ped, Config.Anim.dict, Config.Anim.name, 8.0, -8.0, -1, 1, 0, false, false, false)
    end

    CreateThread(function()
        while isPushing do
            Wait(0)

            local currentPed = PlayerPedId()

            if not DoesEntityExist(pushVehicle) or IsEntityDead(pushVehicle) then
                StopPush('invalid_vehicle')
                break
            end

            if IsPedDeadOrDying(currentPed, true) or IsPedRagdoll(currentPed) then
                StopPush('ped_incapacitated')
                break
            end

            if Config.RequireEmptyDriverSeat and not IsVehicleSeatFree(pushVehicle, -1) then
                StopPush('occupied')
                break
            end

            if GetEntitySpeed(pushVehicle) >= Config.MaxPushSpeed + Config.RunawaySpeedMargin then
                -- Something else is moving it fast (rolling down a slope,
                -- another player) — let go instead of fighting it.
                StopPush('too_fast')
                break
            end

            PushTick()
        end
    end)
end

-- ── Key bindings ───────────────────────────────────────────────────────
-- Shift + F starts a push; F on its own ends it.
RegisterKeyMapping('+esx_pushvehicle', Config.KeyMapping.description, 'keyboard', Config.KeyMapping.key)

RegisterCommand('+esx_pushvehicle', function()
    if isPushing then
        StopPush('toggled_off')
        return
    end

    if not canPush or not nearVehicle then return end
    if not IsControlPressed(0, CONTROL_SPRINT) then return end -- Shift must be held
    if not IsVehiclePushable(nearVehicle) then return end

    StartPush(PlayerPedId(), nearVehicle, nearSign)
end, false)

-- Key release: nothing to do, the push is a toggled mode.
RegisterCommand('-esx_pushvehicle', function() end, false)

-- ── Detection loop ─────────────────────────────────────────────────────
CreateThread(function()
    while true do
        local sleep = 750
        local ped = PlayerPedId()

        if not isPushing and not IsPedInAnyVehicle(ped, false) and not IsPedRagdoll(ped) and not IsPedDeadOrDying(ped, true) then
            local vehicle = GetClosestVehicle(GetEntityCoords(ped), Config.MaxPushDistance)
            local sign = nil

            if vehicle and IsVehiclePushable(vehicle) then
                sign = GetPushSign(ped, vehicle)
            end

            if sign then
                nearVehicle = vehicle
                nearSign    = sign
                canPush     = true

                ShowHelpText(Config.HelpText)
                DisableControlAction(0, CONTROL_ENTER_OLD, true)
                DisableControlAction(0, CONTROL_VEH_ENTER, true)

                sleep = 0
            else
                canPush     = false
                nearVehicle = nil
                nearSign    = 0
            end
        elseif isPushing then
            sleep = 250 -- the push thread itself runs every frame
        end

        Wait(sleep)
    end
end)

-- ── Cleanup ────────────────────────────────────────────────────────────
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    if isPushing then
        StopPush('resource_stop')
    end
end)
