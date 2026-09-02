-- Lint config for local/CI checks. Declares the FiveM natives and
-- cross-file globals this resource relies on so luacheck only flags
-- genuine issues (typos, unused locals, shadowing, etc).
std = 'lua54'
max_line_length = false
exclude_files = { 'fxmanifest.lua' }

local natives = {
    -- resource / threading / commands
    'exports', 'GetCurrentResourceName', 'CreateThread', 'Wait',
    'RegisterCommand', 'RegisterKeyMapping', 'AddEventHandler', 'TriggerEvent',

    -- math / types
    'vector3',

    -- entities
    'PlayerPedId', 'DoesEntityExist', 'IsEntityDead', 'IsEntityAttached',
    'IsEntityAttachedToEntity', 'GetEntityCoords', 'GetEntityModel',
    'GetEntitySpeed', 'GetEntityForwardVector', 'FreezeEntityPosition',
    'GetEntityVelocity', 'SetEntityVelocity',
    'AttachEntityToEntity', 'DetachEntity', 'ApplyForceToEntity',
    'GetOffsetFromEntityGivenWorldCoords', 'GetModelDimensions',
    'GetGamePool', 'GetGameTimer',

    -- peds
    'IsPedInAnyVehicle', 'IsPedRagdoll', 'IsPedDeadOrDying', 'ClearPedTasks',
    'TaskPlayAnim', 'StopAnimTask', 'SetEntityAnimSpeed',

    -- vehicles
    'GetVehicleClass', 'IsVehicleSeatFree', 'SetVehicleSteeringAngle',
    'SetVehicleHandbrake',

    -- animation streaming
    'DoesAnimDictExist', 'RequestAnimDict', 'HasAnimDictLoaded',

    -- network
    'NetworkHasControlOfEntity', 'NetworkRequestControlOfEntity',

    -- controls / UI
    'IsControlPressed', 'IsDisabledControlPressed', 'DisableControlAction',
    'AddTextEntry', 'BeginTextCommandDisplayHelp', 'EndTextCommandDisplayHelp',
    'BeginTextCommandThefeedPost', 'AddTextComponentSubstringPlayerName',
    'EndTextCommandThefeedPostTicker',
}

globals = { 'Config' }
read_globals = natives

-- The test harness deliberately defines the natives it stubs out.
files['tests/'] = {
    globals = natives,
    read_globals = { 'Config' },
    -- Native stubs keep the real parameter names for documentation even
    -- where the stub ignores them.
    unused_args = false,
}
