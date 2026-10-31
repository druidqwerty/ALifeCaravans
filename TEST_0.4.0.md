# 0.4.0 verification — 2026-10-31

**Release status: EXPERIMENTAL GitHub pre-release.** Source/candidate version is 0.4.0;
Steam Workshop remains on 0.3.3. The complete live SOS escape gate is **BLOCKED**, not pending or passed.

## Automated checks

148 simulation assertions passed with the final two-argument Halo notification fix.
The suite includes the earlier caravan regressions and SOS ownership, acceptance without a reward,
physical movement/time gates, player-driven/dead-driver/dead-engine rejection, absence/timeout/hostility,
offline and missing-car failure, live disable, persisted terminal receipt and duplicate-reward rejection.
Lua parsing, EN/RU translation parity and Sandbox definitions also passed.

The B42.21 `HaloTextHelper.addText(IsoPlayer,String)` overload was verified against the actual game JAR
and vanilla usage; the first in-game run exposed the invalid earlier three-argument color call.
The simulation now uses a strict signature stub to prevent that regression.

## Controlled single-player scenario

Build42.21 with installed Project A-Life1.4.6. Real caravan car and two managed NPCs, four real ambush attackers.
The normal production ambush opened SOS. Acceptance succeeded and awarded no favor.
The fixture cleared attackers with the engine Kill call; this is not a test of player combat or balance.

The crew could not resume driving because A-Life's own boarding check rejected vehicle physics authority.
A separately created vanilla control car in the same SP world reported `isClient=false`, `isServer=false`,
vehicle authorization `Server`, and `isLocalPhysicSim=false`. The real game API explains that combination:
the latter helper is a multiplayer-authorization check, not a general SP-physics capability test.
A-Life uses it unconditionally in boarding, its private drive loop and restoration. No authorization flag,
base-game method or A-Life driving code was replaced to bypass the result.

After the normal convoy failure, SOS correctly failed with zero distance and no reward.
**This is not a successful SP rescue-escort verification.**
No SP boarding, driving or restoration compatibility fix is included in 0.4.0.

## Controlled local multiplayer scenario

A fresh localhost dedicated server and one actual client loaded the world and exchanged a real in-world
handshake. PZ 42.21.0, Project A-Life 1.4.6 and ZombieBuddy 2.3.4 were used. Production source snapshots
matched the repositories: 13 Reactive and 15 Caravans runtime Lua files. The notification fix was included,
with no repeated Halo overload error. Initial caravan 2/car 248 accepted SOS without favor but could not
make qualifying progress amid roadside obstacles and NPC blocking.

One final controlled road scene used an engine-validated paved/free 72-tile straight segment at
x=10588, y=10260..10332. Caravan 3/car 247 had two real managed NPCs. The normal ambush opened SOS;
acceptance changed `open` to `cover` without reward. The fixture cleared real attackers using engine Kill
calls, including client-owned bodies; this is not a combat-balance or player-input test.

Normal boarding and `escape` stages occurred. The server confirmed a matching managed driver, fuel 23.4
and a working/running engine. The client reported `auth=Local`, `active=true`, `static=false`; authority
was not forced. Navigation was braking with `clearance=0` because the other actual crew member remained
outside the vehicle at (10588.484, 10267.171). Driver and outside crew identities/generations were checked.

The observer stopped after its **180-second test cutoff**, reporting `FAIL escort timeout; state=escape`.
This was the harness cutoff, **not** expiry of the production SOS contract's default 10-minute deadline.
The final server snapshot was `state=escape distance=0 coveredMs=0 favor=0 receipt=nil`.
There were 79 position samples over 178.097 seconds with approximately 0.911 tile net drift, not qualifying
escape. **No successful escape, +3 favor payout, terminal success receipt or duplicate-payout rejection
was verified live.** No-award behavior was observed; a failed/expired contract receipt is not inferred.
Do not treat successful loading, boarding, the `escape` state label or simulated assertions as completed driving.

The live gate is **BLOCKED**. Both isolated client/server processes were stopped after cachedir identity
checks; logs and saves were retained. There is no later successful roadcase in the collected runs.

## Evidence and boundaries

Isolated test profiles, raw saves and installed third-party code are not release artifacts.
Local harness evidence resides in the sibling Reactive repository:

- `tools/livetest/runs/20261031_184701/` — SP control and SOS failure evidence.
- `tools/livetest/runs/20261031_185530/` — localhost MP scenario.

The MP run's `evidence.md` records the final verdict. `server/Lua/ALRLive_SOS_result.txt` contains all samples;
`server.out.log:3863` records the observer cutoff and line 3884 records the final zero-progress/no-receipt result.
`cache/console.txt:17410` records local active physics; lines 17411–17412 show the crew obstruction,
and lines 20183–20184 identify the seated driver and outside crew member.

The fixture controls attacker clearance and keeps its test player near the convoy to load chunks.
It never fabricates vehicle coordinates, driving distance or successful SOS receipts.
No claim of long-session, two-client ownership handoff, full trade/rider integration or map-icon visual coverage.
