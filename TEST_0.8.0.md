# A-Life: Caravans — 0.8.0 Verification Report (2026-11-09)

## 1. Automated Simulation & Static Checks (`tools/run_test.py`)
- **Command:** `python -I tools/run_test.py`
- **Coverage:**
  - Kahlua syntax gate across all 24 runtime Lua files (`lupa` compile + static scan for forbidden `goto`, `::label::`).
  - `42/media/sandbox-options.txt` validation (0 `--` comments, all 37 `translation =` keys mapped in `Sandbox.json`).
  - Bilingual localization check across `EN` and `RU` (`IG_UI.json`, `UI.json`, `Sandbox.json`: identical key sets, non-empty UTF-8 strings, 0 `%` format characters).
  - Simulation suite (`tools/test_alc.lua` + `test_v070.lua`): **45 interaction checks + 451 simulation checks = 496 assertions passed (`TOTAL failed = 0`)**.
  - Verified `0.8.0` additions:
    - `ProjectALife.RadioReserved` frequency collision avoidance (`A.Radio.frequency()` steps past reserved frequencies; returns `101600` Hz / `101.6 MHz` when free).
    - `MinVehicles = 2` organized multi-car convoy selection for 4+ crew.
    - `ProjectALife.CarLifeServer.keepCar` and `ProjectALife.CarLife.eligible` hooks preventing A-Life 1.5.1 foot groups from hijacking or reserving tagged caravan vehicles.
    - `101.6 MHz` `radio_hail_caravan`, `radio_supply_drop` (5 packages), `radio_claim_drop` (with duplicate-payout receipt guard), and `radio_market_intel`.

## 2. Main Menu Engine Load Check (`tools/pz_loadcheck.py`)
- **Command:** `python -I tools/pz_loadcheck.py start && python -I tools/pz_loadcheck.py wait 90`
- **Mods enabled:** `ZombieBuddy`, `ProjectALifeNPCs` (1.5.1), `ALifeCaravans` (0.8.0)
- **Result:** `waited 14 s; mod lua seen: True` (`LOG : Lua f:0> [ALC] v0.8.0 client loaded`), `--- errors: 0` (exit code `0`).

## 3. Live In-Game Singleplayer Test on Project A-Life 1.5.1 (`tools/livetest/runs_080/20261109_101838`)
- **Environment:** Project Zomboid Build `42.21.0` isolated singleplayer Sandbox world (`Muldraugh, KY`, `10637, 10267, 0`) with `ProjectALifeNPCs` (1.5.1), `ALifeCaravans` (0.8.0), `ALifeReactiveSurvivors` (0.4.1 obsolete no-op), and `ALifeAirwaves` (0.1.1 obsolete no-op).
- **Verified Steps in `ALCLive080_result.txt` & `console.txt`:**
  1. `STEP 1 PASS`: Project A-Life 1.5.1 + `ALifeCaravans v0.8.0` booted (`[ALC] v0.8.0 installed (singleplayer)`, `CarLife hooks=true/true`); `ALifeReactiveSurvivors v0.4.1` and `ALifeAirwaves v0.1.1` safe no-op confirmed.
  2. `STEP 2a/2b PASS`: Multi-car convoy `caravan:2 Medical Staff Bravo-2` (`cars=2 crew=4`) founded and rendered on road at `10652.5, 10300.5` (`lead car=251`, parked brake released for NPC drive).
  3. `STEP 3 PASS`: Convoy hailed and authoritative trade deal completed (`trades=1`).
  4. `STEP 4 PASS`: `101.6 MHz` Radio Hail (`radio_hail_caravan`), Roadside Supply Drop (`pkg_medical` -> `5` item types claimed), and Regional Town Market Intel (`119` RoadGraph towns scanned) succeeded.
  5. `STEP 5 PASS`: `ALCRadioWindow` (`101.6 MHz Radio & Supply Dispatch`) opened in-game, rendered all 3 tabs (`101.6 MHz Airwaves`, `Supply Dispatch`, `Town Markets`), marked map coordinates, and closed with **0 mod Lua errors** (`errors=0`).

© 2026 druidqwerty. Released under the MIT License. Project A-Life by Vice.
