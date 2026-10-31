# 0.4.1 verification — controlled MP SOS passed

Verified on 2026-10-31. Scope: one-client dedicated-server multiplayer, not SP compatibility.

## Automated checks

180 simulation assertions pass, with Lua syntax, translation parity and Sandbox checks.
Three vehicle-selection cases prevent loaded trailers/wrecks from bypassing the drivable filter.
Eight new crew cases cover the seated-driver/on-foot-passenger quota bug, existing seat identities,
player/unrelated NPC seats and same-tick reservations across cars. Twenty-one new physics cases cover
known current sessions, actual crew identity/seating, local ownership, player exclusion, low speed,
engine/boarding/halt/exit guards, one-shot execution and restoration on bridge failure.

## Evidence collected before the clean candidate run

- Recrew-only MP run: both real NPCs boarded after the fix; the vehicle still barely moved.
  180-second observer cutoff failed, without a successful SOS payout.
- Separate diagnostic-only MP run: native controller inspection confirmed authorized local active physics.
  Clearing native parked wheel braking produced real movement and11.05 counted tiles/26429ms.
  A separate ambient NPC then blocked the turn. This was not a successful escort and not a release test.
- The shipping candidate uses its own small Java bridge loaded by standard ZombieBuddy, only for a
  verified current ALC-owned NPC drive. It restores the brake specification immediately. It does not
  move vehicles, fabricate velocity, grant network authority, replace the driving AI or lower reward gates.
- ZombieBuddy is now required. Its experimental `zbcall` API is deliberately not used.
- Run200003 exposed a separate selector bug: Base.Trailer_Livestock (zero seats) was accepted from
  vehicle distributions. The fallback validator is now consistent with the scanner's eligibility rules.
- The native diagnostic helper and all isolated caches are excluded from shipping artifacts.

## Clean candidate run

PZ42.21, A-Life1.4.6, ZombieBuddy2.3.4, one localhost dedicated server and one actual client.
Fresh cache,16 byte-identical production Lua files on server and client. Unrelated ambient NPC
welcome/encounters disabled and population reduced in test Sandbox settings to isolate the scenario.
Real ambush, real crew, scripted attacker deaths (not a combat balance test). Supported test Sandbox
escape distance40tiles; the required moving-time and exactly-once reward logic are unchanged.

Result: **PASS** in isolated run `20261031_200443`.

- Actual two-NPC crew created and confirmed seated by the client before the ambush.
- Real ambush opened SOS; accepting paid nothing. Nine spawned attackers were cleared by the fixture.
- Production recrew assigned both NPCs. Native parked-brake release ran normally; no diagnostic physics
  commands were used in this run. Read-only road queries were the only later test commands.
- The convoy moved, reached its first nearby stop, waited normally and resumed driving.
- Server observed **49.33 tiles / 30,799 ms** of qualifying movement, completed SOS and awarded **+3 favor**.
- Receipt existed; repeated completion and repeated acceptance did not issue another reward.
- All16 Lua files and the production JAR matched source bytes on both sides before testing.
  JAR SHA256: `f1c782503a2f2fa64c8cb73880eb71ff4dfa52c03d37043b223a6190fa3201ce`.
- Candidate runtime still printed0.4.0 during testing; the final0.4.1 bump changes only version metadata.
- No Caravans Lua exception was found. Vanilla map/animation and missing optional animation-directory
  warnings were present; this is not a claim that the entire game log was warning-free.
- Test processes were stopped by exact PID after evidence collection; user saves were untouched.

The fixture uses supported escape-distance40 rather than default80. The30-second gate, real-motion
checks, distance-from-origin requirement and reward protection were unchanged. This is not a manual
combat, multi-client or default-distance80 playthrough.

## Remaining coverage limits

SP authority compatibility is not changed. Multi-client handoff, long sessions and the full trade/rider
interaction path are not established by a one-client controlled SOS scenario. No claim of such coverage.
