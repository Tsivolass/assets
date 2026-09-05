Config = {}

-- Cancels cheat launches that throw a player into the air, on the client of
-- the player being thrown. Nothing else: horizontal movement, teleports and
-- every other exploit are left alone.

-- Reference points for the thresholds below:
--   a normal jump leaves the ped at roughly  5 m/s upward
--   a hard car impact tops out around       10 m/s upward
--   a 30 m (100 ft) launch needs about      24 m/s upward
Config.MaxVerticalSpeed = 15.0  -- on foot: upward speed that cannot be legitimate
Config.MaxVerticalStep  = 10.0  -- one frame increase in upward velocity
Config.MinUpwardForStep = 10.0  -- the step only counts if still rising this fast
                                -- afterwards, so a hard landing is not a launch

-- Vehicles get airborne on ramps and hills, so they need more headroom.
Config.GuardInVehicle          = true
Config.VehicleMaxVerticalSpeed = 28.0
Config.VehicleMaxVerticalStep  = 22.0

-- Aircraft are left alone: a jet in a vertical climb passes 80 m/s upward, so
-- guarding them would fight normal flying rather than a cheat.
Config.GuardInAircraft = false

-- Being moved upward without the velocity to explain it, i.e. a coord set.
-- Rate based, so a lag spike on a slow client is not mistaken for one.
Config.MinVerticalPositionStep  = 3.0
Config.MaxVerticalPositionSpeed = 30.0

Config.MinFrameTime = 1 / 120

-- The one frame velocity step check is only meaningful on normal frames.
-- Above this frame time (10 fps) it stands down, because a lag spike
-- compresses normal acceleration into a single large step.
Config.MaxStepCheckFrameTime = 0.1

-- Launch force is usually applied over many frames, so corrections keep
-- running for a moment after the last one is seen.
Config.ClampWindowMs   = 750
Config.ClampVerticalTo = 0.0  -- upward velocity is capped here; falling is
                              -- never touched, so gravity still works

Config.RestorePosition       = true  -- put the player back if already thrown up
Config.RestoreHeight         = 6.0   -- only once this far above the safe spot
Config.MaxCorrectionDistance = 75.0  -- beyond this, just kill the upward
                                     -- velocity and let them fall
Config.ClearRagdollOnCorrect = true
Config.DetachOnCorrect       = true

Config.StartupGraceMs = 5000  -- ignore everything just after resource start
Config.RespawnGraceMs = 3000  -- and just after a respawn or ped change
Config.SafeSampleMs   = 250   -- how often the last known good spot is stored

Config.Debug = false
