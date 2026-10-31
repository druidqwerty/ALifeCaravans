# Caravans 0.5.0 verification

Status: **0.5.0 live verification gates passed**: SP checkpoint, final-source one-client dedicated MP audit, and separate real driver-death/replacement/departure probe. See the exact source boundary and coverage limits below.

## Environment and test boundaries

- Windows, Project Zomboid 42.21, Project A-Life 1.4.6, standard ZombieBuddy Java agent.
- Fresh isolated caches; no user saves changed. The test harness is excluded from the mod package.
- Real A-Life boarding, real vehicle physics and production caravan/inventory/reward code.
- Controlled test world: ambient encounters disabled, player protected, test attackers removed by script.
  Player repositioning keeps the scenario in loaded terrain; vehicle movement and crew seating are not forced.
- Tests of controller methods exercise the real UI handlers; they are not a physical-controller hardware test.
- Single-client MP coverage does not certify multi-client handoff, combat balance, every vehicle mod or long sessions.

## Automated regression checkpoint

317 base Lua assertions, 40 independent interaction assertions and 36 native boundary assertions passed:
**393 assertions, zero failures**. All production Lua files parsed; translation/sandbox consistency passed.

Covered invariants include actual/atomic inventory exchanges, forged/stale requests, persistent identities,
single-use rewards, occupied-car protection, physical arrival checks, all heading octants, bounded complete routes,
retry/reboard reservations, dead members versus temporarily missing bodies, replacement-driver key grants and
preservation of the existing session on grant failure, and native authority boundaries.

## Development evidence (not the final snapshot)

Run `20261031_212838`:

- SP SOS: 51.91 qualifying tiles / 36.266 seconds, +3 favor once, duplicate finish rejected.
- Actual barter: 20 currency removed, one bandage received; real trade UI and controller-method smoke passed.
- Timed stop followed by 10.03 tiles of driving.
- Independent dismount: both original NPCs returned and drove 10.16 tiles.
- World-map screenshot `game_214321.png`: physical caravan marker and callsign visible.
- Save/reload retained the nonce, original marked car, both crew UIDs, favor and SOS receipt. Car ID changed 254→253.
  Both NPCs reboarded, but the loaded car remained physically static. This failed the movement oracle and required
  a native activation correction before the final gate.
- A separate harness defect saved an empty active-mod list; the scripted New Game path had skipped vanilla's
  `ActiveMods.getById("currentGame"):copyFrom(ActiveMods.getById("default"))`. Fixed only in the test harness.

The development SOS used 40 tiles instead of default 80 and predates the new heading factory and final guard fixes.
It cannot be substituted for verification of the final release snapshot.

## SP checkpoint and final-source boundary

SP run `20261031_214702` (real game, not Lua simulation):

| Scenario | Observed result |
| --- | --- |
| SOS at the standard 80-tile setting | 90.08 qualifying tiles / 32.201 seconds; +3 favor once; duplicate rejected |
| Actual player passenger | Vanilla entry into seat 2; NPC-driven 10.81 tiles; occupied release/retire rejected |
| Normal save, process exit and reload | Same marked car (numeric ID 253→255), both original living NPC UIDs, favor and receipt retained |
| Player remains aboard during restoration | Same passenger seat 2, no exit/re-entry; NPCs boarded and drove 11.35 tiles |
| Normal player exit after restored travel | Vanilla exit action completed |
| Actual barter/UI | Currency−20, bandage+1; real window, empty-ground menu and controller handlers passed |
| Timed stop/departure | Physical departure 10.23 tiles |
| Separate unexpected crew exit | Both original NPCs reboarded; subsequent drive 10.52 tiles |

**Snapshot boundary:** the first process tested the factory/native fixes and passenger journey. With it stopped,
six files were cold-updated: Crew, Recovery, Spawn (restored passengers), Trade (optional method guards), EN/RU
sandbox labels (literal-percent formatting). The true reload, normal exit and complete trade/stop/reboard audit
ran on that cold snapshot (`20261031_215506`); no hot-patching. A later key-grant correction changes only
`ALC_Spawn.lua`, so **30 of 31 SP runtime files match the final freeze**, not all 31. The native JAR and spawn
factory are unchanged. This last correction was verified by the final-source MP driver-death probe below,
not by claiming that the earlier SP run contained it.
The earlier trade UI audit failed; final instrumented audit passed, with the sole observed close caused by its
own B-button test. No separate spontaneous-window-close fix is claimed.

Native JAR SHA256: `a38988b14fbed807e3d404b081e0f7d4b1b00bcb0a408ced3ef4f13af821972c`.
The world-map marker/callsign was also visually checked. Evidence: [passenger-reload video](docs/passenger-reload-0.5.0.mp4),
[frame](docs/passenger-reload-0.5.0.png), [release runtime manifest](docs/runtime-0.5.0.sha256),
and [final MP log extract](docs/live-mp-0.5.0.txt).

## MP diagnosis and completed final gates

Run `20261031_215915` did not pass: its original driver really died, and the surviving passenger promoted to
driver lacked the vehicle key. The resulting `ALC_Spawn.lua` correction validates the selected living NPC and
uses the official, idempotent `VehicleArrivalKeys.grant` before releasing the old driving session. A failed
grant now leaves that session intact for retry. Ten new automated checks cover this correction.

Fresh one-client dedicated MP run `20261031_220827`: **ordinary audit and separate driver-death probe PASS**. Both sides have identical 31-file final-source
snapshots. Only Caravans, its mandatory dependencies and the test harness are enabled (not Reactive Survivors).
The controlled ambush clears attackers at 500 ms instead of 3000 ms to preserve two crew for the ordinary audit;
this is not a combat-survival test. After the ordinary audit passed, a separate real `Kill(nil)` driver-death
probe exercised survivor promotion, key availability, actual boarding and physical departure.

Observed on the final source during the completed ordinary MP audit:

- SOS: **123.15 qualifying tiles / 30.908 seconds**, +3 favor exactly once; duplicate completion rejected.
- The car reached its actual first destination, observed the normal 60-second arrival stop, then resumed without
  intervention. The SOS movement-time condition completed after this natural continuation.
- Authority exchanged **20 currency for one bandage**; the client received the expected replicated inventory.
- The real trade window, empty-ground context and controller handlers passed.
- Timed halt followed by **10.022535 tiles** of real departure passed.
- Both original NPCs were observed on foot, then both actually seated; subsequent departure covered **10.69 tiles**.
  Departure took about 80 seconds after reboarding while the real driver turned, reversed and replanned. No motion
  or seating was forced and no error occurred. This is evidence of eventual recovery, not immediate departure.
- The separate real driver-death/replacement probe passed; details follow below.
- Root reran all 393 automated assertions successfully on this final source.

| Final-source live gate | Result |
| --- | --- |
| Dedicated MP SOS and single-use reward | **PASS: 123.15 tiles / 30.908 s; +3 once** |
| Dedicated MP authoritative trade/client inventory/UI | **PASS: −20 currency / +1 bandage** |
| Dedicated MP timed stop/departure | **PASS: 10.022535 tiles** |
| Dedicated MP independent reboarding/departure | **PASS: two original NPCs, 10.69 tiles** |
| Separate real driver-death/replacement/departure probe | **PASS: original survivor, matching key, same car, 10.06 tiles** |

## Deliberate real driver death: same-case proof

- The existing car was **246**. Original driver `palife:1793473810768:1` received exactly one real `Kill(nil)`.
  Its death event and authority registry death were confirmed by **581 ms**; the original UID/generation were latched.
- Original survivor `palife:1793473810974:2` was promoted to **seat 0**. Its actual inventory contained the matching
  vehicle key, ID **27936360**. The engine was running, and the **same car drove 10.06 tiles**. No new car or NPC
  was introduced to satisfy the test.
- **Observer correction, not a gameplay retry:** the first observer kept calling `isDead()` on the old Java body
  after the engine pooled/reset that object, despite the already-confirmed event/registry death. The observer was
  corrected to retain exact event plus registry UID/generation evidence and resumed the **same case** at about
  **134 seconds**. The original **180-second deadline** remained; there was no second kill or gameplay mutation.
- The reported **10.06 tiles were measured after the observer correction and matching-key validation**. PASS
  occurred at about **149 seconds**. All 31 runtime files remained unchanged throughout the final MP snapshot.

This proves the tested survivor/key/boarding/departure path, not instantaneous recovery in every road geometry.
Multi-client transfer, extended journeys, arbitrary third-party vehicles and combat balance need broader coverage.
