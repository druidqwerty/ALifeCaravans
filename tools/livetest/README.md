# Real-game audit extensions

These are development-only scripts, **not mod runtime files**. Do not install them
in an ordinary save or public server. They expect the separate isolated
Reactive live-test harness, its `ALRLive` fixture and one protected test player.

- `ALC_Audit.lua`: after a successful SOS, exercises production hail, barter,
  timed halt, departure, dismount and two-NPC reboarding. Runs in SP or on the server.
- `ALC_AuditClient.lua`: verifies the actual client inventory and trade window,
  empty-ground context menu and controller handlers. This is not a hardware test.
- `ALC_DriverDeath.lua`: inject on the isolated MP server only after the ordinary
  audit reports PASS. Deliberately kills the current NPC driver once through the
  game API, then observes an original survivor obtaining the matching key,
  taking seat 0 and driving the same car at least ten tiles.

The harness removes controlled ambush attackers and can reposition its protected
observer to keep terrain loaded. These observers do not force NPC seating or
vehicle motion. The death probe is destructive to its throwaway test NPC by design.
No harness, credentials, caches or save files are shipped in release archives.

See the repository's `TEST_0.5.0.md` for exact runs, boundaries and results.
