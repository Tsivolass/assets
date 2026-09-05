-- Unit tests for the pure detection logic (no FiveM runtime involved).

return function(t, paths)
    dofile(paths.resource .. '/config.lua')
    local Detector = dofile(paths.resource .. '/shared/detector.lua')

    local FRAME = 1 / 60

    -- Feeds frames to a detector. Each step may override any field.
    local function newRig(overrides)
        local cfg = {}
        for k, v in pairs(Config) do cfg[k] = v end
        for k, v in pairs(overrides or {}) do cfg[k] = v end

        local rig = {
            cfg = cfg,
            now = 0,
            pos = { x = 0.0, y = 0.0, z = 30.0 },
            vel = { x = 0.0, y = 0.0, z = 0.0 },
            base = { grounded = true, dead = false, inVehicle = false,
                     aircraft = false, parachuting = false, swimming = false,
                     climbing = false, switchActive = false, suppressed = false },
        }
        rig.detector = Detector.new(cfg, 0)
        -- Skip the startup grace window unless a test wants it.
        rig.now = cfg.StartupGraceMs + 1

        function rig:step(over)
            over = over or {}
            self.now = self.now + (over.dtMs or (FRAME * 1000))
            local f = {
                now = self.now,
                dt  = (over.dtMs and over.dtMs / 1000) or FRAME,
                pos = over.pos or self.pos,
                vel = over.vel or self.vel,
            }
            for k, v in pairs(self.base) do f[k] = v end
            for k, v in pairs(over) do
                if k ~= 'pos' and k ~= 'vel' and k ~= 'dtMs' then f[k] = v end
            end
            self.pos, self.vel = f.pos, f.vel
            return self.detector:update(f)
        end

        -- Several seconds of standing still, so a safe position is stored.
        function rig:settle(frames)
            local last
            for _ = 1, (frames or 40) do last = self:step() end
            return last
        end

        return rig
    end

    t.group('detector: legitimate movement is never corrected')

    t.check('standing still', function()
        local rig = newRig()
        for _ = 1, 120 do
            t.assert(rig:step() == nil, 'idle frame flagged')
        end
    end)

    t.check('a normal jump', function()
        local rig = newRig()
        rig:settle()
        -- Jump: instant ~5 m/s up, then gravity brings it back down.
        local vz = 5.0
        for _ = 1, 60 do
            local action = rig:step {
                vel = { x = 0, y = 0, z = vz },
                pos = { x = 0, y = 0, z = rig.pos.z + vz * FRAME },
                grounded = false,
            }
            t.assert(action == nil, ('jump frame flagged at vz=%.2f'):format(vz))
            vz = vz - 9.81 * FRAME
        end
    end)

    t.check('a long fall, including the landing', function()
        local rig = newRig()
        rig:settle()
        local vz = 0.0
        for _ = 1, 120 do -- accelerate downward to terminal-ish speed
            vz = math.max(vz - 9.81 * FRAME, -45.0)
            local action = rig:step {
                vel = { x = 0, y = 0, z = vz },
                pos = { x = 0, y = 0, z = rig.pos.z + vz * FRAME },
                grounded = false,
            }
            t.assert(action == nil, ('falling frame flagged at vz=%.2f'):format(vz))
        end
        -- Landing: vertical velocity snaps from -45 to 0 in one frame. That
        -- is a +45 step, and must not read as a launch.
        local action = rig:step { vel = { x = 0, y = 0, z = 0.0 }, grounded = true }
        t.assert(action == nil, 'landing was treated as a launch')
    end)

    t.check('a ragdoll bounce off the ground', function()
        local rig = newRig()
        rig:settle()
        rig:step { vel = { x = 0, y = 0, z = -12.0 }, grounded = false }
        -- Bounce: -12 up to +6 in one frame (an 18 m/s step).
        local action = rig:step { vel = { x = 0, y = 0, z = 6.0 }, grounded = false }
        t.assert(action == nil, 'ragdoll bounce was treated as a launch')
    end)

    t.check('a car hitting a pedestrian', function()
        local rig = newRig()
        rig:settle()
        local action = rig:step { vel = { x = 8.0, y = 0, z = 9.0 }, grounded = false }
        t.assert(action == nil, 'car impact was treated as a launch')
    end)

    t.check('a frame hitch while sprinting', function()
        local rig = newRig()
        rig:settle()
        -- 400ms freeze, then the position catches up ~2.8m. Rate-based
        -- checks must not read that as a warp.
        local action = rig:step {
            dtMs = 400,
            pos = { x = 2.8, y = 0.0, z = rig.pos.z },
            vel = { x = 7.0, y = 0.0, z = 0.0 },
        }
        t.assert(action == nil, 'frame hitch was treated as a teleport')
    end)

    t.check('a vehicle launching off a ramp', function()
        local rig = newRig()
        rig:settle()
        local action = rig:step {
            vel = { x = 20.0, y = 0.0, z = 18.0 },
            inVehicle = true, grounded = false,
        }
        t.assert(action == nil, 'ramp jump in a vehicle was flagged')
    end)

    t.check('a jet climbing vertically', function()
        local rig = newRig()
        rig:settle()
        -- A Lazer in a vertical climb passes 80 m/s upward. Guarding that
        -- would fight normal flying.
        local action = rig:step {
            pos = { x = 0, y = 0, z = rig.pos.z + 1.5 },
            vel = { x = 0, y = 0, z = 90.0 },
            inVehicle = true, aircraft = true, grounded = false,
        }
        t.assert(action == nil, 'jet climb was treated as a launch')
    end)

    t.check('a helicopter climbing through a frame hitch', function()
        local rig = newRig()
        rig:settle()
        -- 300ms freeze while climbing at 25 m/s: 7.5m of position change
        -- in a single frame, which is legitimate at that frame time.
        local action = rig:step {
            dtMs = 300,
            pos = { x = 0, y = 0, z = rig.pos.z + 7.5 },
            vel = { x = 0, y = 0, z = 25.0 },
            inVehicle = true, grounded = false,
        }
        t.assert(action == nil, 'climbing through a lag spike was flagged')
    end)

    t.check('a car climbing a steep hill through a frame hitch', function()
        local rig = newRig()
        rig:settle()
        -- 250ms freeze at 20 m/s up a slope: 5m in one frame, on the
        -- ground the whole time.
        local action = rig:step {
            dtMs = 250,
            pos = { x = 0, y = 0, z = rig.pos.z + 5.0 },
            vel = { x = 15.0, y = 0, z = 8.0 },
            inVehicle = true,
        }
        t.assert(action == nil, 'hill climb through a lag spike was flagged')
    end)

    t.check('aircraft can be guarded if a server wants it', function()
        local rig = newRig { GuardInAircraft = true }
        rig:settle()
        local action = rig:step {
            vel = { x = 0, y = 0, z = 90.0 },
            inVehicle = true, aircraft = true, grounded = false,
        }
        t.assert(action ~= nil, 'GuardInAircraft = true was ignored')
    end)

    t.check('skydiving under a parachute', function()
        local rig = newRig()
        rig:settle()
        local action = rig:step {
            vel = { x = 0, y = 0, z = 40.0 },
            parachuting = true, grounded = false,
        }
        t.assert(action == nil, 'parachute state was flagged')
    end)

    t.check('a whitelisted script teleport (suppressed)', function()
        local rig = newRig()
        rig:settle()
        local action = rig:step {
            pos = { x = 1200.0, y = 800.0, z = 90.0 },
            suppressed = true,
        }
        t.assert(action == nil, 'suppressed teleport was flagged')
    end)

    t.check('the startup grace window', function()
        local rig = newRig()
        rig.now = 0
        local action = rig:step { vel = { x = 0, y = 0, z = 45.0 }, grounded = false }
        t.assert(action == nil, 'launch during startup grace was acted on')
    end)

    t.group('detector: launches are caught')

    t.check('a 100ft launch (24 m/s upward)', function()
        local rig = newRig()
        rig:settle()
        local action = rig:step { vel = { x = 0, y = 0, z = 24.0 }, grounded = false }
        t.assert(action ~= nil, 'launch not detected')
        t.equal(action.report.reason, 'vertical_speed')
        t.equal(action.clampVerticalTo, 0.0)
    end)

    t.check('an extreme launch (80 m/s)', function()
        local rig = newRig()
        rig:settle()
        local action = rig:step { vel = { x = 0, y = 0, z = 80.0 }, grounded = false }
        t.assert(action ~= nil and action.report.reason == 'vertical_speed')
    end)

    t.check('a moderate launch caught by the velocity step', function()
        local rig = newRig()
        rig:settle()
        -- Starts falling slowly, then a force leaves them rising at 13 m/s:
        -- under the absolute threshold, but a 16 m/s one-frame step.
        rig:step { vel = { x = 0, y = 0, z = -3.0 }, grounded = false }
        local action = rig:step { vel = { x = 0, y = 0, z = 13.0 }, grounded = false }
        t.assert(action ~= nil, 'stepped launch not detected')
        t.equal(action.report.reason, 'velocity_step')
    end)

    t.check('a launch during a lag spike is still caught', function()
        local rig = newRig()
        rig:settle()
        -- The velocity-step check stands down on long frames, so the
        -- absolute speed check has to carry this one.
        local action = rig:step {
            dtMs = 300,
            vel = { x = 0, y = 0, z = 40.0 },
            grounded = false,
        }
        t.assert(action ~= nil, 'launch during a lag spike was missed')
        t.equal(action.report.reason, 'vertical_speed')
    end)

    t.check('a coord-set launch during a lag spike is still caught', function()
        local rig = newRig()
        rig:settle()
        -- 60m up in 300ms is 200 m/s: far past what any frame time excuses.
        local action = rig:step {
            dtMs = 300,
            pos = { x = 0, y = 0, z = rig.pos.z + 60.0 },
            vel = { x = 0, y = 0, z = 0.0 },
            grounded = false,
        }
        t.assert(action ~= nil, 'coord-set launch during a lag spike was missed')
        t.equal(action.report.reason, 'position_jump')
    end)

    t.check('a straight coord set upward', function()
        local rig = newRig()
        rig:settle()
        local action = rig:step {
            pos = { x = 0.0, y = 0.0, z = rig.pos.z + 40.0 },
            vel = { x = 0, y = 0, z = 0.0 },
            grounded = false,
        }
        t.assert(action ~= nil, 'coord-set launch not detected')
        t.equal(action.report.reason, 'position_jump')
    end)

    t.check('a sideways warp', function()
        local rig = newRig()
        rig:settle()
        local action = rig:step {
            pos = { x = 300.0, y = 0.0, z = rig.pos.z },
            vel = { x = 0, y = 0, z = 0.0 },
        }
        t.assert(action ~= nil, 'sideways warp not detected')
        t.equal(action.report.reason, 'teleport')
    end)

    t.check('a launch while in a vehicle', function()
        local rig = newRig()
        rig:settle()
        local action = rig:step {
            vel = { x = 0, y = 0, z = 45.0 },
            inVehicle = true, grounded = false,
        }
        t.assert(action ~= nil, 'vehicle launch not detected')
        t.assert(action.report.inVehicle == true)
    end)

    t.check('vehicles can be exempted entirely', function()
        local rig = newRig { GuardInVehicle = false }
        rig:settle()
        local action = rig:step {
            vel = { x = 0, y = 0, z = 45.0 },
            inVehicle = true, grounded = false,
        }
        t.assert(action == nil, 'vehicle guarded despite GuardInVehicle = false')
    end)

    t.group('detector: correcting an incident')

    t.check('correction continues for the whole clamp window', function()
        local rig = newRig()
        rig:settle()
        rig:step { vel = { x = 0, y = 0, z = 30.0 }, grounded = false }
        -- Force removed, but the ped is still rising: keep clamping.
        local frames = 0
        for _ = 1, 60 do
            local action = rig:step { vel = { x = 0, y = 0, z = 1.0 }, grounded = false }
            if action then frames = frames + 1 end
        end
        t.assert(frames > 30, ('clamp window too short: %d frames'):format(frames))
    end)

    t.check('correction stops after the window', function()
        local rig = newRig()
        rig:settle()
        rig:step { vel = { x = 0, y = 0, z = 30.0 }, grounded = false }
        for _ = 1, 20 do rig:step { dtMs = 100, vel = { x = 0, y = 0, z = 0.0 } } end
        t.assert(rig:step() == nil, 'still correcting long after the incident')
    end)

    t.check('only one report per incident', function()
        local rig = newRig()
        rig:settle()
        local reports = 0
        for _ = 1, 40 do
            local action = rig:step { vel = { x = 0, y = 0, z = 30.0 }, grounded = false }
            if action and action.report then reports = reports + 1 end
        end
        t.equal(reports, 1)
    end)

    t.check('the player is put back once thrown clear', function()
        local rig = newRig()
        rig:settle()
        local ground = rig.pos.z
        local action = rig:step { vel = { x = 0, y = 0, z = 30.0 }, grounded = false }
        t.assert(action.restore == nil, 'restored before actually moving')

        action = rig:step {
            pos = { x = 0.0, y = 0.0, z = ground + 20.0 },
            vel = { x = 0, y = 0, z = 25.0 }, grounded = false,
        }
        t.assert(action.restore ~= nil, 'not restored after being thrown up')
        t.near(action.restore.z, ground, 0.5)
    end)

    t.check('no yank back from across the map', function()
        local rig = newRig()
        rig:settle()
        rig:step { vel = { x = 0, y = 0, z = 30.0 }, grounded = false }
        local action = rig:step {
            pos = { x = 0.0, y = 0.0, z = rig.pos.z + 400.0 },
            vel = { x = 0, y = 0, z = 25.0 }, grounded = false,
        }
        t.assert(action ~= nil and action.restore == nil,
            'restored from beyond MaxCorrectionDistance')
    end)

    t.check('the safe position is not poisoned mid-incident', function()
        local rig = newRig()
        rig:settle()
        local ground = rig.pos.z
        rig:step { vel = { x = 0, y = 0, z = 30.0 }, grounded = false }
        -- A cheat that keeps the victim "grounded" while lifting them must
        -- not get the safe spot updated to the new height.
        for _ = 1, 10 do
            rig:step {
                pos = { x = 0.0, y = 0.0, z = rig.pos.z + 2.0 },
                vel = { x = 0, y = 0, z = 25.0 }, grounded = true,
            }
        end
        local action = rig:step {
            pos = { x = 0.0, y = 0.0, z = ground + 25.0 },
            vel = { x = 0, y = 0, z = 25.0 }, grounded = false,
        }
        t.near(action.restore.z, ground, 0.5)
    end)

    t.check('reset clears history after a respawn', function()
        local rig = newRig()
        rig:settle()
        rig.detector:reset(rig.now, Config.RespawnGraceMs)
        local action = rig:step {
            pos = { x = 500.0, y = 500.0, z = 100.0 },
            vel = { x = 0, y = 0, z = 40.0 }, grounded = false,
        }
        t.assert(action == nil, 'respawn move was flagged as a launch')
    end)
end
