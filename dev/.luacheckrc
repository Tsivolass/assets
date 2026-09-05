-- Lint config. Run from the repo root:
--   luacheck --config dev/.luacheckrc esx_launchguard dev/launchguard-tests
std = 'lua54'
max_line_length = false
exclude_files = { '**/fxmanifest.lua' }

local natives = {
    'CreateThread', 'Wait', 'GetGameTimer', 'GetFrameTime',
    'AddEventHandler', 'RegisterNetEvent', 'TriggerEvent', 'TriggerServerEvent',
    'exports', 'vector3',

    'PlayerPedId', 'GetEntityCoords', 'GetEntityVelocity', 'SetEntityVelocity',
    'SetEntityCoordsNoOffset', 'IsEntityInAir', 'IsEntityAttached', 'DetachEntity',
    'ClearPedTasksImmediately', 'IsPedDeadOrDying', 'IsPedInAnyVehicle',
    'IsPedRagdoll', 'IsPedClimbing', 'IsPedVaulting', 'IsPedSwimming',
    'IsPedInParachuteFreeFall', 'GetPedParachuteState', 'IsPlayerSwitchInProgress',
    'IsPedInAnyPlane', 'IsPedInAnyHeli',

    -- stubbed by the harness so tests can prove the resource never calls them
    'NetworkGetEntityIsNetworked', 'PedToNet', 'SetNetworkIdCanMigrate',
    'BeginTextCommandThefeedPost', 'AddTextComponentSubstringPlayerName',
    'EndTextCommandThefeedPostTicker',
}

globals = { 'Config', 'LaunchDetector' }
read_globals = natives

files['dev/launchguard-tests/'] = {
    -- Specs deliberately write Config overrides.
    globals = (function()
        local g = { 'Config', 'LaunchDetector' }
        for _, n in ipairs(natives) do g[#g + 1] = n end
        return g
    end)(),
    unused_args = false,
}
