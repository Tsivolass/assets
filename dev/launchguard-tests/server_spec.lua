-- Tests for the server side: sanitising, rate limiting, suspect lists.

return function(t, paths)
    local mock = dofile(paths.tests .. '/mock_fivem.lua')

    local function load(overrides)
        mock.reset()
        dofile(paths.resource .. '/config.lua')
        for k, v in pairs(overrides or {}) do Config.Server[k] = v end
        dofile(paths.resource .. '/server/main.lua')
        mock.ticks(2)
    end

    local function addPlayer(id, name, x, y, z)
        mock.players[id] = {
            name = name, ped = 1000 + id,
            coords = { x = x, y = y, z = z },
            identifiers = { 'license:abc' .. id },
        }
    end

    local function goodReport(over)
        local p = { reason = 'vertical_speed', magnitude = 42.5,
                    verticalVelocity = 42.5, rise = 18.0, inVehicle = false }
        for k, v in pairs(over or {}) do p[k] = v end
        return p
    end

    -- Console output produced by the next call.
    local function capture(fn)
        local from = #mock.consoleLog + 1
        fn()
        local out = {}
        for i = from, #mock.consoleLog do out[#out + 1] = mock.consoleLog[i] end
        return table.concat(out, '\n')
    end

    t.group('server: report intake')

    t.check('a valid report is logged', function()
        load()
        addPlayer(1, 'Victim', 0.0, 0.0, 30.0)
        local out = capture(function()
            mock.triggerFromClient('esx_launchguard:report', 1, goodReport())
        end)
        t.assert(out:find('BLOCKED', 1, true), 'no log line written: ' .. out)
        t.assert(out:find('Victim', 1, true), 'victim not named')
        t.equal(#exports['esx_launchguard']:GetIncidents(), 1)
    end)

    t.check('nobody is ever punished', function()
        load()
        addPlayer(1, 'Victim', 0.0, 0.0, 30.0)
        mock.triggerFromClient('esx_launchguard:report', 1, goodReport())
        -- The resource has no kick/ban path at all; assert on the source.
        local src = io.open(paths.resource .. '/server/main.lua'):read('a')
        t.assert(not src:find('DropPlayer', 1, true), 'server can drop players')
        t.assert(not src:lower():find('executecommand', 1, true), 'server runs commands')
    end)

    t.group('server: hostile input is rejected')

    t.check('a non-table payload', function()
        load()
        addPlayer(1, 'Victim', 0.0, 0.0, 30.0)
        mock.triggerFromClient('esx_launchguard:report', 1, 'launch!')
        t.equal(#exports['esx_launchguard']:GetIncidents(), 0)
    end)

    t.check('an unknown reason string', function()
        load()
        addPlayer(1, 'Victim', 0.0, 0.0, 30.0)
        mock.triggerFromClient('esx_launchguard:report', 1, goodReport { reason = 'ban_everyone' })
        t.equal(#exports['esx_launchguard']:GetIncidents(), 0)
    end)

    t.check('a table where the reason should be', function()
        load()
        addPlayer(1, 'Victim', 0.0, 0.0, 30.0)
        mock.triggerFromClient('esx_launchguard:report', 1, goodReport { reason = { 'nested' } })
        t.equal(#exports['esx_launchguard']:GetIncidents(), 0)
    end)

    t.check('absurd and NaN numbers are clamped, not passed through', function()
        load()
        addPlayer(1, 'Victim', 0.0, 0.0, 30.0)
        mock.triggerFromClient('esx_launchguard:report', 1,
            goodReport { magnitude = 1e30, rise = 0 / 0 })
        local inc = exports['esx_launchguard']:GetIncidents()[1]
        t.assert(inc.magnitude <= 1e6, 'magnitude not clamped')
        t.assert(inc.rise == inc.rise, 'NaN reached the log')
    end)

    t.check('a report spam flood is capped', function()
        load { MaxReportsPerMin = 3 }
        addPlayer(1, 'Spammer', 0.0, 0.0, 30.0)
        for _ = 1, 50 do
            mock.triggerFromClient('esx_launchguard:report', 1, goodReport())
        end
        t.equal(#exports['esx_launchguard']:GetIncidents(), 3)
    end)

    t.check('the cap is per player', function()
        load { MaxReportsPerMin = 2 }
        addPlayer(1, 'A', 0.0, 0.0, 30.0)
        addPlayer(2, 'B', 5.0, 0.0, 30.0)
        for _ = 1, 10 do
            mock.triggerFromClient('esx_launchguard:report', 1, goodReport())
            mock.triggerFromClient('esx_launchguard:report', 2, goodReport())
        end
        t.equal(#exports['esx_launchguard']:GetIncidents(), 4)
    end)

    t.group('server: suspects come from server-side coords')

    t.check('nearby players are listed closest first', function()
        load()
        addPlayer(1, 'Victim', 0.0, 0.0, 30.0)
        addPlayer(2, 'Far', 100.0, 0.0, 30.0)
        addPlayer(3, 'Close', 8.0, 0.0, 30.0)
        mock.triggerFromClient('esx_launchguard:report', 1, goodReport())

        local inc = exports['esx_launchguard']:GetIncidents()[1]
        t.equal(#inc.suspects, 2)
        t.equal(inc.suspects[1].name, 'Close')
        t.equal(inc.suspects[2].name, 'Far')
    end)

    t.check('players beyond the radius are ignored', function()
        load { NearbyRadius = 50.0 }
        addPlayer(1, 'Victim', 0.0, 0.0, 30.0)
        addPlayer(2, 'Distant', 900.0, 0.0, 30.0)
        mock.triggerFromClient('esx_launchguard:report', 1, goodReport())
        t.equal(#exports['esx_launchguard']:GetIncidents()[1].suspects, 0)
    end)

    t.check('the victim never appears in their own suspect list', function()
        load()
        addPlayer(1, 'Victim', 0.0, 0.0, 30.0)
        addPlayer(2, 'Other', 3.0, 0.0, 30.0)
        mock.triggerFromClient('esx_launchguard:report', 1, goodReport())
        for _, s in ipairs(exports['esx_launchguard']:GetIncidents()[1].suspects) do
            t.assert(s.id ~= 1, 'victim listed as a suspect')
        end
    end)

    t.check('the suspect list is capped', function()
        load { MaxSuspects = 3 }
        addPlayer(1, 'Victim', 0.0, 0.0, 30.0)
        for i = 2, 12 do addPlayer(i, 'P' .. i, i * 1.0, 0.0, 30.0) end
        mock.triggerFromClient('esx_launchguard:report', 1, goodReport())
        t.equal(#exports['esx_launchguard']:GetIncidents()[1].suspects, 3)
    end)

    t.group('server: staff output')

    t.check('only ACE holders get the live alert', function()
        load()
        addPlayer(1, 'Victim', 0.0, 0.0, 30.0)
        addPlayer(2, 'Mod', 5.0, 0.0, 30.0)
        addPlayer(3, 'Civilian', 6.0, 0.0, 30.0)
        mock.acePerms[2] = Config.Server.StaffAce

        mock.triggerFromClient('esx_launchguard:report', 1, goodReport())
        t.equal(#mock.clientEvents, 1, 'alert went to the wrong number of players')
        t.equal(mock.clientEvents[1].target, 2)
    end)

    t.check('the webhook fires only when configured', function()
        load()
        addPlayer(1, 'Victim', 0.0, 0.0, 30.0)
        mock.triggerFromClient('esx_launchguard:report', 1, goodReport())
        t.equal(#mock.httpPosts, 0, 'posted without a webhook url')

        load { DiscordWebhook = 'https://discord.example/hook' }
        addPlayer(1, 'Victim', 0.0, 0.0, 30.0)
        mock.triggerFromClient('esx_launchguard:report', 1, goodReport())
        t.equal(#mock.httpPosts, 1)
        t.assert(mock.httpPosts[1].body:find('Victim', 1, true), 'victim missing from webhook')
    end)

    t.group('server: /launchguard command')

    t.check('console can read the history', function()
        load()
        addPlayer(1, 'Victim', 0.0, 0.0, 30.0)
        mock.triggerFromClient('esx_launchguard:report', 1, goodReport())
        local out = capture(function() mock.commands['launchguard'](0, {}) end)
        t.assert(out:find('Victim', 1, true), 'history not printed: ' .. out)
    end)

    t.check('players without the ACE get nothing', function()
        load()
        addPlayer(1, 'Victim', 0.0, 0.0, 30.0)
        addPlayer(2, 'Nosy', 5.0, 0.0, 30.0)
        mock.triggerFromClient('esx_launchguard:report', 1, goodReport())
        local out = capture(function() mock.commands['launchguard'](2, {}) end)
        t.equal(out, '', 'history leaked to a non-staff player')
    end)

    t.check('an empty history says so', function()
        load()
        local out = capture(function() mock.commands['launchguard'](0, {}) end)
        t.assert(out:find('no launch attempts', 1, true), out)
    end)

    t.check('history is capped', function()
        load { HistorySize = 5, MaxReportsPerMin = 1000 }
        addPlayer(1, 'Victim', 0.0, 0.0, 30.0)
        for _ = 1, 20 do
            mock.triggerFromClient('esx_launchguard:report', 1, goodReport())
        end
        t.equal(#exports['esx_launchguard']:GetIncidents(), 5)
    end)
end
