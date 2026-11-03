# Caravans 0.6.1 verification

## Scope and findings

Target: Project Zomboid 42.21, Project A-Life 1.4.6 (with Driving enabled).
Joint tests also load Reactive Survivors 0.4.0, Jeem Extension 0.7.5 and Living Factions 0.2.2.
Tests use isolated disposable worlds, not player saves. No upstream mod files are modified or redistributed.

Version 0.6.1 removes the bundled `ALifeCaravans.jar` native bridge and the `ZombieBuddy` requirement in `mod.info`.
All vehicle physics adapters in `42/media/lua/shared/ALifeCaravans/06_ALC_Physics.lua` now run in pure Lua:

- **Singleplayer local simulation (`F.acquireSP` / `F.releaseSP`):** calls `BaseVehicle:authorizationChanged(npc)` to lease local simulation to an offline caravan vehicle when its verified NPC driver is seated or boarding within 40 tiles, and `BaseVehicle:authorizationChanged(nil)` on release when no player has taken over.
- **Singleplayer save/reload physics wake (`F.wakeSP`):** calls `BaseVehicle:checkSurroundingChunks()` and toggles `BaseVehicle:setPhysicsActive(false)` / `setPhysicsActive(true)` once when a stationary driving session needs its Bullet body woken.
- **Parked wheel-brake release (`F.releaseBrake`):** clears residual Bullet wheel braking once at the start of an active NPC drive via a zero-power regulator step (`setBrakingForce(0)`, `setBraking(false)`, `setEngineFeature(quality, loudness, 0)`, `setRegulator(true)`, `updatePhysics()`). Because `CarController.update()` in Build 42.21 calls `getDriver().getMoodles().getMoodleLevel(MoodleType.DRUNK)` and `IsoZombie`-backed A-Life NPCs have `getMoodles() == null`, `F.releaseBrake` temporarily clears seat 0 (`clearPassenger(0)`) for the synchronous `updatePhysics()` call and immediately restores the driver via `enterRSync(0, driver, v)`.
- **Immediate physics preparation (`04_ALC_Convoy.lua`):** `C.setKnown` prepares physics immediately when a rendered caravan entry is published on the driving side.
- **Vanilla crash-damage NPE guard (`F.syncCrashGuard`):** in Build 42.21, `BaseVehicle.addRandomDamageFromCrash` calls `IsoGameCharacter.getBodyDamage().getBodyPart(...)`, which throws `NullPointerException` on `IsoZombie` passengers (`getBodyDamage() == null`) when `PlayerDamageFromCrash` is enabled unless `isGodMod()` is true. Seated bodiless NPC crew receive `setGodMod(true, true)` while actively driving and clear it (`setGodMod(false, true)`) when stopped, exiting or released.

## Automated checks

- `python tools/run_test.py`: **416 assertions passed** (`371 core + 45 interaction`, `TOTAL failed = 0`).
- `python tools/pz_loadcheck.py`: launches Project Zomboid 42.21 with `-mods=ProjectALifeNPCs;ALifeCaravans` (without `ZombieBuddy`), verifies that `42/mod.info` has no `ZombieBuddy` requirement and no `.jar` exists under `42/` or `common/`, and confirms clean main-menu load.

## Real-game evidence

Isolated singleplayer runs with Project A-Life 1.4.6, Reactive Survivors 0.4.0, Jeem Extension 0.7.5 and Living Factions 0.2.2:

- **Run `20261104_011856`:**
  - **SOS:** `PASS real convoy escape 124.13 tiles/30168ms; favor +3 once; duplicate denied`
  - **Caravan audit:** `PASS hail/trade/UI/timed stop; actual on-foot crew reboarded and drove 10.34 tiles`
- **Run `20261104_014513` (with the unseated `updatePhysics()` brake-release refinement):**
  - **SOS:** `PASS real convoy escape 106.92 tiles/30333ms; favor +3 once; duplicate denied`
  - **Brake release & post-trade departure:** `[ALC] car 254 parked brake released for NPC drive` succeeded with zero Java/Lua exceptions; after the hail/trade stop, Car 254 resumed driving and covered 26.53 tiles across two waypoints.

Raw scenario evidence: [live-0.6.1.txt](docs/live-0.6.1.txt). Two-client MP evidence from [0.6.0](TEST_0.6.0.md) and save/reload passenger evidence from [0.5.0](TEST_0.5.0.md) remain historical references.

## Limits

Nearby movement remains physical: blocked doors, wrecks and unloaded terrain can delay or prevent departure. Distant markers interpolate a coarse graph, not exact road geometry. Arbitrary vehicle packs, long-session authority churn, split-screen hardware and physical gamepads are not comprehensively certified.

## Source integrity

`docs/runtime-0.6.1.sha256` identifies all 25 release runtime files (pure Lua, translations, sandbox options and metadata; zero `.jar` files).

© 2026 druidqwerty. Released under the MIT License. Project A-Life by Vice.
