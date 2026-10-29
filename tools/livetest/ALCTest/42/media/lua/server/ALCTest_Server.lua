-- A-Life: Caravans live-test driver (server, test only). Once the client reports "ready", runs the scenario:
--   boot    A-Life runtime and the add-on installed
--   place   teleport the player onto a road of A-Life's road graph
--   render  found a caravan 90 tiles up the road and wait until it is on the road (cars + crew)
--   drive   follow it (the player is teleported behind it so the map stays loaded); it must move
--   hail    flag it down beside the lead car; it must stop
--   trade   stock reaches the client; a deal is executed and committed
--   ride    the player boards a free seat; the caravan drives on with the rider; the player gets out
--   recrew  the lead driver is killed; the survivors must re-crew the car and drive on
--   release the player is sent 500 tiles away; the caravan must go back to the ledger, cars removed
-- Every step logs "[ALCTest] STEP <name> PASS|FAIL|SKIP <detail>"; ALCTest_done.txt is written at the end.
if isClient() then return end

local function log(msg) print("[ALCTest] " .. tostring(msg)) end

local T = { player = nil, step = nil, stepAt = 0, results = {}, lastStatus = nil, caravan = nil, done = false,
    follow = nil, samples = {} }

local function now() return getTimestampMs() end
local function A() return ALifeCaravans end
local function P() return ProjectALife end

local function result(step, ok, detail)
    T.results[#T.results + 1] = { step = step, ok = ok, detail = detail or "" }
    log("STEP " .. step .. " " .. (ok == true and "PASS" or (ok == "skip" and "SKIP" or "FAIL")) .. " " .. tostring(detail or ""))
end

local function go(step)
    T.step, T.stepAt = step, now()
    log("-> " .. tostring(step))
end

local function age() return now() - T.stepAt end

local function send(command, args)
    if T.player then sendServerCommand(T.player, "ALCTest", command, args or {}) end
end

local function playerXY()
    if not T.player then return 0, 0 end
    return T.player:getX(), T.player:getY()
end

local function leadCar()
    local c = T.caravan
    if not c then return nil end
    for _, id in ipairs(c.vehicleIds or {}) do
        local car = getVehicleById(id)
        if car then return car, id end
    end
    return nil
end

local function dist(x1, y1, x2, y2) return math.sqrt((x1 - x2) ^ 2 + (y1 - y2) ^ 2) end

-- a road point near (x, y): the road graph's snap, then the nearest town
local function roadPoint(x, y, radius)
    local G = P() and P().RoadGraph
    if not G then return nil end
    local ok, point = pcall(G.snapToRoad, x, y, radius or 60)
    if ok and point then return point.x + 0.5, point.y + 0.5 end
    return nil
end

local function finish()
    if T.done then return end
    T.done = true
    local lines, passed, failed = {}, 0, 0
    for _, r in ipairs(T.results) do
        lines[#lines + 1] = r.step .. "=" .. (r.ok == true and "PASS" or (r.ok == "skip" and "SKIP" or "FAIL")) .. " " .. r.detail
        if r.ok == true then passed = passed + 1 elseif r.ok ~= "skip" then failed = failed + 1 end
    end
    local a = A()
    lines[#lines + 1] = "counters: " .. (a and a.counters() or "?")
    lines[#lines + 1] = "errors: " .. tostring(a and a.metrics.errors or "?")
    local writer = getFileWriter("ALCTest_done.txt", true, false)
    for _, line in ipairs(lines) do writer:writeln(line) end
    writer:close()
    log("DONE passed=" .. passed .. " failed=" .. failed)
    for _, line in ipairs(lines) do log("  " .. line) end
end

local function fail(step, detail)
    result(step, false, detail)
end

local steps = {}

function steps.boot()
    local a, p = A(), P()
    if a and a.Boot and a.Boot.installed and p and p.Runtime and p.Runtime.started then
        result("boot", true, "installed, runtime started")
        go("place")
    elseif age() > 240000 then
        fail("boot", "add-on installed=" .. tostring(a and a.Boot and a.Boot.installed) .. " runtime=" .. tostring(p and p.Runtime and p.Runtime.started))
        finish()
    end
end

function steps.place()
    if not T.placed then
        local px, py = playerXY()
        local x, y = roadPoint(px, py, 120)
        if not x then
            local G = P().RoadGraph
            local best, bestD = nil, math.huge
            for id, node in pairs(G.nodes or {}) do
                local d = dist(px, py, node.x, node.y)
                if d < bestD then best, bestD = node, d end
            end
            if best then x, y = roadPoint(best.x, best.y, 120) end
        end
        if not x then fail("place", "no road near the player") finish() return end
        T.placed = { x = x, y = y }
        send("teleport", { x = x, y = y })
        log("player sent to the road at " .. math.floor(x) .. "," .. math.floor(y))
        T.stepAt = now()
        return
    end
    if age() > 20000 then
        local px, py = playerXY()
        result("place", dist(px, py, T.placed.x, T.placed.y) < 10, "player at " .. math.floor(px) .. "," .. math.floor(py))
        go("render")
    end
end

function steps.render()
    local a = A()
    local D, Ledger = a.Director, a.Ledger
    if not T.caravan then
        a.settings.maxCaravans = 1
        a.settings.foundIntervalMinutes = 1
        local store = Ledger.open()
        for _, c in ipairs(Ledger.list()) do D.retire(c, "test reset") end
        store.nextFoundAtMs = 0
        local ok, caravan = D.found(now(), D.playerRows())
        if not ok then
            if age() > 60000 then fail("render", "founding refused: " .. tostring(caravan)) finish() end
            return
        end
        T.caravan = caravan
        local px, py = playerXY()
        local placed
        for _, d in ipairs({ { 90, 0 }, { 0, 90 }, { -90, 0 }, { 0, -90 }, { 64, 64 }, { -64, 64 }, { 64, -64 }, { -64, -64 }, { 110, 0 }, { 0, 110 }, { -110, 0 }, { 0, -110 } }) do
            local x, y = roadPoint(px + d[1], py + d[2], 30)
            if x and dist(x, y, px, py) >= 60 and dist(x, y, px, py) <= 140 then placed = { x = x, y = y } break end
        end
        if not placed then placed = { x = px + 80, y = py } end
        caravan.x, caravan.y = placed.x, placed.y
        caravan.nextRenderAtMs = 0
        D.renderCooldownUntilMs = 0
        log("caravan " .. caravan.id .. " " .. caravan.name .. " " .. tostring(caravan.callsign) .. " placed at " .. math.floor(placed.x) .. "," .. math.floor(placed.y)
            .. " (" .. #caravan.vehicles .. " cars, " .. #caravan.crew .. " crew); waiting for render")
        T.stepAt = now()
        return
    end
    local c = T.caravan
    if c.state == "rendered" then
        local car, id = leadCar()
        result("render", car ~= nil, "state=" .. c.state .. " cars=" .. #c.vehicleIds .. " crew=" .. #c.actorUids .. " units=" .. tostring(c.units)
            .. " refused=" .. a.metrics.renderRefused)
        if car then
            T.samples = { { x = car:getX(), y = car:getY(), at = now() } }
            go("drive")
        else
            finish()
        end
    elseif age() > 180000 then
        fail("render", "state=" .. tostring(c.state) .. " refused=" .. a.metrics.renderRefused .. " failures=" .. tostring(c.renderFailures))
        finish()
    end
end

-- keep the player 35 tiles behind the lead car (where it was 5 s ago) so the map stays loaded
local function follow()
    local car = leadCar()
    if not car then return end
    local x, y = car:getX(), car:getY()
    T.samples[#T.samples + 1] = { x = x, y = y, at = now() }
    local back = T.samples[math.max(1, #T.samples - 2)]
    local px, py = playerXY()
    if dist(px, py, back.x, back.y) > 45 then send("teleport", { x = back.x, y = back.y }) end
end

function steps.drive()
    if not T.caravan or T.caravan.state ~= "rendered" then
        if age() > 20000 then fail("drive", "caravan state " .. tostring(T.caravan and T.caravan.state)) finish() end
        return
    end
    if now() - (T.followAt or 0) > 5000 then
        T.followAt = now()
        follow()
    end
    if age() > 75000 then
        local first, last = T.samples[1], T.samples[#T.samples]
        local moved = dist(first.x, first.y, last.x, last.y)
        local phases = T.lastStatus and T.lastStatus.sessions or {}
        local text = ""
        for id, phase in pairs(phases) do text = text .. id .. ":" .. tostring(phase) .. " " end
        result("drive", moved >= 20, string.format("moved %.1f tiles in %d s; client sessions: %s; legs=%d", moved, math.floor(age() / 1000), text, A().metrics.legs))
        go("hail")
    end
end

function steps.hail()
    local c = T.caravan
    local car, id = leadCar()
    if not car then fail("hail", "no lead car") finish() return end
    if not T.hailed then
        send("teleport", { x = car:getX() + 4, y = car:getY() + 3 })
        T.hailed = { at = now(), id = id }
        T.stepAt = now()
        return
    end
    if age() > 6000 and not T.hailed.sent then
        T.hailed.sent = true
        A().Interact.command(T.player, "hail", { vehicleId = id })
        T.hailed.x, T.hailed.y = car:getX(), car:getY()
        log("hail sent; halted=" .. tostring(c.halted))
        return
    end
    if T.hailed.sent and age() > 26000 then
        local moved = dist(car:getX(), car:getY(), T.hailed.x, T.hailed.y)
        local phases = T.lastStatus and T.lastStatus.sessions or {}
        local text = ""
        for sid, phase in pairs(phases) do text = text .. sid .. ":" .. tostring(phase) .. " " end
        result("hail", c.halted == true and moved < 12, string.format("halted=%s moved %.1f tiles after the hail; sessions: %s", tostring(c.halted), moved, text))
        go("trade")
    end
end

function steps.trade()
    local c = T.caravan
    local car, id = leadCar()
    if not car then fail("trade", "no lead car") finish() return end
    if not T.traded then
        T.traded = { stockBefore = 0 }
        for _, row in ipairs(c.stock or {}) do T.traded.stockBefore = T.traded.stockBefore + row.count end
        A().Interact.command(T.player, "trade", { vehicleId = id })
        T.stepAt = now()
        return
    end
    if age() > 8000 and not T.traded.deal then
        T.traded.deal = true
        T.traded.window = T.lastStatus and T.lastStatus.window
        local row = c.stock and c.stock[1]
        if not row then fail("trade", "no stock") go("ride") return end
        local price = A().Trade.sellPrice(row, c.kind, 0) + 5
        A().Interact.command(T.player, "deal", { vehicleId = id, take = { [1] = 1 }, give = { { type = "Base.Money", count = price } } })
        log("deal sent for " .. row.item .. " at " .. price)
        return
    end
    if T.traded.deal and age() > 20000 then
        local after = 0
        for _, row in ipairs(c.stock or {}) do after = after + row.count end
        local pending = 0
        for _ in pairs(c.pending or {}) do pending = pending + 1 end
        result("trade", A().metrics.trades >= 1 and after == T.traded.stockBefore - 1,
            string.format("trades=%d stock %d->%d pending=%d window=%s", A().metrics.trades, T.traded.stockBefore, after, pending, tostring(T.traded.window)))
        go("ride")
    end
end

function steps.ride()
    local c = T.caravan
    local car, id = leadCar()
    if not car then fail("ride", "no lead car") finish() return end
    if not T.ride then
        T.ride = { phase = "ask" }
        A().Interact.command(T.player, "ride", { vehicleId = id })
        T.stepAt = now()
        return
    end
    if T.ride.phase == "ask" and age() > 4000 then
        T.ride.phase = "enter"
        send("teleport", { x = car:getX() + 2.5, y = car:getY() + 1 })
        T.ride.at = now()
        return
    end
    if T.ride.phase == "enter" and now() - T.ride.at > 4000 then
        T.ride.phase = "entering"
        T.ride.at = now()
        send("enter", { vehicleId = id, seat = 1 })
        return
    end
    if T.ride.phase == "entering" and now() - T.ride.at > 30000 then
        local inVehicle = T.lastStatus and T.lastStatus.inVehicle
        T.ride.aboard = inVehicle == id
        result("ride.board", T.ride.aboard, "client inVehicle=" .. tostring(inVehicle) .. " riders allowed=" .. tostring(c.riders))
        T.ride.phase = "go"
        T.ride.at = now()
        T.ride.x, T.ride.y = playerXY()
        A().Interact.command(T.player, "farewell", { vehicleId = id })
        return
    end
    if T.ride.phase == "go" and now() - T.ride.at > 45000 then
        local px, py = playerXY()
        local moved = dist(px, py, T.ride.x, T.ride.y)
        if T.ride.aboard then
            result("ride.move", moved >= 15, string.format("rider moved %.1f tiles with the convoy", moved))
        else
            result("ride.move", "skip", "not aboard")
        end
        send("exit", {})
        T.ride.phase = "exit"
        T.ride.at = now()
        return
    end
    if T.ride.phase == "exit" and now() - T.ride.at > 12000 then
        local inVehicle = T.lastStatus and T.lastStatus.inVehicle
        if T.ride.aboard then result("ride.exit", inVehicle == nil, "client inVehicle=" .. tostring(inVehicle)) end
        T.samples = {}
        go("recrew")
    end
end

function steps.recrew()
    local c = T.caravan
    local car, id = leadCar()
    if not car then fail("recrew", "no lead car") finish() return end
    if now() - (T.followAt or 0) > 5000 then T.followAt = now() follow() end
    if not T.recrew then
        local driver = car:getDriver()
        if not driver then
            if age() > 30000 then result("recrew", "skip", "no driver seated on the server side") go("release") end
            return
        end
        local ok, err = pcall(function()
            driver:setHealth(0)
            driver:Kill(nil)
        end)
        T.recrew = { at = now(), driver = driver, recrewsBefore = A().metrics.recrews, ok = ok, err = err }
        log("driver kill attempted: ok=" .. tostring(ok) .. " " .. tostring(err))
        T.stepAt = now()
        return
    end
    local dead = false
    pcall(function() dead = T.recrew.driver:isDead() end)
    if not T.recrew.deadSeen and dead then
        T.recrew.deadSeen = now()
        log("driver is dead; waiting for the re-crew")
    end
    if not T.recrew.deadSeen and age() > 40000 then
        result("recrew", "skip", "the driver did not die from the test kill (A-Life health protocol)")
        go("release")
        return
    end
    if T.recrew.deadSeen and A().metrics.recrews > T.recrew.recrewsBefore and not T.recrew.recrewed then
        T.recrew.recrewed = now()
        T.recrew.x, T.recrew.y = car:getX(), car:getY()
        log("re-crew started: " .. (A().metrics.recrews - T.recrew.recrewsBefore) .. " car(s)")
    end
    if T.recrew.recrewed and now() - T.recrew.recrewed > 120000 then
        local moved = dist(car:getX(), car:getY(), T.recrew.x, T.recrew.y)
        local phases = T.lastStatus and T.lastStatus.sessions or {}
        local text = ""
        for sid, phase in pairs(phases) do text = text .. sid .. ":" .. tostring(phase) .. " " end
        result("recrew", moved >= 10, string.format("car moved %.1f tiles after the re-crew; sessions: %s; cars=%d abandoned=%d", moved, text, #c.vehicleIds, #(c.abandoned or {})))
        go("release")
        return
    end
    if T.recrew.deadSeen and age() > 200000 then
        fail("recrew", "no re-crew within 200 s; recrews=" .. A().metrics.recrews .. " cars=" .. #c.vehicleIds .. " state=" .. tostring(c.state))
        go("release")
    end
end

function steps.release()
    local c = T.caravan
    if not T.released then
        local px, py = playerXY()
        T.released = { at = now(), cars = #c.vehicleIds }
        send("teleport", { x = px + 500, y = py + 500 })
        T.stepAt = now()
        return
    end
    if age() > 70000 then
        local remaining = 0
        for _, id in ipairs(T.released and c.vehicleIds or {}) do if getVehicleById(id) then remaining = remaining + 1 end end
        local anyCar = leadCar()
        result("release", c.state == "offline" and anyCar == nil, "state=" .. tostring(c.state) .. " cars left=" .. tostring(anyCar ~= nil) .. " released=" .. A().metrics.released)
        finish()
    end
end

Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= "ALCTest" then return end
    if command == "ready" then
        if not T.player then
            T.player = player
            log("client ready: " .. tostring(player:getUsername()) .. " at " .. math.floor(player:getX()) .. "," .. math.floor(player:getY()))
            pcall(function() player:setInvulnerable(true) end)
            go("boot")
        end
    elseif command == "status" then
        T.lastStatus = args
        if now() - (T.statusLoggedAt or 0) > 15000 then
            T.statusLoggedAt = now()
            local text = ""
            for id, phase in pairs(args.sessions or {}) do text = text .. id .. ":" .. tostring(phase) .. " " end
            log(string.format("client: at %s,%s inVehicle=%s known=%s markers=%s window=%s errors=%s sessions: %s",
                tostring(args.x), tostring(args.y), tostring(args.inVehicle), tostring(args.known), tostring(args.markers),
                tostring(args.window), tostring(args.errors), text))
        end
    end
end)

Events.OnTick.Add(function()
    if T.done or not T.step then return end
    if now() - (T.tickAt or 0) < 1000 then return end
    T.tickAt = now()
    local fn = steps[T.step]
    if not fn then return end
    local ok, err = pcall(fn)
    if not ok then
        log("step " .. tostring(T.step) .. " error: " .. tostring(err))
        fail(T.step, "error: " .. tostring(err))
        finish()
    end
end)

log("server driver loaded")
