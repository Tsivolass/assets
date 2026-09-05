# esx_launchguard

Cancels modmenu "launch" attacks — the ones that fling a player a hundred
feet into the air — so the victim's position never jumps and the anticheat
never sees anything to flag them for.

It does not ban, kick or punish anyone. It cancels the launch and writes a
log line naming who was standing nearby, so a moderator can tell a victim
apart from a cheater.

## Why this works client side

A ped's position is authoritative on its owner's client. However the
launch is delivered — forced entity control, an invisible explosion, a
punt object, or a straight coord set — the result has to pass through the
victim's own physics before it becomes a position the server and the
anticheat see. Cancelling it there means it never becomes a suspicious
position in the first place.

That also means the protection is vector-agnostic: it reacts to impossible
motion, not to any particular exploit, so a new launcher menu doesn't need
a new patch here.

## What counts as a launch

Reference points the thresholds are built around:

| Motion | Upward speed |
|---|---|
| A normal jump | ~5 m/s |
| A hard car impact | ~10 m/s |
| A 30 m (100 ft) launch | ~24 m/s |

Four checks run per frame:

- **vertical_speed** — sustained upward speed past what any legitimate
  action produces (15 m/s on foot).
- **velocity_step** — a one-frame jump in upward velocity, only counted
  when the player is left genuinely rising afterwards, so a hard landing
  (falling fast, then stopped) is not mistaken for a launch. Stands down
  on frames longer than 100 ms, where a lag spike compresses normal
  acceleration into one large step.
- **position_jump** — moving upward faster than the velocity can explain:
  a coord set rather than a force.
- **teleport** — the same idea in any direction, for sideways warps.

The position checks are rate based, so a lag spike on a slow client is not
mistaken for a teleport.

Exempt at all times: dead players, parachuting and free fall, swimming,
climbing and vaulting, player switches, aircraft, the seconds after a
respawn or resource start, and anything a resource has suppressed.

## Response

Upward velocity is capped; **downward velocity is never touched**, so
gravity, falling and fall damage all behave normally. If the player has
already been thrown clear of their last known good position, they are put
back, ragdoll is cleared and any attachment is broken. Corrections keep
running for `ClampWindowMs` because launch force is usually applied
repeatedly over many frames.

A player thrown further than `MaxCorrectionDistance` is not dragged back —
velocity is killed and they fall normally. Yanking someone across the map
is its own anticheat trigger.

## Install

1. Copy `esx_launchguard` into your `resources` directory.
2. Add `ensure esx_launchguard` to `server.cfg`, after ESX.
3. Give your staff the alert permission, e.g.
   `add_ace group.admin launchguard.alerts allow`.
4. Restart.

## Using it with Waveshield

Two things worth checking on your setup:

- **Whitelist this resource** if Waveshield flags `SetEntityCoords` or
  `SetEntityVelocity` from resources it doesn't know. The correction is a
  legitimate write to your own ped, but an anticheat has no way to know
  that on its own.
- **Check for overlap.** If Waveshield already has its own launch or
  velocity protection, run one or the other, not both — two resources
  correcting the same ped in the same frame will fight each other.

This resource cannot see or change Waveshield's decisions. It reduces
false bans by stopping the position jump that causes them; it does not
undo bans that have already happened.

## Other resources that move players

Anything that legitimately teleports or launches a player should stand the
guard down for a moment:

```lua
exports['esx_launchguard']:SuppressFor(1500)  -- milliseconds
-- or, without a hard dependency:
TriggerEvent('esx_launchguard:suppress', 1500)
```

Also available: `IsSuppressed()` and `GetIncidentCount()`.

Normal ESX teleports (admin TP, job menus, interiors) are worth wrapping.
Without it the guard may pull the player back, since a scripted teleport
looks exactly like a warp.

## Moderator tools

- `/launchguard [count]` — recent blocked launches, newest last. Console,
  or players holding the `launchguard.alerts` ACE.
- Live in-game alerts to ACE holders as incidents happen.
- Optional Discord webhook (`Config.Server.DiscordWebhook`).

Every incident records the victim, their identifier, the detection that
fired, and the players who were near them — **suspect coordinates come
from the server**, so the reporting client cannot choose who gets named.

Reports arrive from clients, so a cheat could forge or spam them. They are
rate limited per player, type checked, clamped, and treated as a lead for a
human, never as proof.

## Tuning

Everything lives in `config.lua`. The two worth knowing:

- `GuardInVehicle` (default on) — vehicles get much higher thresholds
  since ramps and hills are legitimate. Turn off if your server does stunt
  work.
- `LockNetworkOwnership` (default **off**) — asks the game not to hand
  your ped's network ownership to another client, blocking the "force
  control, then apply force" route at the source. Off by default because
  some resources legitimately take control of player peds. If you turn it
  on, test spawning, deaths, and any carry, cuff or tow scripts first.

Set `Config.Debug = true` for console logging of every detection.

## Limits

- Only protects players whose client is running this resource. It cannot
  protect someone with the resource blocked, and it does not stop a
  cheater from launching themselves.
- Aircraft are exempt by default: a jet in a vertical climb passes 80 m/s,
  far beyond any launch threshold, so guarding them would fight normal
  flying.
- A false correction is deliberately cheap — the worst case is a slightly
  less dramatic ragdoll after a big collision. A miss costs someone a ban,
  so the thresholds lean toward correcting.
