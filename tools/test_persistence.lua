-- Regression cases on the existing game simulation, using the real Set iterator API.
return function(check)
    local A = ALifeCaravans
    local L, R, B, M = A.Ledger, A.Recovery, A.Boot, A.Map
    local oldStore, oldPending, oldBucket = L.store, L.reloadPending, BUCKETS.alc_caravans
    local oldFallback, oldClock = L.fallback, CLOCK
    local function open(store)
        BUCKETS.alc_caravans, L.store = store, nil
        R.nextAtMs = 0
        return L.open()
    end
    local empty = { schema = A.SCHEMA, caravans = {}, sequence = 0 }
    open(A.copy(empty))
    local foreign = newVehicle("Base.CarNormal", 120, 100)
    A.tagVehicle(foreign, "unrelated", 1)
    local function saved(id, x, uid)
        return { id = id, state = "rendered", x = x, y = 100, actorUids = uid and { uid } or {},
            vehicleIds = { foreign:getId() }, factionId = "recovery_test", units = 1, arrivals = 3,
            route = { "townA", "townB" }, goals = { { x = 250, y = 100 } } }
    end
    local car = newVehicle("Base.CarNormal", 150, 100)
    A.tagVehicle(car, "caravan:99", 1)
    local npc = newShell("restored-driver", "recovery_test")
    npc.x, npc.y, npc.vehicle = car.x, car.y, car
    SHELLS[npc.uid], car.passengers[0] = npc, npc
    ACTORS[npc.uid] = { uid = npc.uid, generation = 1, lifecycle = "active", factionId = "recovery_test", revision = 1 }
    local c = saved("caravan:99", 150, npc.uid)
    car.passengers[1] = PLAYER
    local owner = ProjectALife.VehicleArrivals.owner()
    owner.bindings[car.id] = {vehicleId=car.id,restoredCrew=true,crew={{uid=npc.uid,generation=1,seat=0}}}
    owner.allowRiders[car.id], owner.carModes[car.id] = true, "mixed"
    open({ schema = A.SCHEMA, sequence = 1, caravans = { [c.id] = c } })
    check("reload detects current-schema physical caravan", L.reloadPending[c.id] ~= nil)
    R.tick(CLOCK)
    check("reload quarantines old IDs during restore grace", c.state == "recovering" and #c.vehicleIds == 0 and not foreign.removed)
    CLOCK = CLOCK + R.graceMs + 1
    R.tick(CLOCK)
    check("reload binds same tagged car at new current ID", c.state == "rendered" and c.vehicleIds[1] == car:getId()
        and c.actorUids[1] == npc.uid and c.arrivals == 0 and not foreign.removed)
    check("reload derives permitted rider tracking from actual occupied car", c.riders==true and c.ridersAboard==true)
    car.passengers[1] = nil
    local created = L.create({ state = "offline" })
    check("ledger sequence cannot overwrite restored record", created.id == "caravan:100" and L.get(c.id) == c)
    L.reset()
    check("debug reset cannot reuse old vehicle tags", L.create({ state = "offline" }).id == "caravan:101")

    local orphan = newVehicle("Base.CarNormal", 180, 100)
    A.tagVehicle(orphan, "caravan:102", 1)
    orphan.occupied = true
    c = saved("caravan:102", 180)
    open({ schema = A.SCHEMA, caravans = { [c.id] = c } })
    R.tick(CLOCK)
    CLOCK = CLOCK + R.graceMs + 1
    R.tick(CLOCK)
    check("reload without crew preserves player-occupied car as stranded", c.state == "stranded"
        and c.recoveryReason == "no_live_crew" and c.vehicleIds[1] == orphan:getId() and not orphan.removed)
    check("reload tracks real occupants without inventing mixed permission", c.ridersAboard==true and c.riders~=true)

    c = saved("caravan:103", 1000)
    open({ schema = A.SCHEMA, caravans = { [c.id] = c } })
    R.tick(CLOCK)
    CLOCK = CLOCK + R.graceMs + 1
    R.tick(CLOCK)
    check("unloaded save location cannot duplicate-spawn caravan", c.state == "recovering" and L.reloadPending[c.id] ~= nil)
    c.x = 200
    CLOCK = CLOCK + 1001
    R.tick(CLOCK)
    CLOCK = CLOCK + R.graceMs + 1
    R.tick(CLOCK)
    check("loaded location with missing cars returns safely to ledger", c.state == "offline" and #c.vehicleIds == 0 and not foreign.removed)

    local install, installed, errors, tries = A.Spawn.install, B.installed, A.metrics.errors, B.tries
    B.installed = false
    A.Spawn.install = function() error("simulated transient hook failure") end
    check("bootstrap failure does not latch successful install", not B.install() and not B.installed)
    A.Spawn.install = install
    check("bootstrap can retry after hook failure", B.install() and B.installed)
    B.installed, B.tries, A.metrics.errors = installed, tries, errors

    local oldMarkers, oldOrder, oldReceived = M.markers, M.order, M.receivedAtMs
    local packet = { { id = "valid", x = 100, y = 100 }, { id = "valid", x = 105, y = 100 },
        {}, false, { id = "bad", x = 0 / 0, y = 100 }, { id = "bad2", x = math.huge, y = 100 } }
    local ok = pcall(M.setMarkers, packet)
    check("map ignores malformed coordinates and duplicate markers", ok and #M.order == 1 and M.markers.valid.x1 == 105)
    check("map waits for both projection methods", M.drawOn({}, { worldToUIX = function() return 0 end }, false) == 0)
    M.markers, M.order, M.receivedAtMs = oldMarkers, oldOrder, oldReceived
    L.store, L.reloadPending, BUCKETS.alc_caravans = oldStore, oldPending, oldBucket
    L.fallback, CLOCK = oldFallback, oldClock
    R.nextAtMs = 0
end
