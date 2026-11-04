# Caravans 0.6.2 verification

## Scope and findings

Target: Project Zomboid 42.21, Project A-Life 1.4.6 (with Driving enabled).
Joint tests also load Reactive Survivors 0.4.0, Jeem Extension 0.7.5 and Living Factions 0.2.2.
Tests use isolated disposable worlds, not player saves. No upstream mod files are modified or redistributed.

Version 0.6.2 addresses two player-reported issues on Steam Workshop:
1. Caravans oscillating back and forth, doing U-turns, sitting still, or moving very slowly on clear roads.
2. Crews rarely dismounting from their vehicles during stops or pinned zombie pressure, while needing reliable re-boarding afterward.

### Root causes and fixes

- **Road scouting & anti-U-turn guards (`03_ALC_Roads.lua`):**
  - `R.scout` now combines path cost `g` with heuristic `h` (`f = g * 0.35 + h` plus turn penalties) instead of pure greedy `h`, allowing routes to follow perpendicular roads before curving toward the goal.
  - Added `reversesRecentStep` (4-step / 16-tile window) and initial heading propagation (`root.dx`, `root.dy`) so `R.scout` cannot step across the width of a two-lane highway and make a 180-degree hairpin U-turn down the opposite lane.
  - Added `R.isLoaded(x, y)` chunk-boundary detection: when a step toward the goal reaches an unloaded map chunk (`getGridSquare == nil`), `R.scout` stops at the loaded edge instead of detouring backward into already-loaded chunks.
  - `R.compress` enforces minimum bend spacing (`minBendSpacing`) to eliminate 4-tile staircase zig-zags and merges short `<6`-tile final tail stubs into the preceding waypoint.
- **Forward goal progression & convoy driving (`04_ALC_Convoy.lua`, `ALC_Director.lua`, `ALC_Spawn.lua`):**
  - `C.goalFor` now scans ahead along the current leg (`lookLimit`) and checks segment projection (`passedGoal`), advancing `goalIndex` across any intermediate goals already passed or bypassed by road curves so cars never turn back to chase a goal behind them.
  - `S.render` aligns `caravan.goalIndex` with the chosen road site before scouting the initial spawn route.
  - `D.advance` refreshes `caravan.goals` during offline ledger travel so newly rendered caravans never inherit stale goals behind their spawn point; `D.planRoute` avoids immediately picking the previous town (`prevId`) when starting a new trip.
  - `C.tickOne` extends routes when `#s.route <= 3` and `tailDist <= 38` tiles, and `C.legFor` passes the tail segment heading to `R.scout`.
  - Wrapped `DrivingEscape.tick` (which previously overwrote convoy formation `cruiseSpeed` every tick), `DrivingRoute.scene` (filtering other cars of the same convoy and non-blocking roadside pedestrians so followers do not trigger reverse maneuvers against their own lead car), and `DrivingRecovery.driveStall` (preventing false stall-reverse triggers during startup on clear roads).
- **Pure-Lua brake release, parked-state reset & physics wake (`06_ALC_Physics.lua`):**
  - Removed the `isInvalidChunkAhead()` / `isInvalidChunkBehind()` guard from `F.releaseBrake`: in Build 42.21, `isInvalidChunkAround` checks 2 chunks away in velocity direction and could block local brake release near unloaded distant chunks.
  - Added a bounded stall retry when `driveAcceleration > 1.5` and `speed < 0.25 km/h` for 750ms, and marked `s.terrainWaiting = true` while `v:isPhysicsActive() == false`.
  - Added `F.parkBrake`: when a caravan car transitions from driving (`s.alcBrakeReleased == true`) to parked/halted (`s.phase ~= "driving"` or `entry.halted`), runs a synchronous `updatePhysics()` step with `setRegulator(false)` and `setRegulatorSpeed(0)` (temporarily unseating bodiless `IsoZombie` drivers just like `F.releaseBrake`). This clears `CarController.isGas` (`isGasPedalPressed() == false`) and engages `ControlState.NoControl` braking so parked cars do not creep and `BaseVehicle:isStopped()` returns `true`.
- **Balanced dismounts & reliable re-boarding (`ALC_Threats.lua`, `ALC_Director.lua`, `ALC_Crew.lua`, `04_ALC_Convoy.lua`):**
  - When a rendered caravan is pinned by a zombie swarm (`>= 8s` without progress under contact pressure), the crew dismounts (`c.state = "fighting"`, `A.Spawn.dismount`) to fight on foot and automatically re-boards once threats are cleared.
  - Roadside inspection (`D.breakdownTick`), scavenging (`D.scavengingTick`, when near players and safe), and friendly safehouse visits (`D.livingWorldTick`) dismount crews onto the road, and `D.resume` immediately queues `halt_resume` re-boarding when the stop ends.
  - If a player hails a caravan and walks away (`> 28` tiles for `30s`), the caravan resumes early instead of waiting out the full 180-second hail timer.
  - Wrapped `DrivingEntry.walked` to retry cancelled approach walks up to 3 times instead of aborting boarding.

## Automated checks

- `python tools/run_test.py`: **431 assertions passed** (`386 core + 45 interaction`, `TOTAL failed = 0`).
- `python tools/pz_loadcheck.py`: launches Project Zomboid 42.21 with `-mods=ProjectALifeNPCs;ALifeCaravans` (without `ZombieBuddy`), verifies that `42/mod.info` has no `ZombieBuddy` requirement and no `.jar` exists under `42/` or `common/`, and confirms clean main-menu load.

## Real-game evidence

Isolated singleplayer run `20261104_210709` with Project A-Life 1.4.6, Reactive Survivors 0.4.0, Jeem Extension 0.7.5 and Living Factions 0.2.2:

- **SOS (`cache/Lua/ALRLive_SOS_result.txt`):**
  `PASS real convoy escape 113.19 tiles/30167ms; favor +3 once; duplicate denied`
  Crew dismounted during ambush, re-boarded Car 254, released the parked brake in pure Lua, and drove straight down the highway (`x = 10588`, `y = 10266 -> 10397`) at up to `33.5 km/h` with zero U-turns or reverse oscillations across chunk boundaries.
- **Caravan audit (`cache/Lua/ALC_Audit_result.txt`):**
  `PASS hail/trade/UI/timed stop; actual on-foot crew reboarded and drove 10.62 tiles`
  Verified hail stop (`car:isStopped() == true` via `F.parkBrake`), authoritative trade (`money -20, bandages +1`), live Trade/Contact UI and controller handlers, timed halt/departure (`10.28` tiles), and on-foot dismount -> re-board (`seated=2`) -> departure (`10.62` tiles).

Raw scenario evidence: [live-0.6.2.txt](docs/live-0.6.2.txt). Two-client MP evidence from [0.6.0](TEST_0.6.0.md) and save/reload passenger evidence from [0.5.0](TEST_0.5.0.md) remain historical references.

## Limits

Nearby movement remains physical: blocked doors, wrecks and unloaded terrain can delay or prevent departure. Distant markers interpolate a coarse graph, not exact road geometry. Arbitrary vehicle packs, long-session authority churn, split-screen hardware and physical gamepads are not comprehensively certified.

## Source integrity

`docs/runtime-0.6.2.sha256` identifies all 37 release runtime files (pure Lua, translations, sandbox options and metadata; zero `.jar` files).

© 2026 druidqwerty. Released under the MIT License. Project A-Life by Vice.
