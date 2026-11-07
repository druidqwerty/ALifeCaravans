# Caravans 0.7.1 verification

## Scope and findings

Target: Project Zomboid 42.21, Project A-Life 1.4.6 (with Driving enabled).
Joint tests also load Reactive Survivors 0.4.0, Jeem Extension 0.7.5 and Living Factions 0.2.2.
Tests use isolated disposable worlds, not player saves. No upstream mod files are modified or redistributed.

Version 0.7.1 delivers a major content update (regional town supply & demand economy, 5 distinct special Event Caravans, physical trunk cargo + theft detection, and roadside repair/medical/vehicle/intel field services) together with four player-reported bug fixes from Steam Workshop comments (`@melixrism`, `@farleymarley1`, `@TreeasaurusRex`, `@Orion`, `@MiX74P3`).

### Bug fixes from Steam Workshop comments

### 0.7.1 Hotfix — Airtight `BaseVehicle.addRandomDamageFromCrash` NPE guard with *Collapse - Destructible Buildings* (`3831085225`)

- **Fixed `DrivingEntry.seated` -> `DrivingEntry.clear` stripping crash guard on departure (`04_ALC_Convoy.lua`, `06_ALC_Physics.lua`):**
  - Upstream `ProjectALife.DrivingEntry.seated(npc)` calls `DrivingEntry.clear(npc, true)` while `npc` is seated in the vehicle (both during `DrivingBoarding.seat` and in `DrivingEntryClient.entryTick` at the exact tick when `s.phase` transitions from `"readywait"` to `"driving"`).
  - In 0.7.0, the `DrivingEntry.clear` wrapper passed `v = nil, active = false` to `F.syncBodyCrashGuard`, which cleared `setGodMod(false, true)` on the seated driver right as the vehicle began driving (leaving up to a 250 ms unguarded window before the next `C.tick`, and permanently unguarded on MP servers or non-caravan `ProjectALife` vehicles).
  - `F.isSeatedInVehicle(body, v)` and `F.syncBodyCrashGuard(body, v, active)` now enforce the invariant that **as long as a bodiless NPC (`getBodyDamage() == nil`) is physically seated in any vehicle (`body:getVehicle() ~= nil` or occupying any seat in `v`), the crash guard stays `true` even if a caller passes `active = false` or `v = nil`**.
- **Fixed `F.releaseSP` / `F.ensureSP` `refuse()` and `S.releaseCar` clearing crash guard while crew is still aboard (`06_ALC_Physics.lua`, `ALC_Spawn.lua`):**
  - When `F.ensureSP` declined SP physics leasing (e.g. while one crew member was still walking to the car or when a session was suspended into `owner.sleeping`), `refuse()` called `F.releaseSP(v)` -> `F.syncCrashGuard(v, members, false)`, which stripped `godMod` from seated passengers still inside `v`. `F.ensureSP` and `F.syncBodyCrashGuard` now preserve the guard until each occupant has actually exited the vehicle, and `S.releaseCar` releases the session (`D.release`) before clearing occupant guards.
- **Immediate ejection + `setInvulnerable` fallback for dead bodiless occupants (`06_ALC_Physics.lua`, `08_ALC_Ballistics.lua`):**
  - In Build 42.21 bytecode, `BaseVehicle.damagePlayers(float)` does **not** check `chr.isDead()` (only `chr.isGodMod()`), and `IsoGameCharacter.setGodMod(true, true)` is a no-op when `this.isDead()` is `true`, whereas `setInvulnerable(true)` calls `setGodModCheat(true)` unconditionally. Furthermore, *Collapse*'s `hitCharacters` (`TilterWreck_Client.lua:464`) damages and knocks down `IsoZombie`s on vehicle squares with flying debris without checking `zed:getVehicle()`.
  - `F.syncBodyCrashGuard` now immediately ejects dead bodiless occupants from vehicle seats (`exitRSync` + `clearPassenger` + `setVehicle(nil)`), falls back to `setInvulnerable(true)` if a dead occupant remains in a seat, and clears knockdown states (`setKnockedDown(false)`) on living seated crew.
- **Direct `ProjectALife` & `TilterWreck` hooks + `Events.OnTick` cell vehicle guard (`04_ALC_Convoy.lua`, `06_ALC_Physics.lua`, `ALC_Spawn.lua`):**
  - Wrapped `DrivingEntry.seated`, `DrivingBoarding.seat`, `DrivingDemo.seat`, `DrivingProtection.sync`, and `VehicleArrivals.actorReady`, wrapped `TilterWreck.Vehicle.update` and `TilterWreck.Vehicle.pushBack` when *Collapse* is loaded, and added `F.guardCellVehicles` on `Events.OnTick` (every tick for active/known vehicles and every 150 ms across `getCell():getVehicles()`).

- **Crash fix with *Collapse - Destructible Buildings* (`@melixrism`, `06_ALC_Physics.lua`, `ALC_Spawn.lua`, `ALC_Director.lua`, `04_ALC_Convoy.lua`):**
  - In Build 42.21, `BaseVehicle.updatePhysics()` invokes `BaseVehicle.crash(float, boolean)` -> `addRandomDamageFromCrash(IsoGameCharacter, float)` on sudden velocity deltas (wall collisions or *Collapse*'s `applyImpulseFromHitObject` pushback), which calls `getBodyDamage().getBodyPart(...)` without a null check when `!isGodMod()`. Because `IsoZombie`-backed A-Life NPCs have `getBodyDamage() == null`, any unguarded seated NPC causes a `NullPointerException` in `IngameState.updateInternal`.
  - Previously, `F.syncCrashGuard` only set `setGodMod(true, true)` when `s.phase == "driving"` and `not s.braking` and `not entry.halted`, and only in Singleplayer. As soon as a caravan car braked before a wall, halted, slowed to dismount, or ran on an MP server, the guard was cleared while the NPC was still seated.
  - `F.syncVehicleOccupants` and `F.syncCrashGuard` now keep the crash guard active across all seated states (driving, braking, halted, boarding, and slowing to dismount) on both SP and MP server, and clear it immediately when an NPC exits the vehicle (`DrivingEntry.clear` / `releaseCar`).
- **Ballistic weapon damage against seated NPCs (`@farleymarley1`, `08_ALC_Ballistics.lua`, `ALC_Client.lua`, `ALC_Interact.lua`):**
  - Because `isGodMod() == true` is required while seated to prevent `BaseVehicle.addRandomDamageFromCrash` NPEs, vanilla firearm hit processing ignored bullets hitting seated NPCs.
  - `08_ALC_Ballistics.lua` detects player weapon attacks aimed at caravan vehicles (`Events.OnWeaponSwingHitPoint`), damages the seat's door/window first (`B.penetrateSeat`), applies penetrating firearm damage to the seated NPC (`B.onShot`), kills and ejects the NPC at zero health, and triggers `A.Interact.onAttacked` so surviving crew dismount to fight or flee.
- **Heavy tank & construction vehicle filter (`@TreeasaurusRex`, `02_ALC_Vehicles.lua`, `00_ALC_Core.lua`, `sandbox-options.txt`):**
  - Added `V.heavyArmorPatterns` (`Tank`, `T90`, `T-90`, `T72`, `T80`, `Abrams`, `BTR`, `BMP`, `APC`, `IFV`, `Artillery`, etc., plus `mass > 12000` kg) and excluded industrial construction vehicles (`Bulldozer`, `Excavator`, `Crane`, `Loader`, `Tractor`) in `V.badPatterns`.
  - Heavy armor is excluded from road convoys by default and gated behind the new `AllowHeavyArmor` Sandbox option (military class only).
- **Distant pedestrian & brake-stall fix (`@Orion`, `@MiX74P3`, `04_ALC_Convoy.lua`, `06_ALC_Physics.lua`):**
  - Reduced pedestrian obstacle distance in `C.fastScene` from 60 tiles to 14 tiles in the forward lane corridor (`along in [-1, 12]`, `across <= 1.15`) so distant *Jeem Extension* and *Living Factions* NPCs down the road do not freeze convoys.
  - Replaced the 3-attempt permanent cap on `F.releaseBrake` with periodic chunk wake (`checkSurroundingChunks` + `setPhysicsActive(true)`) and brake-release retries every 1.5 s while `driveAcceleration > 1.0` and `speed < 0.3 km/h`, improving compatibility with *Viewpoint* non-iso cameras.

### New content & features in 0.7.1

- **Regional town supply & demand economy (`07_ALC_Market.lua`, `ALC_Economy.lua`):**
  - RoadGraph towns maintain supplies across `medical`, `food`, `ammo`, `fuel`, and `tools`.
  - Convoys score candidate routes toward town shortages, attach a destination market snapshot (`caravan.market`), pay **+35% higher barter credit** for scarce destination goods, sell abundant goods at a **15% discount**, and settle remaining cargo into destination town reserves upon arrival (`A.metrics.deliveries`).
- **5 distinct Event Caravans (`trade_fair`, `medical_aid`, `supply_drop`, `refugees`, `scavenger_haul`):**
  - Unique stock pools, expanded item rows (`trade_fair` up to 12), buy/sell rate modifiers, event dialogue lines, world map badges, and bonus escort payouts (`supply_drop` +120 cash).
- **Physical trunk cargo & roadside field services (`ALC_Cargo.lua`, `ALC_ContactWindow.lua`, `ALC_Interact.lua`):**
  - `Cargo.populateCar` populates `TruckBed` / `Trunk` containers with physical items on spawn, and `Cargo.checkTheft` triggers caravan hostility if a player steals from a living caravan's trunk without trading.
  - New Convoy Contact Window and context-menu services: `assist_repair` (repair/refuel halted convoys for cash & `+2` favor), `field_aid` (medical treatment & bandaging), `donate_supplies` (relief donations for `+2..+3` favor & gift), `vehicle_service` (fuel top-up & engine patch for the player's nearby car), and `road_intel` (active convoy & SOS briefing).

## Automated checks

- `python tools/run_test.py`: **474 assertions passed** (`429 core + 45 interaction`, `TOTAL failed = 0`), including 27 new v0.7.1 regression and content checks in `tools/test_v070.lua`.
- `python tools/pz_loadcheck.py`: clean main-menu load (`0 errors`) with `-mods=ProjectALifeNPCs;ALifeCaravans` without `ZombieBuddy`.

## Real-game evidence

Isolated singleplayer run `20261107_235334` with Project A-Life 1.4.6, Reactive Survivors 0.4.0, Jeem Extension 0.7.5 and Living Factions 0.2.2:

- **SOS (`cache/Lua/ALRLive_SOS_result.txt`):**
  `PASS real convoy escape 117.75 tiles/30234ms; favor +3 once; duplicate denied`
- **Caravan audit (`cache/Lua/ALC_Audit_result.txt`):**
  `PASS hail/trade/UI/timed stop; actual on-foot crew reboarded and drove 10.61 tiles`
- **Client UI & controller audit (`cache/Lua/ALC_AuditClient_result.txt`):**
  `PASS client inventory matches authority; real trade UI; empty-ground menu; controller discovery/quantity/clear/close`
- **In-world counters (`cache/console.txt` at `f:6987`):**
  `founded=2 rendered=1 refused=0 released=0 retired=1 legs=7 halts=4 hails=1 trades=1 ... recrews=2 ... errors=0 ... deliveries=2`

Raw scenario evidence: [live-0.7.1.txt](docs/live-0.7.1.txt).

## Source integrity

`docs/runtime-0.7.1.sha256` identifies all 41 release runtime files (pure Lua, translations, sandbox options and metadata; zero `.jar` files).

© 2026 druidqwerty. Released under the MIT License. Project A-Life by Vice.
