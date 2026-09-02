Config = {}

-- ── Key bind ────────────────────────────────────────────────────────────
-- Pushing starts with Shift + F: the command is bound to "F" by default and
-- only starts a push while the Sprint control (default LSHIFT) is held.
-- That keeps it clear of the vanilla "Enter Vehicle" action, which also
-- defaults to F. Pressing F again ends the push.
-- The key can be rebound in Settings > Key Bindings > FiveM.
Config.KeyMapping = {
    key = 'F',                 -- default physical key for the push command
    description = 'Push nearby vehicle (hold Shift)',
}

-- ── Detection ───────────────────────────────────────────────────────────
Config.MaxPushDistance   = 3.0   -- how far (meters) from the vehicle the search looks
Config.PushZoneDepth     = 1.15  -- how far beyond the bumper still counts as "behind/in front"
Config.PushZoneInset     = 0.25  -- allows standing slightly inside the bumper edge
Config.PushZoneHalfWidth = 0.75  -- max sideways offset (as a fraction of vehicle half-width)
Config.MaxVehicleSpeed   = 0.6   -- vehicle must be nearly stationary (m/s) to start pushing

Config.AllowBikes             = true   -- allow pushing motorcycles/bicycles
Config.AllowCars              = true   -- allow pushing cars
Config.RequireEmptyDriverSeat = true   -- vehicle must have no driver to be pushed

-- ── Push physics ────────────────────────────────────────────────────────
Config.PushForce           = 1.4  -- tune if vehicles feel too slow/fast to push
Config.MaxPushSpeed        = 2.2  -- stop adding force once the vehicle reaches this speed (m/s)
Config.RunawaySpeedMargin  = 0.5  -- above MaxPushSpeed + this, let go of the vehicle entirely

-- Holding position while no direction key is pressed.
Config.StationaryDamping    = 0.55 -- per-frame horizontal velocity multiplier (lower = harder stop)
Config.StationarySnapSpeed  = 0.12 -- below this speed (m/s) the vehicle is pinned outright

-- ── Steering ────────────────────────────────────────────────────────────
Config.SteerAngle  = 35.0   -- wheel angle (degrees) applied while holding A or D
Config.InvertSteer = false  -- flip if A/D feel reversed on your build

-- ── Animation ───────────────────────────────────────────────────────────
-- If this animation fails to load (missing/renamed in a game build) the
-- script automatically falls back to a physics-only push (no clip) instead
-- of breaking the feature, and logs a warning when Config.Debug is on.
Config.Anim = {
    dict = 'missfbi3ig_9',
    name = 'trev_pushes_floyd_car',
    loadTimeoutMs = 3000,
}

-- ── Text / notifications ───────────────────────────────────────────────
Config.HelpText        = '~y~Shift + F~s~ to push'
Config.HelpTextPushing = '~y~W~s~ push   ~y~A/D~s~ steer   ~y~F~s~ stop'

Config.Locales = {
    no_control        = 'You can\'t take control of this vehicle right now.',
    occupied          = 'Someone is driving, you can\'t push this vehicle.',
    too_fast          = 'The vehicle is moving, you can\'t push it.',
    anim_load_failed  = 'Animation failed to load, falling back to physics-only push.',
}

Config.Debug = false
