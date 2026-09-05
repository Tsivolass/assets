-- esx_launchguard/shared/detector.lua
--
-- Pure launch-detection logic: no natives, no globals beyond the export
-- below, so it can be reasoned about and tested in isolation.
--
-- The client samples the local player every frame and feeds a plain table
-- of numbers/booleans into Detector:update(). The detector decides whether
-- the motion is physically possible for a legitimate player, and returns
-- the correction to apply (if any). It never bans, kicks or reports on its
-- own - it only describes what it saw.

local Detector = {}
Detector.__index = Detector

local function copy3(v)
    return { x = v.x, y = v.y, z = v.z }
end

local function dist3(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function Detector.new(cfg, now)
    now = now or 0
    return setmetatable({
        cfg          = cfg,
        prev         = nil,
        safePos      = nil,
        safeAt       = 0,
        clampUntil   = 0,
        graceUntil   = now + cfg.StartupGraceMs,
        lastReportAt = nil,
        incidents    = 0,
    }, Detector)
end

-- Called when the ped is replaced (respawn, model change) so stale motion
-- history can't be compared against a brand new position.
function Detector:reset(now, graceMs)
    self.prev       = nil
    self.clampUntil = 0
    self.safePos    = nil
    self.graceUntil = now + (graceMs or self.cfg.RespawnGraceMs)
end

-- States where extreme vertical motion is legitimate, or where correcting
-- it would fight the game rather than a cheat.
function Detector:isExempt(f)
    local cfg = self.cfg
    if f.suppressed then return true, 'suppressed' end
    if f.dead then return true, 'dead' end
    if f.parachuting then return true, 'parachuting' end
    if f.swimming then return true, 'swimming' end
    if f.climbing then return true, 'climbing' end
    if f.switchActive then return true, 'switch' end
    if f.aircraft and not cfg.GuardInAircraft then return true, 'aircraft' end
    if f.inVehicle and not cfg.GuardInVehicle then return true, 'in_vehicle' end
    if f.now < self.graceUntil then return true, 'grace' end
    return false
end

function Detector:markSafe(f)
    local cfg = self.cfg
    if not self.safePos
        or (f.now - self.safeAt) >= cfg.SafeSampleMs
        or dist3(f.pos, self.safePos) > 1.0
    then
        self.safePos = copy3(f.pos)
        self.safeAt  = f.now
    end
end

-- Returns reason, magnitude for motion that no legitimate player can
-- produce, or nil when the frame looks normal.
function Detector:classify(f, prev)
    if not prev then return nil end

    local cfg = self.cfg
    local dt  = math.max(f.dt, cfg.MinFrameTime)

    local maxSpeed = f.inVehicle and cfg.VehicleMaxVerticalSpeed or cfg.MaxVerticalSpeed
    local maxStep  = f.inVehicle and cfg.VehicleMaxVerticalStep or cfg.MaxVerticalStep
    local maxWarp  = f.inVehicle and cfg.VehicleMaxTeleportSpeed or cfg.MaxTeleportSpeed

    -- Sustained upward speed. Nothing on foot climbs this fast.
    if f.vel.z > maxSpeed then
        return 'vertical_speed', f.vel.z
    end

    -- A one-frame jump in upward velocity. Landing also produces a large
    -- positive step (falling fast, then stopped), so this only counts when
    -- the player is left moving upward hard afterwards.
    --
    -- Skipped on long frames: during a lag spike, several hundred ms of
    -- perfectly normal acceleration (a helicopter spooling into a climb)
    -- arrives as a single large step. Launches during a spike are still
    -- caught by the absolute speed and position checks below.
    if f.dt <= cfg.MaxStepCheckFrameTime then
        local dvz = f.vel.z - prev.vel.z
        if dvz > maxStep and f.vel.z > cfg.MinUpwardForStep then
            return 'velocity_step', dvz
        end
    end

    -- Position moved up faster than the velocity could explain: a coord
    -- set rather than a force. Scaled by frame time so a lag spike on a
    -- slow client isn't mistaken for a launch.
    local dz = f.pos.z - prev.pos.z
    if dz > cfg.MinVerticalPositionStep and (dz / dt) > cfg.MaxVerticalPositionSpeed then
        return 'position_jump', dz
    end

    -- Same idea in any direction, to catch a sideways warp.
    local moved = dist3(f.pos, prev.pos)
    if moved > cfg.MinTeleportStep and (moved / dt) > maxWarp then
        return 'teleport', moved
    end

    return nil
end

-- One frame. Returns nil, or an action table:
--   clampVerticalTo : cap the ped's upward velocity at this value
--   restore         : coords to put the ped back to, when it was thrown far
--   report          : incident details, only on the first frame of an
--                     incident and at most once per ReportCooldownMs
function Detector:update(f)
    local cfg  = self.cfg
    local prev = self.prev
    self.prev = { pos = copy3(f.pos), vel = copy3(f.vel), now = f.now }

    if self:isExempt(f) then
        self.clampUntil = 0
        if f.grounded then self:markSafe(f) end
        return nil
    end

    local reason, magnitude = self:classify(f, prev)
    if reason then
        self.clampUntil = f.now + cfg.ClampWindowMs
    end

    -- Outside an active incident there is nothing to correct.
    if f.now >= self.clampUntil then
        if f.grounded then self:markSafe(f) end
        return nil
    end

    local action = { clampVerticalTo = cfg.ClampVerticalTo }

    if cfg.RestorePosition and self.safePos then
        local rise = f.pos.z - self.safePos.z
        local away = dist3(f.pos, self.safePos)
        if rise > cfg.RestoreHeight and away <= cfg.MaxCorrectionDistance then
            action.restore = copy3(self.safePos)
        end
    end

    if reason and (self.lastReportAt == nil or (f.now - self.lastReportAt) >= cfg.ReportCooldownMs) then
        self.lastReportAt = f.now
        self.incidents    = self.incidents + 1
        action.report = {
            reason      = reason,
            magnitude   = magnitude,
            verticalVel = f.vel.z,
            pos         = copy3(f.pos),
            rise        = self.safePos and (f.pos.z - self.safePos.z) or 0.0,
            inVehicle   = f.inVehicle and true or false,
        }
    end

    return action
end

-- FiveM loads this as a shared script; the tests dofile it. Both pick the
-- module up from this global.
LaunchDetector = Detector

return Detector
