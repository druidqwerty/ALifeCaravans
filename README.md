# A-Life: Caravans [B42] — test version

<p align="center"><img src="docs/preview.png" alt="A-Life: Caravans" width="320"></p>

An add-on for [Project A-Life [ALIFE NPCS]](https://steamcommunity.com/sharedfiles/filedetails/?id=3803984183) (by Vice):
faction caravans and convoys of up to four cars drive the roads between towns at low speed (35 km/h by default), so
you can catch up in your own car. Far from everyone they travel fast in a ledger and show on your map; near you they
are real cars with real crews. Flag them down, ask for news, barter goods, hitch a ride to their town, escort them for
a reward, pay a raider's toll, or threaten them and see what the faction does. Project A-Life itself is not changed
and none of its code is copied; this is a separate Lua mod built on A-Life's public NPC driving, arrival and speech
functions.

> **Test version 0.2.0.** The simulation suite (112 checks) passes and the mod loads and runs on a real dedicated
> server with A-Life (see "How it was tested"); it has not been played through a long session. It is out so players
> can test it: please report bugs (what the caravan did + your `Zomboid/console.txt`) in the Steam comments or the
> Issues here. Multiplayer hand-off and the trade window are the least tested parts.

**Steam Workshop:** https://steamcommunity.com/sharedfiles/filedetails/?id=3829571361 · **Source code (MIT):** https://github.com/druidqwerty/ALifeCaravans

<p align="center"><a href="https://boosty.to/lrgpp"><img src="docs/banner.png" alt="LrgPP mods on Boosty" width="640"></a></p>

Free and open source. The code is written by an AI; the direction, the testing and the time are mine. If the mod made your game better: [support on Boosty](https://boosty.to/lrgpp).

Русская версия: [README_RU.md](README_RU.md)

## What it does

- **Caravans on the roads.** Up to three caravans (Sandbox) exist at once. Each belongs to an A-Life faction and has a
  named leader with a convoy callsign ("Sgt. Miller, Bravo-3") and a crew of 3-6 NPCs in one to four cars. The faction
  decides the kind: soldiers run a **military convoy**, police a **patrol**, medics and firemen a **rescue crew**,
  workers and civilians a **trade caravan**, gangs and raiders a **raid** party. Military and police convoys take the
  maximum number of cars.
- **Town to town, fast when unseen.** A caravan travels A-Life's road graph from one town to another (2-4 legs), then
  picks the next town; after two trips it retires and a new one is founded. While nobody is near it travels in a
  ledger at 3x its cruising speed (Sandbox), slowing down to the cruising speed as a player comes within the appear
  distance, so it never pops or jumps. Within 100 tiles of a player it is put on the road for real: the cars appear on
  a free stretch of road at least 45 tiles away, the crew sits inside, and the convoy drives on at 35 km/h (soldiers 30,
  raiders 40). Beyond 170 tiles from every player it goes back into the ledger and continues its trip there.
- **On your map.** Every caravan, in the ledger or on the road, is a marker on the world map (M) and the minimap: a
  square in the colour of its kind, a heading tick, the callsign; a white ring when it is real, a dot when it waits.
  Positions update every few seconds and move smoothly. Each player can turn the markers off (Options > Mods).
- **Convoys keep formation.** Three or four cars are placed in two A-Life units, the second behind the first.
  Followers slow down and stop behind the car ahead; the leader slows for a straggler ("Close up!") and every car parks
  when the caravan is halted and leaves again a little after the car ahead.
- **Low speed on purpose.** You can catch up in any car, overtake, or block the road. A driver stuck behind you for a
  few seconds says so ("Clear the road!"). A convoy passing a player on foot tells them to stay off the road.
- **Flag them down.** Right-click near a caravan car (within 18 tiles): *[A-LIFE] Caravan: <faction> <callsign> (<kind>)*.
  Or honk within 30 tiles, or flash your headlights three times. Friendly and neutral crews pull over and wait
  2 minutes; careful ones refuse half the time; hostile factions tell you to get off the road, and raiders stop you for
  a **toll** instead.
- **Talk.** *Ask for news*: where they are going, what they saw on the road, rumours. *Ask them to wait*: up to two
  more minutes. *Let them go*: they drive on.
- **Barter.** A stopped non-hostile caravan opens a trade window: on the left what they sell with the price, on the
  right your goods with what they pay for them; click rows to add counts, the balance must be covered. Cash
  (Base.Money) or goods, everything has a value (ammo boxes, food, medical, tools, fuel, weapons, and by category for
  anything else). Stock by kind: traders carry a wide range; military convoys ammo, medical kits and rations; rescue
  crews medical supplies; patrols a little of everything; raiders stolen goods at a 50 % markup and pay half for
  yours. Stock refreshes every trip, and goods you sold are resold. Trades are server-authoritative: the server quotes
  and reserves, your game moves the items exactly once per transaction, the server commits or rolls back.
- **Favor.** Fair trades and escorts earn favor with the faction (-10..10, kept in the ledger): prices drop up to 20 %,
  careful crews start stopping for you, neutral ones become friendly. Threats and attacks cost favor and raise prices.
- **Hitch a ride.** A stopped friendly or neutral caravan lets you take a free seat (the normal "Enter vehicle" on
  the car) to its destination town. The caravan is never removed while a player sits in one of its cars; at the
  destination it pauses a minute ("end of the line for passengers") and you can get out or ride on.
- **Escort contracts.** Offer a friendly caravan an escort to its destination (menu). Stay within 70 tiles; leave for
  a minute and the contract is void. On arrival you are paid in cash or a valuable item from the stock, plus favor.
- **Ambushes.** With a player near, a horde or a raider gang (an outlaw A-Life faction) may wait on the road ahead
  (chance per trip, Sandbox). The convoy halts, the crew gets out and fights, and when the road is clear for ten
  seconds everyone boards again and drives on. Helping an escorted caravan through an ambush earns extra favor.
- **A new driver when one dies.** If the driver is killed (or any car's session ends), the survivors walk back to the
  car, a new driver takes the wheel and the convoy continues. Survivors are shared between the cars that need them.
- **Cars left behind.** A car out of fuel or with a dead engine, or one nobody can drive, is abandoned on the road
  (with whatever it carries); the crew goes on with the other cars, or on foot until the ledger takes them back.
- **Stuck recovery, no teleporting.** A car with no progress skips its waypoint, then parks and re-scouts the road
  from where it stands, then reports itself stuck; the director releases a stuck caravan to the ledger only when no
  player is within 60 tiles, never in front of you.
- **Threaten them.** Traders and civilians hand over an item and flee (15 km/h faster). Soldiers, police and
  raiders stop, dismount and fight. A threat is a provocation for A-Life's reputation and costs favor.
- **Attack them** (shoot or hit a crew member): traders flee, fighters dismount and return fire; A-Life's own
  reputation and grudges apply.
- **Raider toll.** A raider caravan that stops you demands 60 cash. *Pay the toll*: a 30-minute truce with that
  crew. Refuse or threaten them: they fight.
- **Radio chatter.** Convoys within 600 tiles of a player talk on A-Life's Knox County Radio frequency every five
  minutes: who they are, where they pass, where they are bound.
- **Speech lines in English and Russian** through A-Life's own speech bubbles (the driver answers).

Everything uses A-Life's own NPC driving: real cars with physics, road navigation, obstacle avoidance, reversing
when stuck, crews seated inside, and in multiplayer A-Life's hand-off of the car to the nearest player's game.

## Requirements

- Build 42.21+.
- [Project A-Life [ALIFE NPCS]](https://steamcommunity.com/sharedfiles/filedetails/?id=3803984183) 1.4.6+ with
  its "A-Life Driving" sandbox options enabled (the default).
- [A-Life: Factions Expanded](https://steamcommunity.com/sharedfiles/filedetails/?id=3813871509) is optional, but
  recommended for the full experience: more factions, more kinds of caravans.
- Every player, and the server, needs the mod.

Vehicle mods are supported: caravans pick cars from the game's vehicle zone lists (`VehicleZoneDistribution`,
which vehicle mods extend) by faction class — military, police, rescue, trade, raider, civilian — then by name
patterns over every loaded vehicle script, and fall back to any drivable script. Wrecks, trailers and scripts
without a passenger seat are skipped. Trailers are not towed (A-Life's driving does not tow).

## Installation

1. Subscribe, enable **A-Life: Caravans** in the mod list after Project A-Life, restart the game once.
2. On a server add `ALifeCaravans` to `Mods=` (after `ProjectALifeNPCs`).
3. Without Steam: unpack the zip to `%USERPROFILE%\Zomboid\mods\` (→ `mods\ALifeCaravans\42\mod.info`).
4. Updating from 0.1.0: saves are kept; the ledger is migrated (old stock, new fields) at the first start.

## Settings

All global settings are on the host's Sandbox page **A-Life: Caravans** (Host > Edit settings > Sandbox; an admin
can change them in a running game, they apply within 2 s): enable, caravans in the world (3), minutes between new
caravans (8), cruising speed (35 km/h), crew size (3-6), cars per caravan (3, up to 4), appear/disappear distances
(100/170 tiles), minimum spawn distance (45), ledger speed (300 %), trips before retiring (2), stop time (120 s),
horn/headlight hails, hostile caravans, riders, trade, escort contracts, ambush chance (25 %), radio chatter, abandon
dead cars, markers allowed, debug log. Personal options (Options > Mods > A-Life: Caravans): the right-click menu,
trade notices, markers on the world map, on the minimap, marker labels.

## Is it working?

`Zomboid/console.txt` has `[ALC] v0.2.0 installed (singleplayer|server|client)` after the world loads, then
`[ALC] founded caravan:1 <faction> <callsign> (...)` and `[ALC] on the road: caravan:1 ...` when one appears near
you, and a counters line every 5 minutes (`founded=… rendered=… hails=… trades=… recrews=…`). Open the map (M): the
caravans are the coloured squares with callsigns. With the Debug sandbox option on, every founding, rendering and
route step is logged. `ALifeCaravans.status()` in the Lua console prints the ledger.

## How it works (for modders)

- `shared/ALifeCaravans/00_ALC_Core.lua` — settings (SandboxVars polled every 2 s), helpers, counters.
- `01_ALC_Lines.lua` — speech catalog (`IGUI_ALC_<situation>_<n>`, EN/RU), said through `ProjectALife.Speech.say`.
- `02_ALC_Vehicles.lua` — generic vehicle choice (zone distributions → name patterns → any drivable script).
- `03_ALC_Roads.lua` — road scout: best-first search over loaded paved tiles (A-Life's `VehicleArrivalSites`
  road/link/space checks) from the car toward the next route goal, compressed to bends plus a point every ~14 tiles.
- `04_ALC_Convoy.lua` — the driving side: for every caravan session of `ProjectALife.DrivingDemoClient` it keeps
  formation (cruise speed from the gap to the car ahead, regroup for stragglers), appends the next stretch when the
  queue runs low, restarts a parked car, stops a halted one, runs the stuck ladder, says the "blocked"/"passing"
  lines, reports arrivals and stuck cars.
- `05_ALC_Trade.lua` — barter rules shared by server and client: item values, stock per kind, rates, favor, quotes,
  commits.
- `server/ALC_Ledger.lua` — the persistent ledger (`ProjectALife.Persistence.bucket("alc_caravans")`), favor, the
  schema migration.
- `server/ALC_Director.lua` — founding (factions via `FactionSpawnRules.pickList`, crews via
  `Catalog.weightedProfile`, routes via `RoadGraph`, named leaders), ledger travel with easing, render/release
  decisions (two units for 3-4 cars), re-crews, abandonment, stuck reports, escorts, the ambush state machine, radio
  chatter, trips, publishing cars and markers to the driving side (direct in single player, `ALifeCaravans/state`
  command in multiplayer).
- `server/ALC_Spawn.lua` — rendering through A-Life's own "arrive by car" pipeline (`DebugService.rawSpawn` with
  `arrival="ground"` → `VehicleArrivals`); wrappers of `VehicleArrivalSites.find` (our site and waypoints, seat lists
  trimmed so the crew is spread over the cars), `VehicleArrivalVehicle.create` (our vehicle script, car tagged),
  `DrivingLifecycle.create` (cruising speed), `VehicleArrivals.fallback`/`finished`; re-crewing through a boarding
  session (`DrivingLifecycle.create(..., boarding)`; suspended with a hand-off in multiplayer, the way A-Life does
  it); abandonment; ambush spawns (`spawnHorde`, or an outlaw faction through `rawSpawn`).
- `server/ALC_Interact.lua` — hail (menu/horn/flashes), news, trade/deal/dealDone with reservations, ride, wait,
  farewell, escort, threaten, toll, attack reactions (wraps `Reputation.onPlayerDamagedActor/onPlayerKilledActor`),
  stance from `Relations.playerStance` plus truce, anger and favor.
- `client/ALC_Client.lua` — context menu, the trade window, deal execution and gifts (the player's inventory is the
  client's), headlight-flash hails, server commands, personal options; `client/ALC_Map.lua` — markers on
  `ISWorldMap` and `ISMiniMapInner` (drawn after their render, like A-Life's squad overlay).

## How it was tested

- `python -I tools/run_test.py` — the lupa simulation (stubs of A-Life's driving/arrival/catalog/registry/speech/radio
  APIs and of the game): 112 checks over the whole lifecycle, every interaction, formation, stuck recovery, re-crewing,
  abandonment, ambushes, radio, riders, release, the 0.1.0 ledger migration, translations.
- `python -I tools/pz_loadcheck.py start` / `wait` — the real game at the main menu with A-Life and this mod: Lua,
  Sandbox page and translations load (this is how the Java-format `%` bug of 0.1.0 was found).
- `python -I tools/livetest/livetest.py start` / `wait` — a real dedicated server (no Steam) with A-Life, this mod and a
  test driver: the server founded caravans and ran the director for many minutes with no Lua errors (this is how the
  missing-`next` bug of Kahlua was found and fixed). The client part of the live test (a scripted player who flags a
  convoy down, trades, rides, and watches a re-crew) is included in `tools/livetest/` but the automated client stalled
  while joining the test server before the scenario could run, so those steps were **not** verified in a real world
  for 0.2.0; they are verified in the simulation only. See MODLOG.md for the details.

## Known limitations

- Test version: not played through a long session; multiplayer hand-off, the trade window and riders are the parts
  most likely to misbehave. Please report.
- Caravans only drive on loaded map: far from every player they travel in the ledger. If the road ahead is not loaded
  the car waits for it (A-Life's "waiting for terrain"), which can look like a stop.
- Four cars at most; the second A-Life unit is placed behind the first a couple of seconds later. No trailers.
- A caravan whose crew is wiped out is "stranded": the cars stay where they stopped, the ledger forgets it after
  30 minutes or when everyone is far.
- Speech bubbles come from the seated driver; the body does not turn toward you.

## Changelog

- 0.3.2 (2026-10-31) — removed Kahlua-unsupported `goto`/labels from the director (the file failed to compile at
  `ALC_Director.lua:1119`), and removed an unsupported comment from `sandbox-options.txt`. Added regressions for
  both engine-specific syntax checks. Verified with the offline suite and a real dedicated-server startup.
- 0.3.1 (2026-10-31) — fixed the Build 42.21 Java Set vehicle scan (no more right-click `Object tried to call nil`),
  repaired the interaction command chain, and added the missing English and Russian event speech lines.
- 0.2.0 (2026-10-29) — fast ledger travel with easing; map and minimap markers; convoys of up to four cars with
  formation; named leaders and callsigns; barter trade window, faction stock, favor; escort contracts and ambushes;
  re-crewing after a driver's death; abandoned cars; stuck recovery without teleports; radio chatter; headlight-flash
  hails; riders kept safe at arrival and on release; ledger migration from 0.1.0.
- 0.1.0 (2026-10-29) — first test version.

## Credits

- **Project A-Life [ALIFE NPCS]** by Vice — the NPCs, their driving (`ProjectALife.Driving*`), the "arrive by car"
  pipeline, the road graph, the Knox County Radio and the speech bubbles this add-on is built on. Nothing of it is
  copied or changed.
- **Minidoracat MiniMap - AutoDrive for B42** by Minidoracat (MIT, workshop 3792675881) — studied for its ideas on
  cruise-speed road following, queued waypoints and stuck recovery while designing the convoy logic. No code was
  copied; the driving in this add-on is A-Life's own.
- The code is written by an AI (Claude); the direction, testing and time are mine (druid).
