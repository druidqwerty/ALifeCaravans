# A-Life: Caravans 0.7.2 — Verification & Limits

## Automated Simulation Suite (`tools/run_test.py`)
- **486/486 assertions passed** (`441 core + 45 interaction`, `0 failed`).
- New v0.7.2 regressions covered:
  - Per-car home crew ownership (`ALC_Spawn.rememberCarCrew`, `homeCrewSet`, `reservedByOtherCars`, `ALC_Crew.tick`): follower cars (`Car 2`) never claim the lead car's (`Car 1`) driver or passengers while `Car 1` is an active convoy vehicle; `Car 1` retains and boards its own crew in convoy order.
  - Non-combat roadside dismount (`ALC_Spawn.dismount` + `ALC_Director.breakdownTick`): keeps each dismounted survivor's `arrivalObjective` at their own vehicle's coordinates rather than walking down the road to another vehicle in the convoy.
  - Convoy formation boarding hold (`04_ALC_Convoy.formationSpeed`) and friendly run-over protection (`VehicleRules.strike` hook): follower cars hold `speed = 0` while any car in the convoy is boarding or exiting, and caravan vehicles never run over caravan NPCs on foot.
  - `ArmoredVehicleChance` (`02_ALC_Vehicles.lua`): `0%` blocks armored/tactical vehicles (such as KI5 `M998` and `SWAT_Armored`) and selects unarmored fallbacks; `100%` allows full armored weight; default `25%` scales armored selection weights and enforces the probability check.
  - `TrophyVehicleCondition` (`ALC_Lifecycle.applyDefeatWear`): caps part condition, battery charge, and remaining fuel on caravan vehicles when their entire crew is wiped out (with an extra 25% battle-wear penalty on armored vehicles), idempotent per vehicle.

## Engine Load & Translation Verification (`tools/pz_loadcheck.py`)
- **Project Zomboid Build 42.21** + **Project A-Life 1.4.6**:
  - `42/media/sandbox-options.txt`, `42/media/lua/shared/Translate/EN/Sandbox.json`, and `RU/Sandbox.json` loaded with **0 translation or Lua errors**.

## Live Singleplayer Verification (`20261108_194640`)
- Isolated B42.21 world (`runs/20261108_194640`, `pid=35752`, `[ALC] v0.7.2 installed (singleplayer)`):
  - **SOS Rescue Escort:** `PASS real convoy escape 111.74 tiles/30134ms; favor +3 once; duplicate denied`
  - **Client UI & Authority Exchange:** `PASS client inventory matches authority; real trade UI; empty-ground menu; controller discovery/quantity/clear/close`
  - **Timed Stop & Departure:** `PASS distance=10.171875`
  - **Real On-Foot Crew Reboarding & Escape:** `PASS hail/trade/UI/timed stop; actual on-foot crew reboarded and drove 10.18 tiles`
  - **Mod Lua errors:** `0`

© 2026 druidqwerty. Released under the MIT License. Project A-Life by Vice.
