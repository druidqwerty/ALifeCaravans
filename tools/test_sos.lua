-- Run inside test_alc's existing game/A-Life simulation; no additional fake API layer.
return function(check, newContext)
    local A = ALifeCaravans
    local S, L, D, I = A.SOS, A.Ledger, A.Director, A.Interact
    local serial = 0
    local function rows() return { { key = "ivan", player = PLAYER, x = PLAYER.x, y = PLAYER.y } } end
    local function fixture()
        serial = serial + 1
        local uid, faction = "sos-driver-" .. serial, "sos-faction-" .. serial
        local car = newVehicle("Base.CarNormal", 2000 + serial * 500, 100)
        local npc = newShell(uid, faction)
        npc.x, npc.y, npc.vehicle = car.x, car.y, car
        ACTORS[uid] = { uid = uid, generation = 1, lifecycle = "active", factionId = faction, revision = 1, memory = {} }
        SHELLS[uid], car.passengers[0] = npc, npc
        local c = L.create({ name = "SOS test", callsign = "SOS-" .. serial, factionId = faction, kind = "trade", state = "rendered",
            x = car.x, y = car.y, actorUids = { uid }, vehicleIds = { car:getId() }, halted = true, trip = 1,
            vehicles = { "Base.CarNormal" }, route = { "townA", "townB" }, leg = 1, t = 0.3, goals = {}, stock = {},
            ambush = { state = "fighting", kind = "zombies", sinceMs = CLOCK } })
        PLAYER.x, PLAYER.y = car.x, car.y
        A.tagVehicle(car, c.id, 1)
        S.start(c, CLOCK)
        return c, car, npc
    end
    local function drive(c, car, npc, dx, dt, playerRows)
        CLOCK = CLOCK + (dt or 2000)
        car.x = car.x + dx
        npc.x, npc.y, c.x, c.y = car.x, car.y, car.x, car.y
        PLAYER.x, PLAYER.y = car.x, car.y
        S.tick(c, CLOCK, playerRows or rows())
    end
    local function accept(c, car) I.command(PLAYER, "distress_help", { vehicleId = car:getId(), playerKey = "forged", success = true }) end
    local function ready(c) c.ambush, c.halted, c.recrew = nil, nil, nil end

    local sandbox = SandboxVars.ALifeCaravans
    sandbox.SOSContracts, sandbox.SOSTimeoutMinutes, sandbox.SOSEscapeTiles = false, -5, 900
    A.refreshSettings()
    check("SOS runtime setting toggle and clamps", not A.settings.sosContracts and A.settings.sosTimeoutMinutes == 2 and A.settings.sosEscapeTiles == 300)
    sandbox.SOSContracts, sandbox.SOSTimeoutMinutes, sandbox.SOSEscapeTiles = nil, nil, nil
    A.refreshSettings()
    check("SOS defaults for old saves", A.settings.sosContracts and A.settings.sosTimeoutMinutes == 10 and A.settings.sosEscapeTiles == 80)
    local c, car, npc = fixture()
    check("SOS opens once per actual ambush", c.sos.state == "open" and not S.start(c, CLOCK) and c.sosSequence == 1)
    local known = D.knownTable()[car:getId()]
    check("SOS state published to clients", known.sosState == "open")
    D.publish(true)
    local ctx = newContext()
    A.Client.fill(0, ctx, {}, false)
    local found = false
    for _, menu in pairs(ctx.subs) do for _, option in ipairs(menu.options) do if option.name == TRANSLATIONS.IGUI_ALC_ui_sos_accept then found = true end end end
    check("SOS client menu offers rescue", found)
    check("SOS map retains active incident flag", A.Map.markers[c.id] and A.Map.markers[c.id].sos)
    PLAYER.x = car.x + 1000
    accept(c, car)
    check("SOS rejects remote request", c.sos.owner == nil)
    PLAYER.x = car.x
    local oldClient = isClient
    isClient = function() return true end
    check("SOS client cannot accept authoritatively", not S.accept(c, PLAYER) and c.sos.owner == nil)
    check("SOS client cannot terminate or pay contract", not S.finish(c, true, "escaped", PLAYER) and c.sos.state == "open")
    isClient = oldClient
    accept(c, car)
    local accepted = c.sos.acceptedMs
    accept(c, car)
    check("SOS authoritative owner and idempotent acceptance, no free favor", c.sos.owner == "ivan" and c.sos.acceptedMs == accepted and L.favor("ivan", c.factionId) == 0)
    local bob = setmetatable({ x = car.x, y = car.y, getUsername = function() return "bob" end }, { __index = PLAYER })
    check("SOS second player cannot steal contract", not S.accept(c, bob) and c.sos.owner == "ivan")
    for _ = 1, 16 do drive(c, car, npc, 0) end
    check("SOS fighting/waiting earns no progress", c.sos.coveredMs == 0 and c.sos.distance == 0)
    ready(c)
    S.tick(c, CLOCK, rows())
    for _ = 1, 16 do drive(c, car, npc, 0) end
    check("SOS parked car is not escaped", c.sos.state == "escape" and c.sos.coveredMs == 0)
    drive(c, car, npc, 1000)
    check("SOS teleport resets progress", c.sos.distance == 0 and c.sos.coveredMs == 0)
    drive(c, car, npc, 80, 10000)
    check("SOS stale sample earns nothing", c.sos.distance == 0 and c.sos.coveredMs == 0)
    for _ = 1, 14 do drive(c, car, npc, 6) end
    check("SOS distance alone does not pay before 30 seconds", c.sos.state == "escape" and c.sos.distance >= 80 and L.favor("ivan", c.factionId) == 0)
    drive(c, car, npc, 6)
    check("SOS real observed NPC convoy escape pays once", c.sos.state == "done" and c.sos.paid and L.favor("ivan", c.factionId) == 3)
    accept(c, car)
    S.tick(c, CLOCK, rows())
    check("SOS completed requests cannot farm favor", L.favor("ivan", c.factionId) == 3 and not S.finish(c, true, "escaped", PLAYER))
    local receiptId = c.sos.id
    BUCKETS.alc_caravans = A.copy(L.open())
    L.store = nil
    c = L.get(c.id)
    check("SOS terminal receipt survives persistence reopen", L.open().sosReceipts[receiptId].reward == 3 and c.sos.state == "done")
    check("SOS replay after reopen cannot pay twice", not S.finish(c, true, "escaped", PLAYER) and L.favor("ivan", c.factionId) == 3)
    c.sos.state, c.sos.paid = "escape", false
    check("SOS receipt repairs replayed active snapshot without reward", not S.finish(c, true, "escaped", PLAYER)
        and c.sos.state == "done" and c.sos.paid and L.favor("ivan", c.factionId) == 3)

    c, car, npc = fixture()
    accept(c, car)
    ready(c)
    S.tick(c, CLOCK, rows())
    for step = 1, 32 do drive(c, car, npc, step % 2 == 0 and -6 or 6) end
    check("SOS circling in place is not escape", c.sos.state == "escape" and L.favor("ivan", c.factionId) == 0)
    car.passengers[0] = PLAYER
    drive(c, car, npc, 6)
    check("SOS player-driven car cannot count", c.sos.sample == nil)
    car.passengers[0], npc.dead = npc, true
    drive(c, car, npc, 6)
    check("SOS dead NPC driver cannot count", c.sos.sample == nil)
    npc.dead, car.engine = false, false
    drive(c, car, npc, 6)
    check("SOS dead engine cannot count", c.sos.sample == nil)

    c, car, npc = fixture()
    accept(c, car)
    CLOCK = CLOCK + 30000
    S.tick(c, CLOCK, {})
    check("SOS brief disconnect has grace", S.active(c))
    S.tick(c, CLOCK, rows())
    check("SOS reconnect updates presence", c.sos.lastSeenMs == CLOCK)
    CLOCK = CLOCK + 61000
    S.tick(c, CLOCK, {})
    check("SOS absence fails without reward", c.sos.state == "failed" and c.sos.reason == "absent" and L.favor("ivan", c.factionId) == 0)
    c, car, npc = fixture()
    accept(c, car)
    c.state = "offline"
    S.onRelease(c, "far")
    drive(c, car, npc, 300, 30000)
    check("SOS released/offline convoy has grace but zero progress", S.active(c) and c.sos.distance == 0)
    drive(c, car, npc, 300, 31000)
    check("SOS offline movement cannot complete rescue", c.sos.state == "failed" and c.sos.reason == "lost")
    c, car, npc = fixture()
    accept(c, car)
    car.removed = true
    S.tick(c, CLOCK, rows())
    CLOCK = CLOCK + 61000
    S.tick(c, CLOCK, rows())
    check("SOS missing physical car fails, never succeeds", c.sos.state == "failed" and L.favor("ivan", c.factionId) == 0)
    c, car, npc = fixture()
    accept(c, car)
    A.tagVehicle(car, "different_caravan", 1)
    S.tick(c, CLOCK, rows())
    CLOCK = CLOCK + 61000
    S.tick(c, CLOCK, rows())
    check("SOS recycled vehicle ID cannot prove presence or escape", c.sos.state == "failed" and c.sos.reason == "lost")
    c, car, npc = fixture()
    CLOCK = c.sos.deadlineMs
    accept(c, car)
    check("SOS expired contract cannot be accepted", c.sos.state == "failed" and c.sos.owner == nil)
    c, car, npc = fixture()
    accept(c, car)
    STANCE[c.factionId] = "hostile"
    S.tick(c, CLOCK, rows())
    check("SOS aggression/hostility fails contract", c.sos.state == "failed" and c.sos.reason == "hostile")
    c, car, npc = fixture()
    accept(c, car)
    sandbox.SOSContracts = false
    A.refreshSettings()
    S.tick(c, CLOCK, rows())
    check("SOS live disable cancels without reward", c.sos.state == "failed" and c.sos.reason == "disabled")
    sandbox.SOSContracts = nil
    A.refreshSettings()
end
