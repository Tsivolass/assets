# esx_launchguard

Cancels cheat launches that throw players into the air, so the victim's
position never jumps and the anticheat has nothing to flag them for.

That is all it does. Horizontal shoves, downward slams, teleports and every
other exploit are deliberately out of scope and left untouched. It does not
ban, kick, log or report anything.

## How it works

A ped's position is authoritative on its owner's client. However the launch
is delivered (forced entity control, an invisible explosion, a punt object,
a coord set) the result passes through the victim's own physics before it
becomes a position anyone else sees. Cancelling it there means the jump
never happens.

It reacts to impossible upward motion rather than to any particular
exploit, so a new launcher menu needs no new patch here.

## Detection

Thresholds are built around these reference points:

| Motion | Upward speed |
|---|---|
| A normal jump | ~5 m/s |
| A hard car impact | ~10 m/s |
| A 30 m (100 ft) launch | ~24 m/s |

Three checks run per frame:

- **vertical_speed** — sustained upward speed past anything legitimate
  (15 m/s on foot, 28 in a vehicle).
- **velocity_step** — a one frame jump in upward velocity, counted only
  when the player is left genuinely rising afterwards, so a hard landing
  (falling fast, then stopped) is not mistaken for a launch. Stands down
  above 100 ms frame time, where a lag spike compresses normal
  acceleration into one large step.
- **position_jump** — moved upward faster than the velocity can explain,
  i.e. a coord set rather than a force. Rate based, so a lag spike on a
  slow client is not read as a launch.

Never touched: dead players, parachuting and free fall, swimming, climbing
and vaulting, player switches, aircraft, the seconds after a respawn or
resource start, and anything a resource has suppressed.

## Response

Upward velocity is capped. **Downward velocity is never touched**, so
gravity, falling and fall damage behave normally. If the player was already
thrown clear of their last known good position they are put back, ragdoll
is cleared and any attachment is broken. Corrections keep running for
`ClampWindowMs` because launch force is usually applied over many frames.

A player thrown further than `MaxCorrectionDistance` is not dragged back:
the upward velocity is killed and they fall normally, because yanking
someone across the map is its own anticheat trigger.

## Install

1. Copy `esx_launchguard` into your `resources` directory.
2. Add `ensure esx_launchguard` to `server.cfg`.
3. Restart.

Client side only. No server script, no database, no dependencies.

## Other resources that move players

Anything that legitimately teleports or launches a player upward should
stand the guard down for a moment:

```lua
exports['esx_launchguard']:SuppressFor(1500)  -- milliseconds
-- or, without a hard dependency:
TriggerEvent('esx_launchguard:suppress', 1500)
```

Also available: `IsSuppressed()` and `GetIncidentCount()`.

Worth wrapping admin teleports, job menus and interior scripts that move
someone upward. Without it the guard may pull the player back down, since
a scripted vertical teleport looks the same as a launch.

## Tuning

Everything is in `config.lua`. `GuardInVehicle` (on) gives vehicles much
higher thresholds, since ramps and hills are legitimate; turn it off if
your server does stunt work. `Config.Debug = true` prints every detection
to the client console.

## Notes

- Only protects players whose client runs this resource. It cannot protect
  someone with it blocked, and it does not stop a cheater launching
  themselves.
- Aircraft are exempt: a jet in a vertical climb passes 80 m/s upward, so
  guarding them would fight normal flying.
- If your anticheat flags `SetEntityCoords` or `SetEntityVelocity` from
  unknown resources, whitelist this one. If it already has its own launch
  protection, run one or the other, not both.
- A false correction is cheap by design: the worst case is a slightly less
  dramatic ragdoll after a big collision. A miss costs someone a ban, so
  the thresholds lean toward correcting.
