-- Lint config for esx_launchguard. Run from the repo root:
--   luacheck --config dev/.luacheckrc esx_launchguard dev/launchguard-tests
std = 'lua54'
max_line_length = false
exclude_files = { '**/fxmanifest.lua' }

local natives = {
    -- resource / threading / events
    'CreateThread', 'Wait', 'GetGameTimer', 'GetFrameTime',
    'AddEventHandler', 'RegisterNetEvent', 'TriggerEvent', 'TriggerServerEvent',
    'TriggerClientEvent', 'RegisterCommand', 'GetCurrentResourceName',
    'exports', 'source', 'json', 'vector3',

    -- entities / peds
    'PlayerPedId', 'GetEntityCoords', 'GetEntityVelocity', 'SetEntityVelocity',
    'SetEntityCoordsNoOffset', 'IsEntityInAir', 'IsEntityAttached', 'DetachEntity',
    'ClearPedTasksImmediately', 'IsPedDeadOrDying', 'IsPedInAnyVehicle',
    'IsPedRagdoll', 'IsPedClimbing', 'IsPedVaulting', 'IsPedSwimming',
    'IsPedInParachuteFreeFall', 'GetPedParachuteState', 'IsPlayerSwitchInProgress',
    'IsPedInAnyPlane', 'IsPedInAnyHeli',

    -- network
    'NetworkGetEntityIsNetworked', 'PedToNet', 'SetNetworkIdCanMigrate',

    -- ui
    'BeginTextCommandThefeedPost', 'AddTextComponentSubstringPlayerName',
    'EndTextCommandThefeedPostTicker',

    -- server
    'GetPlayers', 'GetPlayerName', 'GetPlayerPed', 'GetPlayerIdentifiers',
    'IsPlayerAceAllowed', 'PerformHttpRequest',
}

globals = { 'Config', 'LaunchDetector' }
read_globals = natives

-- The test harness defines the natives it stubs, and keeps real parameter
-- names on stubs that ignore them.
files['dev/launchguard-tests/'] = {
    -- Specs deliberately write Config overrides, and the mock replaces
    -- print() so resource console output can be asserted on.
    globals = natives,
    read_globals = {},
    unused_args = false,
}

files['dev/launchguard-tests/'].globals = (function()
    local g = { 'Config', 'LaunchDetector', 'print' }
    for _, n in ipairs(natives) do g[#g + 1] = n end
    return g
end)()
