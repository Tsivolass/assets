-- Integration tests: the real client script running in the stubbed
-- runtime, driven frame by frame.

return function(t, paths)
    local mock = dofile(paths.tests .. '/mock_fivem.lua')

    -- Boots a fresh copy of the resource.
    local function load(overrides)
        mock.reset()
        dofile(paths.resource .. '/config.lua')
        for k, v in pairs(overrides or {}) do Config[k] = v end
        dofile(paths.resource .. '/shared/detector.lua')
        dofile(paths.resource .. '/client/main.lua')
        -- Past the startup grace window, standing still on the ground.
        mock.ticks(math.ceil(Config.StartupGraceMs / 16) + 20)
    end

    -- Simulates one frame in which the ped is moving as described.
    local function frame(pos, vel, state)
        for k, v in pairs(state or {}) do mock.ped[k] = v end
        if pos then mock.ped.pos = pos end
        if vel then mock.ped.vel = vel end
        mock.tick()
    end

    t.group('client: normal play is untouched')

    t.check('no corrections while standing still', function()
        load()
        local before = #mock.log.velocitySets
        mock.ticks(120)
        t.equal(#mock.log.velocitySets, before, 'velocity was written during idle')
        t.equal(#mock.log.coordSets, 0)
    end)

    t.check('no corrections during a jump', function()
        load()
        local before = #mock.log.velocitySets
        local vz = 5.0
        for _ = 1, 40 do
            frame({ x = 0, y = 0, z = mock.ped.pos.z + vz / 60 }, { x = 0, y = 0, z = vz },
                { inAir = true })
            vz = vz - 9.81 / 60
        end
        t.equal(#mock.log.velocitySets, before, 'jump was corrected')
    end)

    t.check('no report is sent during normal play', function()
        load()
        mock.ticks(120)
        t.equal(#mock.serverEvents, 0)
    end)

    t.group('client: a launch is cancelled')

    t.check('upward velocity is capped', function()
        load()
        frame(nil, { x = 2.0, y = 3.0, z = 40.0 }, { inAir = true })
        local set = mock.lastVelocitySet()
        t.assert(set ~= nil, 'no velocity correction applied')
        t.equal(set.z, 0.0, 'upward velocity not zeroed')
        t.equal(set.x, 2.0, 'horizontal velocity should be preserved')
    end)

    t.check('downward velocity is never touched', function()
        load()
        frame(nil, { x = 0, y = 0, z = 40.0 }, { inAir = true }) -- trigger
        local sets = #mock.log.velocitySets
        -- Now falling back down inside the clamp window.
        frame(nil, { x = 0, y = 0, z = -20.0 }, { inAir = true })
        t.equal(#mock.log.velocitySets, sets, 'falling velocity was overwritten')
    end)

    t.check('the player is put back on the ground', function()
        load()
        local ground = mock.ped.pos.z
        frame(nil, { x = 0, y = 0, z = 30.0 }, { inAir = true })
        frame({ x = 0, y = 0, z = ground + 25.0 }, { x = 0, y = 0, z = 25.0 }, { inAir = true })
        local coords = mock.lastCoordSet()
        t.assert(coords ~= nil, 'player was not put back')
        t.near(coords.z, ground, 1.0)
    end)

    t.check('ragdoll is cleared and attachments broken on correction', function()
        load()
        local ground = mock.ped.pos.z
        frame(nil, { x = 0, y = 0, z = 30.0 }, { inAir = true, ragdoll = true, attachedTo = 999 })
        frame({ x = 0, y = 0, z = ground + 25.0 }, { x = 0, y = 0, z = 25.0 }, { inAir = true })
        t.assert(mock.log.detaches > 0, 'attachment not broken')
        t.assert(mock.log.clearTasks > 0, 'ragdoll not cleared')
    end)

    t.check('the incident is reported to the server once', function()
        load()
        for _ = 1, 30 do
            frame(nil, { x = 0, y = 0, z = 40.0 }, { inAir = true })
        end
        t.equal(#mock.serverEvents, 1, 'expected exactly one report')
        local ev = mock.lastServerEvent()
        t.equal(ev.name, 'esx_launchguard:report')
        t.equal(ev.payload.reason, 'vertical_speed')
        t.assert(ev.payload.magnitude >= 40.0)
    end)

    t.check('the victim is told it was blocked', function()
        load()
        frame(nil, { x = 0, y = 0, z = 40.0 }, { inAir = true })
        t.equal(mock.notifications[1], Config.VictimMessage)
    end)

    t.check('reporting can be turned off', function()
        load { ReportToServer = false, NotifyVictim = false }
        frame(nil, { x = 0, y = 0, z = 40.0 }, { inAir = true })
        t.equal(#mock.serverEvents, 0)
        t.equal(#mock.notifications, 0)
        t.assert(mock.lastVelocitySet() ~= nil, 'correction should still apply')
    end)

    t.check('a pilot is left alone', function()
        load()
        frame(nil, { x = 0, y = 0, z = 90.0 },
            { inAir = true, inVehicle = true, inHeli = true })
        t.equal(#mock.log.velocitySets, 0, 'aircraft climb was corrected')
        t.equal(#mock.serverEvents, 0)
    end)

    t.group('client: suppression export')

    t.check('SuppressFor stands the guard down', function()
        load()
        exports['esx_launchguard']:SuppressFor(2000)
        frame({ x = 900.0, y = 900.0, z = 300.0 }, { x = 0, y = 0, z = 40.0 }, { inAir = true })
        t.equal(#mock.log.velocitySets, 0, 'corrected while suppressed')
        t.equal(#mock.serverEvents, 0)
    end)

    t.check('the guard comes back after suppression expires', function()
        load()
        exports['esx_launchguard']:SuppressFor(500)
        mock.ticks(60) -- ~1s
        frame(nil, { x = 0, y = 0, z = 40.0 }, { inAir = true })
        t.assert(mock.lastVelocitySet() ~= nil, 'guard did not resume')
    end)

    t.check('the suppress event works too', function()
        load()
        TriggerEvent('esx_launchguard:suppress', 2000)
        t.assert(exports['esx_launchguard']:IsSuppressed(), 'event did not suppress')
    end)

    t.check('incident count is exposed', function()
        load()
        t.equal(exports['esx_launchguard']:GetIncidentCount(), 0)
        frame(nil, { x = 0, y = 0, z = 40.0 }, { inAir = true })
        t.equal(exports['esx_launchguard']:GetIncidentCount(), 1)
    end)

    t.group('client: respawn handling')

    t.check('respawning is not treated as a launch', function()
        load()
        mock.ped.dead = true
        mock.ticks(30)
        -- Respawn: alive again, somewhere else entirely.
        mock.ped.dead = false
        frame({ x = 400.0, y = -900.0, z = 30.0 }, { x = 0, y = 0, z = 0.0 }, { inAir = false })
        mock.ticks(5)
        t.equal(#mock.serverEvents, 0, 'respawn reported as a launch')
        t.equal(#mock.log.coordSets, 0, 'respawn position was overwritten')
    end)

    t.check('a new ped handle resets history', function()
        load()
        mock.ped.handle = 42
        frame({ x = 800.0, y = 800.0, z = 80.0 }, { x = 0, y = 0, z = 0.0 })
        mock.ticks(5)
        t.equal(#mock.serverEvents, 0, 'ped change reported as a launch')
    end)

    t.group('client: ownership hardening')

    t.check('off by default', function()
        load()
        t.equal(#mock.log.migrateLocks, 0)
    end)

    t.check('locks migration when enabled', function()
        load { LockNetworkOwnership = true }
        t.assert(#mock.log.migrateLocks > 0, 'migration was not locked')
        t.equal(mock.log.migrateLocks[1].toggle, false)
        t.equal(mock.log.migrateLocks[1].netId, mock.ped.netId)
    end)

    t.group('client: missing natives degrade safely')

    t.check('an absent state native does not break the loop', function()
        local saved = IsPedVaulting
        IsPedVaulting = nil
        local ok, err = pcall(function()
            load()
            frame(nil, { x = 0, y = 0, z = 40.0 }, { inAir = true })
        end)
        IsPedVaulting = saved
        t.assert(ok, 'client errored without IsPedVaulting: ' .. tostring(err))
        t.assert(mock.lastVelocitySet() ~= nil, 'guard stopped working')
    end)
end
