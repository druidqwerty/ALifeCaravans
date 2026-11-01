# A-Life: Caravans [B42]

<p align="center"><a href="https://boosty.to/lrgpp"><img src="docs/banner.png" alt="LrgPP mods on Boosty" width="640"></a></p>

Faction caravans for [Project A-Life [ALIFE NPCS]](https://steamcommunity.com/sharedfiles/filedetails/?id=3803984183) by Vice. Far from players, convoys travel between towns in a persistent ledger; nearby, they become real cars with NPC drivers and passengers. Catch up, flag them down, trade, ride along or help them escape an ambush.

[Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3829571361) · [Source / releases (MIT)](https://github.com/druidqwerty/ALifeCaravans) · [Русский](README_RU.md)

Free and open source. The code is developed with AI; direction, testing and time are mine. [Support the mods on Boosty](https://boosty.to/lrgpp).

> **0.6.0 — living crews, clean defeat and a new roadside interface.** See [verification and limits](TEST_0.6.0.md).

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

- **Project Zomboid Build 42.21** and **Project A-Life 1.4.6** are the verified target for 0.6.0. Keep A-Life Driving enabled. Later dependency/game versions require their own verification.
- [ZombieBuddy](https://steamcommunity.com/sharedfiles/filedetails/?id=3619862853) **with its standard Java agent installed** on the client and server. Follow ZombieBuddy's installation instructions: subscribing alone is insufficient. Experimental mode is not required.
- [Project A-Life [ALIFE NPCS]](https://steamcommunity.com/sharedfiles/filedetails/?id=3803984183).
- [A-Life: Factions Expanded](https://steamcommunity.com/sharedfiles/filedetails/?id=3813871509) is optional, but recommended for the full experience.
- Every player and the server need the same mod/dependency versions. Load `ZombieBuddy;ProjectALifeNPCs;ALifeCaravans`, then restart after an update. Use the published package's existing directory layout rather than mixing files from different releases.

- [Project A-Life – Jeem Extension](https://steamcommunity.com/sharedfiles/filedetails/?id=3806944055) is optional, but recommended for the full experience; its public palette integrates with the new windows.

## Settings and use

Host settings are under **Sandbox > A-Life: Caravans**; personal menu, notice and map settings are under **Options > Mods**. Defaults include five caravans, 35 km/h cruising, up to four cars, a 180-second hail stop and 120/200-tile appearance/release distances. Sandbox also controls ambush/SOS rules, event caravans, scavenging, inspection stops, refuelling, cargo, weather and other world activity. Features can be disabled independently.

Right-click within about 18 tiles of a caravan to interact. Trade and ride requests normally require it to stop first. A caravan waiting for unloaded terrain or retrying a blocked boarding path may remain stationary for a while; this is not by itself evidence that its crew has abandoned it.

## How the world simulation works

- **Distant travel is approximate.** The ledger follows A-Life's town/road graph and interpolates between graph points. A faraway map marker is not a recording of a physical car precisely following every road bend; it can appear to cross terrain between coarse nodes.
- **Nearby travel is physical.** Loaded road tiles supply local routes; A-Life drives actual vehicles with collision, formation, steering and boarding. Unloaded terrain and obstacles can make them wait.
- **The world owner controls records and inventory.** SP owns its world directly; an MP server owns the ledger and exchanges. A-Life assigns driving simulation to clients in multiplayer.
- **Compatibility is limited in scope.** An original ZombieBuddy Java bridge handles the required NPC-vehicle compatibility, parked-body wake and brake paths. The add-on does not redistribute A-Life source code. Persistent caravan records are reconciled with surviving cars and crews on load, including cars carrying a player.

## Verification

[0.6.0 current-source report](TEST_0.6.0.md). Previous passenger save/reload and driver replacement evidence remains in [0.5.0](TEST_0.5.0.md); it is not presented as a new 0.6.0 run.

Developer checks: `python tools/run_test.py` and `python tools/test_native.py`.

## Current limits

- At most four cars per convoy; no trailer towing.
- Distant markers follow the coarse graph, not exact road geometry. Physical driving requires loaded terrain.
- NPC recruitment and player-created caravans are **not shipped features**; incomplete commands refuse instead of removing crew or reporting a false success.
- SOS currently means covering an ambush escape, not repairing vehicles, treating NPCs or transporting refugees.
- Recovery uses real turning/reversing/replanning and is not necessarily immediate. Multi-client ownership handoff, combat balance, long rider journeys, extended sessions and vehicle-mod combinations need broader coverage.

## Credits

**Vice / Project A-Life:** NPCs, driving, arrivals, road graph, Knox County Radio and dialogue. **Minidoracat / MiniMap - AutoDrive for B42 (MIT):** studied for road-following, waypoint and stuck-recovery ideas; its code was not copied. **ZombieBuddy:** Java integration. Development uses AI assistance, with direction and testing by druid.

Jeem Extension and A-Life: Living Factions were studied and loaded in the joint compatibility lab. No third-party code or assets are bundled.
