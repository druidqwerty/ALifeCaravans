-- Regression suite for DrivingLifecycle.create pre-flight guard (KahluaException
-- "A teammate is no longer loaded." at ALifeDrivingCrew.lua:55 / ALC_Spawn.lua:228),
-- S.recrew passenger revalidation & rollback, and VehicleArrivalVehicle.create varargs.
return function(check, newVehicle)
    local A, P = ALifeCaravans, ProjectALife
    local S, owner = A.Spawn, P.VehicleArrivals.owner()

    -- 1. DrivingLifecycle.create wrapper rejects unloaded/stale teammates BEFORE calling
    -- original (which would call DrivingCrew.attach -> error("A teammate is no longer loaded.")).
    local car = newVehicle("Base.CarNormal", 100, 100)
    local nonCaravanCar = newVehicle("Base.CarNormal", 104, 100)
    local c = { id = "create-guard-fixture", speedKmh = 35, x = 100, y = 100,
        vehicleIds = { car.id }, actorUids = {}, legPoints = { { x = 140, y = 100 } } }
    A.tagVehicle(car, c.id, 1)

    local d1 = newShell("cg-driver-1", "fixture")
    local p1 = newShell("cg-pass-1", "fixture")
    local p2 = newShell("cg-pass-2", "fixture")
    for _, npc in ipairs({ d1, p1, p2 }) do
        npc.x, npc.y = 100, 100
        SHELLS[npc.uid] = npc
        ACTORS[npc.uid] = { uid = npc.uid, generation = 1, revision = 1, lifecycle = "active", memory = {} }
    end
    c.actorUids = { d1.uid, p1.uid, p2.uid }

    -- Missing passenger on a caravan car returns (nil, reason) without invoking original.
    local beforeSessions = #CREATED_SESSIONS
    local s, why = P.DrivingLifecycle.create(owner, { player = PLAYER, route = { { x = 120, y = 100 } } }, car,
        { { uid = d1.uid, generation = 1, seat = 0 }, { uid = "cg-unloaded", generation = 1, seat = 1 } },
        "tok-missing-rider", { { x = 120, y = 100 } }, false)
    check("create guard defers missing caravan teammate without throwing",
        s == nil and why == "A teammate is no longer loaded." and #CREATED_SESSIONS == beforeSessions)

    -- Missing passenger on a NON-caravan car (e.g., CarLife/CarOffline/VehicleArrivals) also defers cleanly.
    s, why = P.DrivingLifecycle.create(owner, { player = PLAYER, route = { { x = 120, y = 100 } } }, nonCaravanCar,
        { { uid = d1.uid, generation = 1, seat = 0 }, { uid = p1.uid, generation = 99, seat = 1 } },
        "tok-stale-gen", { { x = 120, y = 100 } }, false)
    check("create guard defers stale-generation teammate on non-caravan car",
        s == nil and why == "A teammate is no longer loaded." and #CREATED_SESSIONS == beforeSessions)

    -- Missing driver returns (nil, reason) cleanly.
    s, why = P.DrivingLifecycle.create(owner, { player = PLAYER, route = { { x = 120, y = 100 } } }, car,
        { { uid = "cg-missing-driver", generation = 1, seat = 0 } },
        "tok-missing-driver", { { x = 120, y = 100 } }, false)
    check("create guard defers missing driver without throwing",
        s == nil and why == "The driver is no longer loaded." and #CREATED_SESSIONS == beforeSessions)

    -- Invalid / duplicate passenger seats defer cleanly instead of throwing in DrivingCrew.attach.
    s, why = P.DrivingLifecycle.create(owner, { player = PLAYER, route = { { x = 120, y = 100 } } }, car,
        { { uid = d1.uid, generation = 1, seat = 0 }, { uid = p1.uid, generation = 1, seat = 1 }, { uid = p2.uid, generation = 1, seat = 1 } },
        "tok-dup-seat", { { x = 120, y = 100 } }, false)
    check("create guard rejects duplicate passenger seat without throwing",
        s == nil and why == "Invalid or duplicate passenger seat." and #CREATED_SESSIONS == beforeSessions)

    s, why = P.DrivingLifecycle.create(owner, { player = PLAYER, route = { { x = 120, y = 100 } } }, car,
        { { uid = d1.uid, generation = 1, seat = 0 }, { uid = p1.uid, generation = 1, seat = 0 } },
        "tok-seat0-rider", { { x = 120, y = 100 } }, false)
    check("create guard rejects seat 0 rider without throwing",
        s == nil and why == "Invalid or duplicate passenger seat." and #CREATED_SESSIONS == beforeSessions)

    s, why = P.DrivingLifecycle.create(owner, { player = PLAYER, route = { { x = 120, y = 100 } } }, car,
        { { uid = d1.uid, generation = 1, seat = 0 }, { uid = d1.uid, generation = 1, seat = 1 } },
        "tok-dup-uid", { { x = 120, y = 100 } }, false)
    check("create guard rejects duplicate uid without throwing",
        s == nil and why == "Invalid or duplicate passenger seat." and #CREATED_SESSIONS == beforeSessions)

    -- Stale DrivingDemo.npcIndex miss recovery: clearing npcIndex lets findNpc find the body.
    local origFindNpc = P.DrivingDemo.findNpc
    P.DrivingDemo.npcIndex = { at = CLOCK, size = 1, by = {} }
    P.DrivingDemo.npcMemo = { [p1.uid] = {} }
    P.DrivingDemo.findNpc = function(uid, generation)
        if uid == p1.uid and P.DrivingDemo.npcIndex ~= nil then return nil end
        return origFindNpc(uid, generation)
    end
    s, why = P.DrivingLifecycle.create(owner, { player = PLAYER, route = { { x = 120, y = 100 } } }, car,
        { { uid = d1.uid, generation = 1, seat = 0 }, { uid = p1.uid, generation = 1, seat = 1 } },
        "tok-stale-index", { { x = 120, y = 100 } }, false)
    P.DrivingDemo.findNpc = origFindNpc
    P.DrivingDemo.npcIndex, P.DrivingDemo.npcMemo = nil, nil
    check("create guard clears stale DrivingDemo.npcIndex and succeeds",
        s ~= nil and #CREATED_SESSIONS == beforeSessions + 1)
    S.releaseCar(car.id, c.id)

    -- 2. S.recrew filters out a passenger that disappears during S.releaseCar (e.g. lost from
    -- heldSessions) and refreshes boarded flags if carseatRelease unseated the driver.
    local oldCarseatRelease = P.DrivingLifecycle.carseatRelease
    car.passengers = { [0] = d1, [1] = p1 }
    d1.vehicle, p1.vehicle = car, car
    owner.sleeping[car.id] = { session = { vehicle = car, uid = d1.uid } }
    P.DrivingLifecycle.carseatRelease = function(record, live)
        -- Simulate carseatRelease unseating driver and losing passenger body on release.
        car.passengers[0] = nil
        d1.vehicle = nil
        SHELLS[p1.uid] = nil
    end
    local okRecrew, crewCount = S.recrew(c, car.id, nil, 4, {})
    P.DrivingLifecycle.carseatRelease = oldCarseatRelease
    local bindingAfter = owner.bindings[car.id]
    check("recrew drops passenger unloaded across releaseCar instead of throwing",
        okRecrew == true and crewCount == 2 and bindingAfter ~= nil and #bindingAfter.crew == 2)
    check("recrew keeps surviving driver and loaded second passenger",
        bindingAfter ~= nil and bindingAfter.crew[1].uid == d1.uid and bindingAfter.crew[2].uid == p2.uid)
    -- Restore p1 shell for next checks and release car cleanly.
    SHELLS[p1.uid] = p1
    S.releaseCar(car.id, c.id)

    -- 3. S.recrew rolls back owner.bindings / VehicleArrivals.active / journeys on non-rider create failure.
    car.passengers = {}
    d1.vehicle, p1.vehicle, p2.vehicle = nil, nil, nil
    local savedCreate = P.DrivingLifecycle.create
    P.DrivingLifecycle.create = function() return nil, "simulated_create_fail" end
    local okFail, failWhy = S.recrew(c, car.id, nil, 2, {})
    P.DrivingLifecycle.create = savedCreate
    check("recrew failure on non-rider car rolls back bindings and arrivals",
        not okFail and failWhy == "simulated_create_fail"
        and owner.bindings[car.id] == nil
        and P.VehicleArrivals.active[car.id] == nil
        and P.VehicleArrivals.journeys[car.id] == nil)

    -- 4. VehicleArrivalVehicle.create wrapper forwards extra args (script, color) when S.pending == nil.
    local origVehCreate = A.wrapped["VehicleArrivalVehicle.create"]
    local seenArgs = nil
    local savedWrap = P.VehicleArrivalVehicle.create
    A.wrapped["VehicleArrivalVehicle.create"] = nil
    P.VehicleArrivalVehicle.create = function(site, reqId, script, color)
        seenArgs = { site = site, reqId = reqId, script = script, color = color }
        return nil, "probe"
    end
    S.installed = false
    S.install()
    S.pending = nil
    P.VehicleArrivalVehicle.create({ x = 10, y = 20 }, "req-non-caravan", "Base.VanAmbulance", { h = 0.1 })
    check("VehicleArrivalVehicle.create forwards script and color when pending is nil",
        seenArgs ~= nil and seenArgs.script == "Base.VanAmbulance" and type(seenArgs.color) == "table" and seenArgs.color.h == 0.1)
    -- Restore original wrapped VehicleArrivalVehicle.create
    P.VehicleArrivalVehicle.create = savedWrap
    A.wrapped["VehicleArrivalVehicle.create"] = origVehCreate

    -- Cleanup
    S.releaseCar(car.id, c.id)
    for _, npc in ipairs({ d1, p1, p2 }) do ACTORS[npc.uid], SHELLS[npc.uid] = nil, nil end
    VEHICLES[car.id], VEHICLES[nonCaravanCar.id] = nil, nil
end
