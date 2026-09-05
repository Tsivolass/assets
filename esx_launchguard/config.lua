Config = {}

-- ═══════════════════════════════════════════════════════════════════════
--  esx_launchguard
--
--  Stops modmenu users from launching other players into the air. The
--  victim's own client is where their ped position is authoritative, so
--  the correction happens there - which is why this works regardless of
--  how the launch was delivered (forced entity control, an invisible
--  explosion, a punt object, or a straight coord set).
--
--  This resource never bans, kicks or punishes anyone. It cancels the
--  launch and writes a log line so a moderator can tell a victim apart
--  from a cheater.
-- ═══════════════════════════════════════════════════════════════════════

-- ── Detection thresholds ───────────────────────────────────────────────
-- Reference points, so these numbers can be reasoned about:
--   a normal jump leaves the ped at roughly  5 m/s upward
--   a hard car impact tops out around       10 m/s upward
--   a 30 m (100 ft) launch needs about      24 m/s upward
Config.MaxVerticalSpeed  = 15.0  -- on foot: upward speed that can't be legitimate
Config.MaxVerticalStep   = 10.0  -- one-frame increase in upward velocity
Config.MinUpwardForStep  = 10.0  -- ...only counts if still rising this fast after
                                 --    (stops a hard landing counting as a launch)

-- Vehicles legitimately get airborne on ramps and hills, so they need
-- more headroom. Set GuardInVehicle = false to skip vehicles entirely.
Config.GuardInVehicle          = true
Config.VehicleMaxVerticalSpeed = 28.0
Config.VehicleMaxVerticalStep  = 22.0

-- Aircraft are exempt. A jet in a vertical climb passes 80 m/s upward,
-- far beyond any launch threshold, so guarding them would fight normal
-- flying rather than a cheat. Someone already flying is also not the
-- false-ban case this resource exists for.
Config.GuardInAircraft = false

-- Coord-set launches (position moves without the velocity to explain it).
-- Both are rate based, so a lag spike on a slow client is not mistaken
-- for a teleport.
Config.MinVerticalPositionStep  = 3.0    -- metres before the rate check applies
Config.MaxVerticalPositionSpeed = 30.0   -- m/s of upward position change
Config.MinTeleportStep          = 5.0    -- metres before the rate check applies
Config.MaxTeleportSpeed         = 120.0  -- m/s in any direction, on foot
Config.VehicleMaxTeleportSpeed  = 260.0  -- ...in a vehicle (aircraft are fast)

Config.MinFrameTime = 1 / 120 -- floor for frame time in rate maths

-- The one-frame velocity-step check is only meaningful on normal frames.
-- Above this frame time (10 fps) it stands down, because a lag spike
-- compresses normal acceleration into one big step. Absolute speed and
-- position checks keep working regardless.
Config.MaxStepCheckFrameTime = 0.1

-- ── Response ───────────────────────────────────────────────────────────
Config.ClampWindowMs   = 750   -- keep correcting for this long after a hit,
                               -- since force is usually applied repeatedly
Config.ClampVerticalTo = 0.0   -- upward velocity is capped here; falling is
                               -- never touched, so gravity still works

Config.RestorePosition      = true  -- put the player back if already thrown
Config.RestoreHeight        = 6.0   -- only once this far above the safe spot
Config.MaxCorrectionDistance = 75.0 -- beyond this, just kill the velocity and
                                    -- let them fall - yanking someone across
                                    -- the map is its own anticheat trigger
Config.ClearRagdollOnCorrect = true
Config.DetachOnCorrect       = true  -- break an attach used to carry them off

-- ── Timing ─────────────────────────────────────────────────────────────
Config.StartupGraceMs = 5000  -- ignore everything just after resource start
Config.RespawnGraceMs = 3000  -- ...and just after a respawn / ped change
Config.SafeSampleMs   = 250   -- how often the last known good spot is stored
Config.ReportCooldownMs = 5000 -- at most one report per this window

-- ── Reporting ──────────────────────────────────────────────────────────
Config.ReportToServer = true
Config.NotifyVictim   = true
Config.VictimMessage  = 'A launch attempt on you was blocked.'

-- ── Ownership hardening (optional) ─────────────────────────────────────
-- Asks the game not to hand your ped's network ownership to another
-- client, which blocks the "force control then apply force" route at the
-- source. Off by default: on some servers other resources legitimately
-- need to take control of a player ped, and this would fight them. Turn
-- it on, then test spawning, deaths and any carry/cuff/tow scripts.
Config.LockNetworkOwnership = false

-- ── Server side ────────────────────────────────────────────────────────
Config.Server = {
    ConsoleLog        = true,
    MaxReportsPerMin  = 6,      -- per player; extra reports are dropped
    NearbyRadius      = 150.0,  -- how far to look for who was next to the victim
    MaxSuspects       = 8,      -- most names listed per incident
    HistorySize       = 50,     -- incidents kept for /launchguard
    StaffAce          = 'launchguard.alerts', -- ACE permission for live alerts
    DiscordWebhook    = '',     -- optional; leave empty to disable
}

Config.Debug = false
