# esx_pushvehicle

Push a stationary car or bike while on foot. Walk up to a bumper, a
prompt appears, and you can push and steer the vehicle by hand.

## Controls

| Key | Action |
|---|---|
| `Shift` + `F` | Start pushing (while standing at the front or rear bumper) |
| `W` | Push the vehicle away from you |
| `A` / `D` | Steer left / right while pushing |
| `F` | Stop pushing |

With no direction key held the vehicle is held in place, so it will not
roll away on a slope while you're braced against it.

`Shift` is required to start because `F` on its own is the game's
"Enter Vehicle" key — the resource also suppresses vehicle entry while
you're standing in the push zone, so `F` never puts you in the car by
accident. The key is rebindable in **Settings > Key Bindings > FiveM**.

## Behaviour

- The push zone is worked out from the vehicle's model dimensions, so it
  scales correctly from a compact to a van to a motorcycle without any
  per-model configuration.
- Only stationary vehicles with an empty driver seat can be pushed
  (both configurable). Boats, helicopters and planes are excluded.
- Force follows the vehicle's live heading, so a steered push curves
  instead of drifting sideways.
- Network control of the vehicle is taken before pushing, so the movement
  looks right for other players rather than only locally.
- A push ends cleanly on `F`, on death, if someone gets in the driver
  seat, if the vehicle is deleted, if it starts moving on its own, or if
  the resource stops.

## Install

1. Copy the `esx_pushvehicle` folder into your server's `resources`
   directory.
2. Add `ensure esx_pushvehicle` to `server.cfg`, after ESX.
3. Restart the server.

No database and no server-side script. ESX is used for notifications and
the closest-vehicle helper when present, with plain fallbacks otherwise.

## Configuration

All settings live in `config.lua`.

| Setting | Purpose |
|---|---|
| `KeyMapping.key` | Default physical key for the push command. |
| `MaxPushDistance` | Search radius for a nearby vehicle. |
| `PushZoneDepth` / `PushZoneInset` / `PushZoneHalfWidth` | Shape of the zone at each bumper where pushing is offered. |
| `MaxVehicleSpeed` | Vehicle must be slower than this to start a push. |
| `PushForce` | Push strength. Raise it if vehicles feel sluggish. |
| `MaxPushSpeed` | Force stops being applied at this speed. |
| `RunawaySpeedMargin` | How far past `MaxPushSpeed` before the push is released entirely. |
| `StationaryDamping` / `StationarySnapSpeed` | How hard the vehicle is held still when no key is held. |
| `SteerAngle` | Wheel angle applied by `A` / `D`. |
| `InvertSteer` | Flip if `A` / `D` feel reversed. |
| `AllowBikes` / `AllowCars` | Which vehicle classes can be pushed. |
| `RequireEmptyDriverSeat` | Block pushing an occupied vehicle. |
| `Anim.dict` / `Anim.name` | Push animation. If it can't be loaded the push still works, just without the clip. |
| `Debug` | Console logging of push start/stop reasons. |

## Tests

`tests/` contains a stub of the FiveM runtime that lets the client script
be executed and driven frame by frame outside the game, with simulated key
presses. It covers zone detection, class and driver filtering, push
direction for both bumpers and at arbitrary vehicle headings, steering,
holding position when idle, the speed cap, and every cancel path.

```
cd esx_pushvehicle
lua5.4 tests/run_tests.lua      # 51 assertions
luacheck .                      # lint (config included)
```

Physics feel — `PushForce`, `SteerAngle` and the damping values — is worth
a quick in-game pass to taste. If the console reports the animation
failing to load with `Debug` on, swap `Config.Anim` for another dictionary;
pushing itself is unaffected.
