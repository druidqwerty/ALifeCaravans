# Caravans 0.6.3 verification

## Scope and findings

Target: Project Zomboid 42.21, Project A-Life 1.4.6 (with Driving enabled).
Joint tests also load Reactive Survivors 0.4.0, Jeem Extension 0.7.5 and Living Factions 0.2.2.
Tests use isolated disposable worlds, not player saves. No upstream mod files are modified or redistributed.

Version 0.6.3 addresses player-reported FPS drops and stutters when a caravan spawns or drives nearby (`@Captain_Dick`).

### Root causes and fixes

- **Eliminated repeated full-cell `getZombieList()` scans in `DrivingRoute.scene` (`04_ALC_Convoy.lua`):**
  - Upstream `DrivingRoute.scene` iterated every zombie in `getCell():getZombieList()` (500–2,500+ zombies in towns) and called `getModData()` across the Kahlua–Java bridge 50–120+ times per second across a 4-car convoy just to locate active A-Life NPCs, while also rebuilding empty `squares` and `edges` tables on every call.
  - `C.fastScene` now builds the collision scene for caravan cars directly from `ProjectALife.Watchdog.bindings` / `Executor.executed` (with a 400 ms fallback cache if neither table is present), caches vehicle and pedestrian obstacle rows for 150 ms, and shares `scene.squares` and `scene.edges` across the convoy for 250 ms per floor `z`.
- **Binary min-heap, time budget, and unloaded-chunk fast-fail in road scouting (`03_ALC_Roads.lua`, `ALC_Director.lua`, `04_ALC_Convoy.lua`):**
  - Replaced `O(N^2)` linear search + `table.remove(open, bestIndex)` in `R.scout` with a FIFO-tie-breaking binary min-heap (`heapPush` / `heapPop`), bounded default `maxNodes` to 240 and wall-clock time to 6 ms, removed per-step closure allocations in `R.isLoaded`, and eliminated the duplicate fallback search pass by tracking `anyBest` in the single pass.
  - Added `R.areaLoaded(x, y, radius)` so `D.tryRender` and `R.siteNear` fast-fail in 1–5 checks when a caravan's ledger position is still outside loaded chunks, avoiding a 1,369-tile road scan and preventing false `renderFailures` penalties.
  - Staggered `C.legFor` in `04_ALC_Convoy.lua` (`C.scoutedThisTick`) so at most one car runs `R.scout` per convoy tick, and tuned per-car pathfinding budgets (`scanMs = 150`, `nodesPerTick = 16`, `searchBudgetMs = 2`, `maxNodes = 2400`, `horizon = 36`, `maxHorizon = 96`).
- **Bounding-box pre-filtering for local zombie checks and closure-free coordinate reads (`00_ALC_Core.lua`, `ALC_Threats.lua`, `ALC_Spawn.lua`):**
  - Removed per-call anonymous closure allocations in `A.xyz` and `A.vehicleTag`.
  - `A.Threats.scan` and `A.Spawn.zombiesNear` now filter zombies by `getX()` / `getY()` bounding box before calling `isDead()`, `getModData()` or `math.sqrt()`.
- **Suppressed idle/static `applyImpulseGeneric` spam, chunk-crossing physics wake, and frame-spike reset protection (`04_ALC_Convoy.lua`, `06_ALC_Physics.lua`):**
  - In Build 42.21, `BaseVehicle:applyImpulseGeneric` unconditionally formats and prints a debug line to `console.txt` / `DebugLog.txt` on every call. Wrapped `DrivingControl.apply` for caravan cars to skip impulses when the vehicle physics body is inactive (`isPhysicsActive() == false`), parked/waiting at rest (`speed < 0.08`), or coasting with near-zero acceleration, and to skip redundant rotational lever impulses when `|alpha| < 0.002`.
  - `F.wakeSP` now refreshes `v:checkSurroundingChunks()` every ~5.5 tiles of travel across chunk boundaries and wakes sleeping bodies even when `getCurrentSpeedKmHour()` retains a pre-sleep value, while `F.prepare` uses `s.alcPhysicsWaiting` instead of mutating `s.terrainWaiting` (eliminating `"Terrain wait ended"` log oscillation).
  - Wrapped `DrivingDemoClient.drive` to clamp `s.last` on frame hitches (`> 200 ms`) for caravan cars so a single frame spike from chunk loading or GC does not trigger `"Control update delayed"` emergency braking and route-reset loops.

## Automated checks

- `python tools/run_test.py`: **442 assertions passed** (`397 core + 45 interaction`, `TOTAL failed = 0`).
- `python tools/pz_loadcheck.py`: launches Project Zomboid 42.21 with `-mods=ProjectALifeNPCs;ALifeCaravans` (without `ZombieBuddy`), verifies that `42/mod.info` has no `ZombieBuddy` requirement and no `.jar` exists under `42/` or `common/`, and confirms clean main-menu load (`0 errors`).

## Real-game evidence

Isolated singleplayer run `20261106_033658` with Project A-Life 1.4.6, Reactive Survivors 0.4.0, Jeem Extension 0.7.5 and Living Factions 0.2.2:

- **SOS (`cache/Lua/ALRLive_SOS_result.txt`):**
  `PASS real convoy escape 140.60 tiles/30267ms; favor +3 once; duplicate denied`
- **Caravan audit (`cache/Lua/ALC_Audit_result.txt`):**
  `PASS hail/trade/UI/timed stop; actual on-foot crew reboarded and drove 10.01 tiles`
- **Performance & log telemetry (`cache/console.txt` vs 0.6.2 run `20261104_210709`):**
  - `applyImpulseGeneric!` log lines reduced by **32%** (`4616` vs `6762`), with **0** `isStatic: true` inactive-body impulse calls and **0** `Terrain wait ended` oscillations.
  - `[ALIFE-PERF]` cumulative cost at `f:3600` reduced by **51%** (`cost=49 max=1` vs `cost=101 max=2` in 0.6.2), with **0** caravan/driving hitches.

Raw scenario evidence: [live-0.6.3.txt](docs/live-0.6.3.txt). Two-client MP evidence from [0.6.0](TEST_0.6.0.md) and save/reload passenger evidence from [0.5.0](TEST_0.5.0.md) remain historical references.

## Limits

Nearby movement remains physical: blocked doors, wrecks and unloaded terrain can delay or prevent departure. Distant markers interpolate a coarse graph, not exact road geometry. Arbitrary vehicle packs, long-session authority churn, split-screen hardware and physical gamepads are not comprehensively certified.

## Source integrity

`docs/runtime-0.6.3.sha256` identifies all 37 release runtime files (pure Lua, translations, sandbox options and metadata; zero `.jar` files).

© 2026 druidqwerty. Released under the MIT License. Project A-Life by Vice.
