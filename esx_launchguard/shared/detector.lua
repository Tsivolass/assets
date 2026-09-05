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
        cfg        = cfg,
        prev       = nil,
        safePos    = nil,
        safeAt     = 0,
        clampUntil = 0,
        graceUntil = now + cfg.StartupGraceMs,
        incidents  = 0,
    }, Detector)
end

function Detector:reset(now, graceMs)
    self.prev       = nil
    self.clampUntil = 0
    self.safePos    = nil
    self.graceUntil = now + (graceMs or self.cfg.RespawnGraceMs)
end

function Detector:isExempt(f)
    local cfg = self.cfg
    return f.suppressed
        or f.dead
        or f.parachuting
        or f.swimming
        or f.climbing
        or f.switchActive
        or (f.aircraft and not cfg.GuardInAircraft)
        or (f.inVehicle and not cfg.GuardInVehicle)
        or f.now < self.graceUntil
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

function Detector:classify(f, prev)
    if not prev then return nil end

    local cfg = self.cfg
    local dt  = math.max(f.dt, cfg.MinFrameTime)

    local maxSpeed = f.inVehicle and cfg.VehicleMaxVerticalSpeed or cfg.MaxVerticalSpeed
    local maxStep  = f.inVehicle and cfg.VehicleMaxVerticalStep or cfg.MaxVerticalStep

    if f.vel.z > maxSpeed then
        return 'vertical_speed', f.vel.z
    end


    if f.dt <= cfg.MaxStepCheckFrameTime then
        local dvz = f.vel.z - prev.vel.z
        if dvz > maxStep and f.vel.z > cfg.MinUpwardForStep then
            return 'velocity_step', dvz
        end
    end


    local dz = f.pos.z - prev.pos.z
    if dz > cfg.MinVerticalPositionStep and (dz / dt) > cfg.MaxVerticalPositionSpeed then
        return 'position_jump', dz
    end

    return nil
end

function Detector:update(f)
    local cfg  = self.cfg
    local prev = self.prev
    self.prev = { pos = copy3(f.pos), vel = copy3(f.vel) }

    if self:isExempt(f) then
        self.clampUntil = 0
        if f.grounded then self:markSafe(f) end
        return nil
    end

    local reason, magnitude = self:classify(f, prev)
    if reason then
        self.clampUntil = f.now + cfg.ClampWindowMs
    end

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

    if reason then
        self.incidents = self.incidents + 1
        action.detected = reason
        action.magnitude = magnitude
    end

    return action
end

LaunchDetector = Detector

return Detector
