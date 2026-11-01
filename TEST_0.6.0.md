# Caravans 0.6.0 verification

## Scope and findings

Target: Project Zomboid 42.21, Project A-Life 1.4.6, ZombieBuddy 2.3.4 standard agent.
Joint tests also load Reactive Survivors 0.4.0, Jeem Extension 0.7.5 and Living Factions 0.2.2.
Tests use isolated disposable worlds, not player saves. No upstream mod files are modified or redistributed.

The supplied cooperative logs contained 21 invalid SafeHouse calls and six wide-area horde stops.
The old stop sampled crowds up to 50 tiles away and could park a convoy for three minutes.
These are concrete defects; unrelated MiniMapAutoDrive errors are not attributed to this mod.
Strict registry death now ends caravan interaction even when halted or fighting, while missing/dormant
actors do not prove death. Original vehicles, bodies and cargo remain; occupied vehicles retain their
bookkeeping until their human passenger exits normally.

Two further defects were reproduced during real two-client testing:

- After arrival, an old waypoint underneath the car survived into the new trip. A-Life silently refused
  departure because route points were too close. New trips discard stale route state, and restarted
  routes filter reached/duplicate points. A refused departure is no longer reported as successful.
- A-Life removes a dead passenger and ends the session but keeps the surviving crew binding. With a
  player aboard, recovery previously admitted only save-restored bindings. It now also accepts a
  verified death-cleanup binding, preserving the passenger and monotonic network revisions. It refuses
  moving/unloaded cars, human drivers, foreign occupants, stale actor generations and active handoffs.

## Automated checks

`python tools/run_test.py`: **413 assertions passed** (368 core + 45 interaction).
`python tools/test_native.py`: **36 boundary assertions passed**; shipped bridge binary unchanged.

Coverage includes lifecycle visibility and cleanup, forged interaction rejection, partial crew death,
occupied-car deferral, local threat filtering and ambush exclusions, stale route restart, passenger
recovery provenance and generation checks, item exchange rollback and client UI lifecycle.
These are simulation/boundary tests, not proof of all possible in-game behavior.

## Real-game evidence

SP run 043945 verified the unchanged lifecycle, threat and UI modules:

- SOS: 122.55 tiles / 30.232 seconds of genuine movement, one +3 reward.
- Real trade/inventory, empty-ground context and controller-handler smoke checks.
- Timed departure 10.16 tiles; both original NPCs reboarded and drove 10.14 tiles.
- Three nearby zombies: stop resumed and original car drove 8.06 tiles in 12.135 seconds.
- One crew death retained the caravan and displayed one living crew member.
- Full death removed marker, menu and open windows while preserving the physical car.
- Actual contact/trade/status windows visually inspected at 1024x640; search retained a hidden basket;
  trade window resize to 700x500 checked. Screenshots in `docs/ui-0.6.0-*.png`.

Later route and passenger-recovery changes require the final two-client run below; SP is not claimed
as an exact full-runtime certification. Earlier 0.5.0 true save/reload evidence remains historical.

### Final cold MP run 051825

A dedicated server and two actual EN/RU clients loaded the exact release runtime.
Jeem and Living Factions were loaded on all three sides. No production hotpatches.

- **SOS:** PASS real convoy escape 122.46 tiles/30711ms; favor +3 once; duplicate denied
- **Caravan audit:** PASS hail/trade/UI/timed stop; actual on-foot crew reboarded and drove 10.13 tiles
- **Joint caravan:** PASS two-client zombie departure, real passenger, replicated dead-crew cleanup, vanilla exit and original loot vehicle
- **Primary caravan client:** PASS replicated lifecycle, real windows, original car, normal passenger exit; primary=true
- **Observer caravan client:** PASS replicated lifecycle, real windows, original car, normal passenger exit; primary=false
- **Reactive server:** PASS natural owner-client make-space before contact, actual action movement and other-client replication
- **Reactive primary client:** PASS owner natural reaction at 5.739079263456493 tiles; actual make-space movement=1.028505777731297 action=running
- **Reactive observer client:** PASS spectator saw original actor move 0.9405594812431309 tiles

Reactive results listed above come from a separate fresh two-client run053850. Caravans runtime is identical;
Reactive received one later short-step arrival-tolerance change, verified in its own final SP/MP runs.


The SOS fixture scripts attacker clearance; its escape uses real NPC driving and physical movement.
The first ordinary-stop audit was interrupted by nearby zombies: emergency departure correctly
overrode the timer. That failed isolation attempt was archived, then the test observer was rerun
after clearing ordinary non-NPC threats within 35 tiles. Runtime code, car and crew were unchanged.
The subsequent audit checks actual inventory replication, timed departure and both original NPCs
walking back into the same car. Joint pressure deliberately kills an NPC passenger first, lets the
player board normally, then checks real departure with the surviving original crew.
The official boarding request was repeated after the server rejected an initial request while the
car was still rolling; no forced seat placement, deadline reset or production change was used.
Finally it kills all remaining crew, checks both clients, preserves the occupied car, and waits for vanilla player exit.
The RU trade UI was also visually inspected on a real MP observer client.

The fresh spectator had no preinitialized vanilla global context menu. Its test-only call to
`ISContextMenu.get` failed after marker/window cleanup already succeeded. The observer was corrected
to construct a real vanilla menu, and the same death case continued before its original deadline,
without another kill or runtime change. The initial observer failure remains in the evidence.

Raw scenario-only evidence: [live-0.6.0.txt](docs/live-0.6.0.txt). No private player logs are included.

## Limits

Nearby movement remains physical: blocked doors, wrecks and unloaded terrain can delay or prevent
departure. The response attempts a real escape, not guaranteed survival. Distant markers interpolate
a coarse graph, not exact road geometry. Arbitrary vehicle packs, long-session authority churn,
split-screen hardware and a physical gamepad are not comprehensively certified.

The previously collected public-comment snapshot contained all 11 comments and five complaint posts.
Refresh on 2026-11-01 at 02:14:44 UTC returned all 9 currently available comments (four complaint posts).
The only newly observed comment was the author's update announcement; there were no new complaint IDs.
The earlier deleted/unavailable posts remain part of the historical audit, not the current total.
Unspecified error reports without stacks are not automatically marked resolved. No public comment
was posted on the user's behalf. The source and release notes describe fixes, not a universal
"bug-free" guarantee.

## Source integrity

`docs/runtime-0.6.0.sha256` identifies release runtime files. Packaging verifies every runtime hash
against the cold two-client snapshot and every extracted ZIP byte against source. Private caches,
server credentials, player logs, upstream mods and test launchers are excluded from the release ZIP.
