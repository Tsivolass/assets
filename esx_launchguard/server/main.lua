-- esx_launchguard/server/main.lua
--
-- Collects blocked-launch reports, works out who was standing near the
-- victim, and writes it somewhere a moderator will see it.
--
-- This never bans, kicks or punishes. Reports arrive from clients, so a
-- cheat could forge or spam them; they are rate limited, sanitised, and
-- treated as a lead for a human to follow, never as proof. The suspect
-- list is built from server-side coordinates, so the reporting client
-- cannot choose who gets named.

local ESX = nil

CreateThread(function()
    local attempts = 0
    while ESX == nil and attempts < 50 do
        TriggerEvent('esx:getSharedObject', function(obj) ESX = obj end)
        attempts = attempts + 1
        Wait(200)
    end
end)

local history = {}     -- ring of recent incidents, newest last
local rateWindow = {}  -- [src] = { start = ms, count = n }

local VALID_REASONS = {
    vertical_speed = 'launched upward',
    velocity_step  = 'sudden upward force',
    position_jump  = 'moved upward without velocity',
    teleport       = 'position warp',
}

local function log(msg)
    if Config.Server.ConsoleLog then
        print('[launchguard] ' .. msg)
    end
end

-- ── Input handling ─────────────────────────────────────────────────────

local function clampNumber(v, lo, hi, fallback)
    v = tonumber(v)
    if not v or v ~= v then return fallback end -- nil or NaN
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- Returns a clean payload, or nil if it isn't something this resource
-- would ever send.
local function sanitize(payload)
    if type(payload) ~= 'table' then return nil end
    if type(payload.reason) ~= 'string' or not VALID_REASONS[payload.reason] then
        return nil
    end

    return {
        reason           = payload.reason,
        magnitude        = clampNumber(payload.magnitude, 0.0, 1e6, 0.0),
        verticalVelocity = clampNumber(payload.verticalVelocity, -1e6, 1e6, 0.0),
        rise             = clampNumber(payload.rise, -1e6, 1e6, 0.0),
        inVehicle        = payload.inVehicle == true,
    }
end

local function withinRate(src, now)
    local r = rateWindow[src]
    if not r or (now - r.start) >= 60000 then
        rateWindow[src] = { start = now, count = 1 }
        return true
    end
    if r.count >= Config.Server.MaxReportsPerMin then
        return false
    end
    r.count = r.count + 1
    return true
end

-- ── Identity / suspects ────────────────────────────────────────────────

local function identifierOf(src)
    if ESX and ESX.GetPlayerFromId then
        local xPlayer = ESX.GetPlayerFromId(src)
        if xPlayer and xPlayer.identifier then return xPlayer.identifier end
    end
    for _, id in ipairs(GetPlayerIdentifiers(src) or {}) do
        if id:sub(1, 8) == 'license:' then return id end
    end
    return 'unknown'
end

-- Players near the victim at the moment of the incident, closest first.
-- Coordinates come from the server, not from the reporting client.
local function nearbyPlayers(victimSrc)
    local victimPed = GetPlayerPed(victimSrc)
    if not victimPed or victimPed == 0 then return {} end

    local origin = GetEntityCoords(victimPed)
    local found = {}

    for _, idStr in ipairs(GetPlayers()) do
        local id = tonumber(idStr)
        if id and id ~= victimSrc then
            local ped = GetPlayerPed(id)
            if ped and ped ~= 0 then
                local d = #(GetEntityCoords(ped) - origin)
                if d <= Config.Server.NearbyRadius then
                    found[#found + 1] = { id = id, name = GetPlayerName(id) or '?', distance = d }
                end
            end
        end
    end

    table.sort(found, function(a, b) return a.distance < b.distance end)
    while #found > Config.Server.MaxSuspects do
        table.remove(found)
    end
    return found
end

local function describeSuspects(suspects)
    if #suspects == 0 then return 'nobody within range' end
    local parts = {}
    for _, s in ipairs(suspects) do
        parts[#parts + 1] = ('%s(%d) %.0fm'):format(s.name, s.id, s.distance)
    end
    return table.concat(parts, ', ')
end

-- ── Output ─────────────────────────────────────────────────────────────

local function alertStaff(text)
    for _, idStr in ipairs(GetPlayers()) do
        local id = tonumber(idStr)
        if id and IsPlayerAceAllowed(id, Config.Server.StaffAce) then
            TriggerClientEvent('esx_launchguard:staffAlert', id, text)
        end
    end
end

local function sendWebhook(incident)
    local url = Config.Server.DiscordWebhook
    if not url or url == '' then return end

    local body = json.encode({
        username = 'launchguard',
        embeds = { {
            title = 'Launch attempt blocked',
            color = 15158332,
            fields = {
                { name = 'Victim', value = ('%s (id %d)'):format(incident.victim, incident.victimId) },
                { name = 'Identifier', value = incident.identifier },
                { name = 'Detection', value = ('%s (%.1f)'):format(incident.reason, incident.magnitude) },
                { name = 'Nearby', value = incident.suspectText },
            },
            footer = { text = incident.at },
        } },
    })

    PerformHttpRequest(url, function() end, 'POST', body, { ['Content-Type'] = 'application/json' })
end

local function record(incident)
    history[#history + 1] = incident
    while #history > Config.Server.HistorySize do
        table.remove(history, 1)
    end
end

-- ── Report intake ──────────────────────────────────────────────────────

RegisterNetEvent('esx_launchguard:report')
AddEventHandler('esx_launchguard:report', function(payload)
    local src = source
    local now = GetGameTimer()

    local clean = sanitize(payload)
    if not clean then
        log(('discarded a malformed report from id %s'):format(tostring(src)))
        return
    end

    if not withinRate(src, now) then
        return -- already logged plenty from this player this minute
    end

    local suspects = nearbyPlayers(src)
    local incident = {
        at          = os.date('%Y-%m-%d %H:%M:%S'),
        victim      = GetPlayerName(src) or '?',
        victimId    = src,
        identifier  = identifierOf(src),
        reason      = clean.reason,
        description = VALID_REASONS[clean.reason],
        magnitude   = clean.magnitude,
        rise        = clean.rise,
        inVehicle   = clean.inVehicle,
        suspects    = suspects,
        suspectText = describeSuspects(suspects),
    }

    record(incident)

    local line = ('BLOCKED %s on %s (id %d) | magnitude=%.1f rise=%.1fm%s | nearby: %s'):format(
        incident.description, incident.victim, incident.victimId,
        incident.magnitude, incident.rise,
        incident.inVehicle and ' in-vehicle' or '',
        incident.suspectText)

    log(line)
    alertStaff('^3[launchguard]^7 ' .. line)
    sendWebhook(incident)
end)

AddEventHandler('playerDropped', function()
    rateWindow[source] = nil
end)

-- ── Moderator command ──────────────────────────────────────────────────
-- /launchguard [count]  - recent blocked launches, newest last.
RegisterCommand('launchguard', function(src, args)
    if src ~= 0 and not IsPlayerAceAllowed(src, Config.Server.StaffAce) then
        return
    end

    local want = math.min(tonumber(args and args[1]) or 10, #history)
    if #history == 0 then
        log('no launch attempts recorded since restart')
        return
    end

    log(('last %d of %d recorded launch attempts:'):format(want, #history))
    for i = #history - want + 1, #history do
        local inc = history[i]
        log(('  %s  %s (id %d)  %s %.1f  nearby: %s'):format(
            inc.at, inc.victim, inc.victimId, inc.reason, inc.magnitude, inc.suspectText))
    end
end, true)

exports('GetIncidents', function() return history end)
