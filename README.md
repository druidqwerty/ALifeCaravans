# A-Life: Caravans [B42]

<p align="center"><a href="https://boosty.to/lrgpp"><img src="docs/banner.png" alt="LrgPP mods on Boosty" width="640"></a></p>

Faction caravans for [Project A-Life [ALIFE NPCS]](https://steamcommunity.com/sharedfiles/filedetails/?id=3803984183) by Vice. Far from players, convoys travel between towns in a persistent ledger; nearby, they become real cars with NPC drivers and passengers. Catch up, flag them down, trade, ride along or help them escape an ambush.

[Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3829571361) · [Source / releases (MIT)](https://github.com/druidqwerty/ALifeCaravans) · [Русский](README_RU.md)

Free and open source. The code is developed with AI; direction, testing and time are mine. [Support the mods on Boosty](https://boosty.to/lrgpp).

> **0.6.3 — major FPS and spawn performance optimization, shared collision-scene caching, and smoother chunk-boundary driving.** See [verification and limits](TEST_0.6.3.md).

## New in 0.6.3

- **Eliminated FPS drops when a convoy spawns or drives nearby.** Caravan obstacle scanning (`DrivingRoute.scene`) no longer iterates the entire cell's zombie list (`getCell():getZombieList()`) 50–120 times per second; instead, it reads active A-Life NPCs directly and shares cached collision tiles, edges and world bodies across all cars of the convoy.
- **Faster road scouting and unloaded-chunk guards.** `R.scout` now uses a binary min-heap with a 6 ms frame budget and zero closure allocations, `D.tryRender` and `R.siteNear` fast-fail before scanning 1,369 tiles when a caravan's ledger coordinate is still outside loaded chunks, route extensions are staggered to at most one car per tick, and local zombie threat checks pre-filter by bounding box.
- **Cleaner vehicle physics and frame-spike resilience.** Suppressed redundant `applyImpulseGeneric` calls on parked, coasting or physics-inactive vehicles (cutting native console log I/O spam), refreshed `checkSurroundingChunks()` across chunk boundaries so NPC-driven cars do not freeze into `isStatic` state, and clamped frame-hitch `dt` spikes so chunk loading or GC pauses do not trigger emergency brake/reset loops.

## New in 0.6.2

- **No more back-and-forth U-turn loops or sudden stalls on clear roads.** Road scouting now combines path cost and heading constraints, stops cleanly at unloaded chunk boundaries instead of detouring backward into loaded tiles, merges short tail stubs, and skips intermediate graph goals already passed or bypassed by road curves. Same-convoy vehicles and non-blocking roadside pedestrians no longer trigger reverse obstacle maneuvers, and convoy formation speed is no longer overwritten by upstream escape ticks.
- **Reliable parked-brake release and true stopped state.** Distant unloaded chunks no longer block local wheel-brake release at departure; when a caravan car parks or halts, a pure-Lua `parkBrake` step clears the controller's regulator gas state (`isGasPedalPressed() == false`) and engages parking brake force so parked cars do not creep and `BaseVehicle:isStopped()` is accurate.
- **Crews dismount for pinned combat and roadside stops, then re-board reliably.** When a caravan car is pinned by zombies (`>= 8s` without progress under contact), the crew dismounts to fight and automatically re-boards once clear. Roadside inspections, scavenging stops and friendly safehouse visits also dismount crews onto the road and queue immediate re-boarding on resume; cancelled approach walks retry automatically, and hailed caravans resume early if the player walks away.

## New in 0.6.1

- **No ZombieBuddy or Java agent installation required.** Caravans now handles singleplayer vehicle authority (`BaseVehicle:authorizationChanged`), save/reload physics wake (`checkSurroundingChunks` / `setPhysicsActive`) and parked wheel-brake release entirely in Lua (`06_ALC_Physics.lua`). The bundled `ALifeCaravans.jar` bridge and the `ZombieBuddy` dependency in `mod.info` have been removed.
- **Immediate physics preparation on spawn and reboarding.** Newly rendered and re-crewed caravan sessions prepare local vehicle physics as soon as the convoy entry is published, avoiding premature authority loss on the first client tick.
- **Vanilla car-crash NPE guard for seated NPCs.** In Build 42.21, `BaseVehicle.addRandomDamageFromCrash` assumes every seated passenger has a `BodyDamage` object, which is `null` on `IsoZombie`-backed A-Life NPCs. Seated bodiless crew now receive the engine crash-damage exemption while actively driving and clear it on release or exit.

## New in 0.6.0

- **Leave after arrival.** A new trip discards the previous route tail; restart trims already-reached/duplicate waypoints. Silent A-Life departure refusals are no longer counted as a successful start. This fixes a stationary-car loop reproduced with two clients.
- **Dead crews leave loot, not ghost caravans.** The director checks confirmed crew deaths even while parked or fighting. A fully defeated caravan loses its map marker, context actions and open trade/contact windows. Its physical cars, bodies and cargo remain. A missing/unloaded NPC is not considered dead; one surviving crew member keeps the caravan active. A car occupied by a player is not released until the player leaves.
- **React to nearby zombies.** Same-floor zombies close to the actual car prompt departure and real reboarding when necessary. The old wide-area horde stop is removed; a distant crowd no longer creates repeated three-minute stops. Active scripted ambush combat still has its own resolution. This uses the existing Living World setting.
- **Stop the error loop.** Safehouse inspection now calls the actual Build 42.21 square-based API. This fixes the repeated exception found in the supplied coop logs.
- **Roadside exchange and contact panels.** Item icons, separate searches, quantity controls, a persistent basket and clear cost/offer/balance feedback; resize and controller controls. A new contact panel groups convoy actions and shows live crew status and cargo. Optional Jeem Extension supplies its public colour palette; the layouts and code are original.

## What you can do

- **Meet faction convoys:** military, police, rescue crews, traders and raiders; named leaders and callsigns, 3–8 NPCs and up to four vehicles. Vehicle mods are considered through the loaded vehicle definitions; wrecks and trailers are excluded.
- **Find them on the map:** coloured car markers on the world map and minimap, with headings and callsigns. Marker visibility and labels are personal settings.
- **Flag them down:** right-click near a caravan, honk or flash headlights three times. Their response depends on stance. Ask for news, more waiting time or departure.
- **Barter:** cash or goods, faction-specific stock and favor-based prices. The world owner validates and exchanges the actual items; clients receive replicated inventory and a receipt. Equipped/favorite items, filled bags and loaded firearms are protected from sale.
- **Use a controller:** caravan context discovery is supported; in the trade window, A selects quantity, left/right switch columns, up/down select rows, X trades, Y clears and B closes. Split-screen interactions retain the initiating player's slot.
- **Ride or escort:** ask for a free seat or accept a destination escort contract. Cars carrying players are protected from routine removal. Ordinary escort contracts are separate from SOS rescue.
- **Answer SOS:** accept a friendly ambushed convoy's rescue, stay close and cover genuine NPC-driven escape. Defaults require 80 tiles and at least 30 seconds of movement; success awards +3 favor once. Accepting alone, offline ledger movement and teleport jumps do not earn the reward.
- **Face consequences:** threatening civilians can yield one item before they flee; military, police and raiders can fight. A paid raider toll grants a temporary truce. A-Life reputation and EN/RU radio/dialogue remain part of the encounter.

## Crews should return to their cars

A usable car is no longer treated as abandoned merely because its driving session ended or its crew stepped outside. The director watches for unexpected exits, lets crews regroup after combat, and retries real boarding when a body, door or network owner is temporarily unavailable. Surviving crew are allocated across cars without claiming the same NPC twice; an available survivor can replace a dead driver.

A replacement driver receives the vehicle key through A-Life's official key service. If that grant is temporarily unavailable, the existing session is preserved for retry instead of being released prematurely.

If A-Life removes a dead NPC passenger and ends its driving session, the surviving crew can reconnect around a seated player. Recovery requires confirmed crew death, matching NPC identities, an owned stopped vehicle and explicit mixed-seat permission; it never takes over a human driver's seat.

Temporary inspection/breakdown stops and roadside activity should finish with boarding and departure. Truly unusable cars or a dead crew can still leave a vehicle behind. Recovery uses A-Life's boarding and driving, not vehicle teleportation, and cannot guarantee passage through every physical obstruction.

Save/reload recovery also preserves a seated player instead of deadlocking the crew behind the occupied-car protection. It restores surviving NPC ownership, wakes parked native vehicle physics when needed and resumes genuine driving. Generated routes retain all their bounded goals (up to 61), instead of truncating the client's route at 40.

## Requirements and installation

- **Project Zomboid Build 42.21** and **Project A-Life 1.4.6** are the verified target for 0.6.3. Keep A-Life Driving enabled. Later dependency/game versions require their own verification.
- [Project A-Life [ALIFE NPCS]](https://steamcommunity.com/sharedfiles/filedetails/?id=3803984183).
- [A-Life: Factions Expanded](https://steamcommunity.com/sharedfiles/filedetails/?id=3813871509) is optional, but recommended for the full experience.
- [Project A-Life – Jeem Extension](https://steamcommunity.com/sharedfiles/filedetails/?id=3806944055) is optional, but recommended for the full experience; its public palette integrates with the new windows.
- Every player and the server need the same mod/dependency versions. Load `ProjectALifeNPCs;ALifeCaravans`, then restart after an update. No Java agent or `ZombieBuddy` installation is required. Use the published package's existing directory layout rather than mixing files from different releases.

## Settings and use

Host settings are under **Sandbox > A-Life: Caravans**; personal menu, notice and map settings are under **Options > Mods**. Defaults include five caravans, 35 km/h cruising, up to four cars, a 180-second hail stop and 120/200-tile appearance/release distances. Sandbox also controls ambush/SOS rules, event caravans, scavenging, inspection stops, refuelling, cargo, weather and other world activity. Features can be disabled independently.

Right-click within about 18 tiles of a caravan to interact. Trade and ride requests normally require it to stop first. A caravan waiting for unloaded terrain or retrying a blocked boarding path may remain stationary for a while; this is not by itself evidence that its crew has abandoned it.

## How the world simulation works

- **Distant travel is approximate.** The ledger follows A-Life's town/road graph and interpolates between graph points. A faraway map marker is not a recording of a physical car precisely following every road bend; it can appear to cross terrain between coarse nodes.
- **Nearby travel is physical.** Loaded road tiles supply local routes; A-Life drives actual vehicles with collision, formation, steering and boarding. Unloaded terrain and obstacles can make them wait.
- **The world owner controls records and inventory.** SP owns its world directly; an MP server owns the ledger and exchanges. A-Life assigns driving simulation to clients in multiplayer.
- **Compatibility is limited in scope.** Pure-Lua vehicle physics adapters (`06_ALC_Physics.lua`) handle the required NPC-vehicle compatibility, parked-body wake, brake release and seated crash-damage guard without any Java agent. The add-on does not redistribute A-Life source code. Persistent caravan records are reconciled with surviving cars and crews on load, including cars carrying a player.

## Verification

[0.6.3 current-source report](TEST_0.6.3.md). Earlier verification remains in [0.6.2](TEST_0.6.2.md), [0.6.1](TEST_0.6.1.md), two-client MP evidence in [0.6.0](TEST_0.6.0.md), and passenger save/reload and driver replacement evidence in [0.5.0](TEST_0.5.0.md).

Developer checks: `python tools/run_test.py` (442 assertions) and `python tools/pz_loadcheck.py`.

## Current limits

- At most four cars per convoy; no trailer towing.
- Distant markers follow the coarse graph, not exact road geometry. Physical driving requires loaded terrain.
- NPC recruitment and player-created caravans are **not shipped features**; incomplete commands refuse instead of removing crew or reporting a false success.
- SOS currently means covering an ambush escape, not repairing vehicles, treating NPCs or transporting refugees.
- Recovery uses real turning/reversing/replanning and is not necessarily immediate. Multi-client ownership handoff, combat balance, long rider journeys, extended sessions and vehicle-mod combinations need broader coverage.

## Credits

**Vice / Project A-Life:** NPCs, driving, arrivals, road graph, Knox County Radio and dialogue. **Minidoracat / MiniMap - AutoDrive for B42 (MIT):** studied for road-following, waypoint and stuck-recovery ideas; its code was not copied. Development uses AI assistance, with direction and testing by druid.

Jeem Extension and A-Life: Living Factions were studied and loaded in the joint compatibility lab. No third-party code or assets are bundled.

© 2026 druidqwerty. Released under the MIT License. Project A-Life by Vice.
