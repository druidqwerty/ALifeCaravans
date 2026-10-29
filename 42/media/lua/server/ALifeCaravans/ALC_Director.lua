-- A-Life: Caravans - the director (server / single player). Founds caravans in
-- towns of A-Life's road graph, moves them along town-to-town routes while no
-- player is near ("offline"), puts them on the road through ALC_Spawn when a
-- player comes within the render radius, follows them while they drive, and
-- takes them back into the ledger when every player is far away.

require "ALifeCaravans/00_ALC_Core"
require "ALifeCaravans/01_ALC_Lines"
require "ALifeCaravans/02_ALC_Vehicles"
require "ALifeCaravans/03_ALC_Roads"
require "ALifeCaravans/04_ALC_Convoy"
require "ALifeCaravans/ALC_Ledger"
require "ALifeCaravans/ALC_Spawn"

local A = ALifeCaravans
local D = { nextTickMs = 0, intervalMs = 2000, lastTickMs = nil, renderCooldownUntilMs = 0, publishAtMs = 0,
    publishDirty = false, maxRendered = 2, goalSpacing = 55 }
A.Director = D

local KIND_BY_CLASS = { military = "convoy", police = "patrol", rescue = "rescue", trade = "trade", raider = "raid", civilian = "trade" }

local function P() return ProjectALife end

function D.graph()
    local p = P()
    local G = p and p.RoadGraph or nil
    if G == nil or type(G.nodes) ~= "table" then return nil end
    if next(G.nodes) == nil and type(G.importShipped) == "function" then pcall(G.importShipped) end
    if next(G.nodes) == nil then return nil end
    return G
end

function D.clock()
    local rules = P() and P().FactionSpawnRules
    if rules ~= nil and type(rules.clock) == "function" then
        local ok, day, hour = pcall(rules.clock)
        if ok and type(day) == "number" then return day, hour or 12 end
    end
    local day, hour = 1, 12
    pcall(function()
        local time = getGameTime()
        day = math.floor(time:getNightsSurvived()) + 1
        hour = time:getTimeOfDay()
    end)
    return day, hour
end

function D.playerRows()
    local rows = {}
    for _, player in ipairs(A.players()) do
        local x, y = A.xyz(player)
        if x ~= nil then rows[#rows + 1] = { player = player, x = x, y = y, key = A.playerKey(player) } end
    end
    return rows
end

local function nearestPlayer(rows, x, y)
    local best, bestD = nil, math.huge
    for _, row in ipairs(rows) do
        local d = A.dist(x, y, row.x, row.y)
        if d < bestD then best, bestD = row, d end
    end
    return best, bestD
end

function D.nodeName(G, id)
    local node = G and G.nodes[id] or nil
    if node == nil then return tostring(id) end
    if type(G.displayName) == "function" then
        local ok, name = pcall(G.displayName, id, node)
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    return tostring(node.name or id)
end

-- Factions that may run caravans today: populated, in season, with people.
function D.factionRows()
    local p = P()
    local catalog = p and p.Catalog and (p.Catalog.current or (type(p.Catalog.load) == "function" and p.Catalog.load())) or nil
    local rules = p and p.FactionSpawnRules or nil
    if catalog == nil then return {} end
    local day, hour = D.clock()
    local allowHostile = A.settings.allowHostile
    local function filter(faction)
        if type(faction) ~= "table" or faction.spawn == nil then return false end
        if faction.spawn.enabled == false or faction.general and faction.general.deleted then return false end
        if faction.spawn.visitorOnly == true then return false end
        if not allowHostile and rules ~= nil and type(rules.hostile) == "function" and rules.hostile(faction) then return false end
        return true
    end
    local rows = {}
    if rules ~= nil and type(rules.pickList) == "function" then
        local ok, list = pcall(rules.pickList, catalog, "roamer", false, day, hour, nil, filter)
        if ok and type(list) == "table" then rows = list end
    end
    if #rows == 0 then
        local populated = {}
        for _, profile in ipairs(catalog.npcOrder or {}) do
            if profile.general then populated[profile.general.faction] = true end
        end
        for _, faction in ipairs(catalog.factionOrder or {}) do
            if populated[faction.id] and filter(faction) then rows[#rows + 1] = { faction = faction, weight = 1 } end
        end
    end
    return rows, catalog
end

function D.pickFaction()
    local rows, catalog = D.factionRows()
    if #rows == 0 then return nil, catalog end
    local total = 0
    for _, row in ipairs(rows) do total = total + math.max(0, tonumber(row.weight) or 0) end
    if total <= 0 then return rows[A.rand(#rows) + 1].faction, catalog end
    local needle = A.randFloat() * total
    for _, row in ipairs(rows) do
        needle = needle - math.max(0, tonumber(row.weight) or 0)
        if needle < 0 then return row.faction, catalog end
    end
    return rows[#rows].faction, catalog
end

function D.rosterFor(catalog, factionId)
    local out = {}
    for _, profile in ipairs(catalog and catalog.npcOrder or {}) do
        if profile.general and profile.general.faction == factionId and not profile.general.deleted then out[#out + 1] = profile end
    end
    return out
end

function D.crewFor(catalog, faction, count)
    local roster = D.rosterFor(catalog, faction.id)
    if #roster == 0 then return nil end
    local p = P()
    local crew = {}
    for _ = 1, count do
        local profile
        if p.Catalog ~= nil and type(p.Catalog.weightedProfile) == "function" then
            profile = p.Catalog.weightedProfile(roster, A.randFloat())
        end
        profile = profile or roster[A.rand(#roster) + 1]
        crew[#crew + 1] = profile.id
    end
    return crew
end

-- A route of 2-4 edges from `fromId`, no node twice.
function D.planRoute(G, fromId, edges)
    local route, seen = { fromId }, { [fromId] = true }
    local current = fromId
    for _ = 1, edges do
        local choices = {}
        for other in pairs(G.adjacency and G.adjacency[current] or {}) do
            if not seen[other] and G.nodes[other] ~= nil then choices[#choices + 1] = other end
        end
        if #choices == 0 then break end
        table.sort(choices)
        local pick = choices[A.rand(#choices) + 1]
        route[#route + 1] = pick
        seen[pick] = true
        current = pick
    end
    if #route < 2 then return nil end
    return route
end

function D.edgeLength(G, a, b)
    local length = G.adjacency and G.adjacency[a] and G.adjacency[a][b] or nil
    if type(length) ~= "number" or length <= 0 then
        local na, nb = G.nodes[a], G.nodes[b]
        if na == nil or nb == nil then return 1 end
        length = math.max(1, A.dist(na.x, na.y, nb.x, nb.y))
    end
    return length
end

function D.interpolate(G, a, b, t)
    if type(G.interpolate) == "function" then
        local ok, point = pcall(G.interpolate, a, b, t)
        if ok and type(point) == "table" then return point end
    end
    local na, nb = G.nodes[a], G.nodes[b]
    if na == nil or nb == nil then return nil end
    return { x = na.x + (nb.x - na.x) * t, y = na.y + (nb.y - na.y) * t, z = 0 }
end

-- Road points ahead of the caravan along its remaining route, goalSpacing apart.
function D.goalsFor(G, caravan)
    local goals = {}
    local route = caravan.route or {}
    for leg = caravan.leg or 1, #route - 1 do
        local a, b = route[leg], route[leg + 1]
        local length = D.edgeLength(G, a, b)
        local start = leg == (caravan.leg or 1) and (caravan.t or 0) or 0
        local step = D.goalSpacing / length
        local t = start + step
        while t < 1 do
            local point = D.interpolate(G, a, b, t)
            if point ~= nil then goals[#goals + 1] = { x = point.x, y = point.y } end
            t = t + step
            if #goals >= 60 then break end
        end
        local nodeB = G.nodes[b]
        if nodeB ~= nil then goals[#goals + 1] = { x = nodeB.x, y = nodeB.y } end
        if #goals >= 60 then break end
    end
    return goals
end

function D.offlinePosition(G, caravan)
    local route = caravan.route or {}
    local leg = caravan.leg or 1
    if route[leg + 1] == nil then
        local node = G.nodes[route[#route]]
        return node and { x = node.x, y = node.y } or nil
    end
    return D.interpolate(G, route[leg], route[leg + 1], caravan.t or 0)
end

-- Advance the ledger position by dt seconds of real time.
function D.advance(G, caravan, dt)
    local route = caravan.route or {}
    if route[(caravan.leg or 1) + 1] == nil then return "end" end
    local tilesPerSecond = (tonumber(caravan.speedKmh) or A.settings.cruiseKmh) / 3.6 * A.settings.offlineSpeedPercent / 100
    local tiles = tilesPerSecond * dt
    while tiles > 0 do
        local leg = caravan.leg or 1
        local a, b = route[leg], route[leg + 1]
        if b == nil then return "end" end
        local length = D.edgeLength(G, a, b)
        local remaining = (1 - (caravan.t or 0)) * length
        if tiles < remaining then
            caravan.t = (caravan.t or 0) + tiles / length
            tiles = 0
        else
            tiles = tiles - remaining
            caravan.leg, caravan.t = leg + 1, 0
        end
    end
    local point = D.offlinePosition(G, caravan)
    if point ~= nil then caravan.x, caravan.y = point.x, point.y end
    return route[(caravan.leg or 1) + 1] == nil and "end" or "moving"
end

-- Put the ledger progress at the route point nearest to a world position.
function D.snapProgress(G, caravan, x, y)
    local route = caravan.route or {}
    local bestLeg, bestT, bestD = caravan.leg or 1, caravan.t or 0, math.huge
    for leg = 1, #route - 1 do
        local na, nb = G.nodes[route[leg]], G.nodes[route[leg + 1]]
        if na ~= nil and nb ~= nil then
            local dx, dy = nb.x - na.x, nb.y - na.y
            local len2 = dx * dx + dy * dy
            local t = len2 > 0 and ((x - na.x) * dx + (y - na.y) * dy) / len2 or 0
            t = math.max(0, math.min(1, t))
            local px, py = na.x + dx * t, na.y + dy * t
            local d = A.dist(x, y, px, py)
            if d < bestD then bestLeg, bestT, bestD = leg, t, d end
        end
    end
    caravan.leg, caravan.t = bestLeg, bestT
    caravan.x, caravan.y = x, y
end

function D.newTrip(G, caravan, fromId)
    local route = D.planRoute(G, fromId, 2 + A.rand(3))
    if route == nil then return false end
    caravan.route, caravan.leg, caravan.t = route, 1, 0
    caravan.destName = D.nodeName(G, route[#route])
    caravan.goals = D.goalsFor(G, caravan)
    caravan.goalIndex = 1
    caravan.arrivals = 0
    local point = D.offlinePosition(G, caravan)
    if point ~= nil then caravan.x, caravan.y = point.x, point.y end
    return true
end

-- Found a caravan: a town 2-4 edges from a town near a player, heading there.
function D.found(now, players)
    local G = D.graph()
    if G == nil then return false, "no_road_graph" end
    local faction, catalog = D.pickFaction()
    if faction == nil then return false, "no_faction" end
    local crewCount = A.settings.crewMin + A.rand(A.settings.crewMax - A.settings.crewMin + 1)
    local crew = D.crewFor(catalog, faction, crewCount)
    if crew == nil then return false, "no_profiles" end
    local towns = {}
    for id, node in pairs(G.nodes) do
        if node.kind == nil or node.kind == "town" then towns[#towns + 1] = id end
    end
    table.sort(towns)
    if #towns < 2 then return false, "no_towns" end
    -- destination: a town within 150..900 tiles of some player; start: 2-4 edges away and far from everyone
    local candidates = {}
    for _, id in ipairs(towns) do
        local node = G.nodes[id]
        local _, d = nearestPlayer(players, node.x, node.y)
        if #players == 0 or (d >= 150 and d <= 900) then candidates[#candidates + 1] = id end
    end
    if #candidates == 0 then candidates = towns end
    -- shuffle the destinations once, then try a few plans from each
    for index = #candidates, 2, -1 do
        local swap = A.rand(index) + 1
        candidates[index], candidates[swap] = candidates[swap], candidates[index]
    end
    local route, bestD = nil, -1
    for _, destination in ipairs(candidates) do
        for _ = 1, 4 do
            local back = D.planRoute(G, destination, 2 + A.rand(3))
            if back ~= nil then
                local startNode = G.nodes[back[#back]]
                local _, d = nearestPlayer(players, startNode.x, startNode.y)
                if #players == 0 then d = math.huge end
                if d > bestD then
                    bestD = d
                    route = {}
                    for i = #back, 1, -1 do route[#route + 1] = back[i] end
                end
            end
            if bestD >= A.settings.releaseRadius + 60 then break end
        end
        if bestD >= A.settings.releaseRadius + 60 then break end
    end
    -- never found a far start: accept one outside the render radius, otherwise give up
    if route == nil or bestD < A.settings.renderRadius then return false, "no_route" end
    local class = A.Vehicles.classFor(faction)
    local vehicles = A.Vehicles.convoy(class, #crew, A.settings.maxVehicles)
    if #vehicles == 0 then return false, "no_vehicles" end
    local kind = KIND_BY_CLASS[class] or "trade"
    local rules = P().FactionSpawnRules
    local hostile = rules ~= nil and type(rules.hostile) == "function" and rules.hostile(faction) == true or false
    if hostile and kind ~= "convoy" and kind ~= "patrol" then kind = "raid" end
    local speed = A.settings.cruiseKmh
    if class == "military" then speed = speed - 5 elseif class == "raider" then speed = speed + 5 end
    local caravan = {
        name = tostring(faction.general and faction.general.name or faction.id),
        factionId = faction.id, factionName = tostring(faction.general and faction.general.name or faction.id),
        kind = kind, class = class, hostile = hostile,
        vehicles = vehicles, crew = crew, speedKmh = math.max(10, math.min(70, speed)),
        route = route, leg = 1, t = 0, trips = 0, state = "offline", createdMs = now, lastMs = now,
        vehicleIds = {}, actorUids = {}, renderFailures = 0, nextRenderAtMs = 0, truce = {}, goalIndex = 1,
    }
    caravan.destName = D.nodeName(G, route[#route])
    caravan.goals = D.goalsFor(G, caravan)
    local point = D.offlinePosition(G, caravan)
    if point ~= nil then caravan.x, caravan.y = point.x, point.y end
    if A.Interact ~= nil and type(A.Interact.offersFor) == "function" then caravan.offers = A.Interact.offersFor(caravan) end
    A.Ledger.create(caravan)
    A.metrics.founded = A.metrics.founded + 1
    A.log("founded", caravan.id, caravan.name, "(" .. kind .. ", " .. #crew .. " crew, " .. #vehicles .. " car(s))",
        "from", D.nodeName(G, route[1]), "to", caravan.destName)
    return true, caravan
end

function D.retire(caravan, reason)
    if caravan.state == "rendered" or caravan.state == "rendering" or caravan.state == "fighting" or caravan.state == "stranded" then
        A.Spawn.teardown(caravan, "alc_retire")
    end
    A.Ledger.remove(caravan.id)
    A.metrics.retired = A.metrics.retired + 1
    A.debug("retired", caravan.id, reason)
    D.publishDirty = true
end

function D.release(caravan, reason)
    local G = D.graph()
    local kept = A.Spawn.teardown(caravan, "alc_release")
    if G ~= nil and caravan.x ~= nil then D.snapProgress(G, caravan, caravan.x, caravan.y) end
    caravan.state = "offline"
    caravan.halted, caravan.haltUntilMs, caravan.riders = nil, nil, nil
    caravan.nextRenderAtMs = A.now() + 30000
    if G ~= nil then caravan.goals = D.goalsFor(G, caravan) caravan.goalIndex = 1 end
    A.metrics.released = A.metrics.released + 1
    A.log("released", caravan.id, reason, #kept > 0 and ("(" .. #kept .. " car(s) left with players inside)") or "")
    D.publishDirty = true
    A.Ledger.touch()
end

function D.countRendered()
    local count = 0
    for _, caravan in ipairs(A.Ledger.list()) do
        if caravan.state == "rendering" or caravan.state == "rendered" or caravan.state == "fighting" then count = count + 1 end
    end
    return count
end

function D.tryRender(caravan, players, now)
    if now < (caravan.nextRenderAtMs or 0) or now < D.renderCooldownUntilMs then return false end
    if D.countRendered() >= D.maxRendered then return false end
    local row, distance = nearestPlayer(players, caravan.x, caravan.y)
    if row == nil or distance > A.settings.renderRadius or distance < A.settings.minSpawnDistance * 0.6 then return false end
    D.renderCooldownUntilMs = now + 15000
    local ok, reason = A.Spawn.render(caravan, row.player, A.players())
    if ok then
        caravan.state = "rendering"
        caravan.renderingAtMs = now
        A.debug("rendering", caravan.id, "near", row.key, "at", math.floor(caravan.x), math.floor(caravan.y))
        return true
    end
    A.metrics.renderRefused = A.metrics.renderRefused + 1
    caravan.renderFailures = (caravan.renderFailures or 0) + 1
    caravan.nextRenderAtMs = now + 20000 * math.min(6, caravan.renderFailures)
    A.debug("render refused", caravan.id, reason)
    return false
end

function D.onSpawnOutcome(id, outcome)
    local caravan = A.Ledger.get(id)
    if caravan == nil then return end
    if type(outcome) == "table" and outcome.ok == true then
        caravan.state = "rendered"
        caravan.actorUids = {}
        for _, uid in ipairs(outcome.actorUids or {}) do caravan.actorUids[#caravan.actorUids + 1] = uid end
        caravan.renderedAtMs = A.now()
        caravan.renderFailures = 0
        A.metrics.rendered = A.metrics.rendered + 1
        A.log("on the road:", caravan.id, caravan.name, "cars", table.concat(caravan.vehicleIds or {}, ","), "crew", #caravan.actorUids)
        D.publishDirty = true
        return
    end
    local reason = type(outcome) == "table" and tostring(outcome.reason or "unknown") or "unknown"
    A.Spawn.teardown(caravan, "alc_spawn_failed")
    caravan.state = "offline"
    caravan.renderFailures = (caravan.renderFailures or 0) + 1
    caravan.nextRenderAtMs = A.now() + 30000 * math.min(6, caravan.renderFailures)
    A.metrics.renderRefused = A.metrics.renderRefused + 1
    A.log("crew spawn failed:", caravan.id, reason)
    D.publishDirty = true
end

function D.onSessionFinished(caravanId, vehicleId, reason)
    local caravan = A.Ledger.get(caravanId)
    if caravan == nil then return end
    caravan.stranded = caravan.stranded or {}
    caravan.stranded[tostring(vehicleId)] = tostring(reason or "stopped")
    local all = true
    for _, id in ipairs(caravan.vehicleIds or {}) do
        if caravan.stranded[tostring(id)] == nil then all = false end
    end
    if all and caravan.state ~= "fighting" then
        caravan.state = "stranded"
        caravan.strandedAtMs = A.now()
        A.log("stranded:", caravan.id, reason)
        D.publishDirty = true
    end
end

function D.halt(caravan, seconds, reason)
    caravan.halted = true
    caravan.haltUntilMs = A.now() + math.max(5, tonumber(seconds) or A.settings.haltSeconds) * 1000
    caravan.haltReason = reason
    A.metrics.halts = A.metrics.halts + 1
    D.publish(true)
end

function D.resume(caravan)
    caravan.halted = nil
    caravan.haltUntilMs = nil
    caravan.riders = nil
    A.Spawn.setRiders(caravan, false)
    D.publish(true)
end

function D.vehiclePositions(caravan)
    local out, missing = {}, 0
    for _, id in ipairs(caravan.vehicleIds or {}) do
        local car = type(getVehicleById) == "function" and getVehicleById(id) or nil
        local x, y = A.xyz(car)
        if x ~= nil then out[#out + 1] = { id = id, x = x, y = y, vehicle = car } else missing = missing + 1 end
    end
    return out, missing
end

function D.observe(G, caravan, now, players)
    local cars, missing = D.vehiclePositions(caravan)
    if #cars > 0 then
        caravan.x, caravan.y = cars[1].x, cars[1].y
        caravan.missingSinceMs = nil
    else
        caravan.missingSinceMs = caravan.missingSinceMs or now
        if now - caravan.missingSinceMs > 15000 then D.release(caravan, "cars_gone") return end
    end
    local _, distance = nearestPlayer(players, caravan.x, caravan.y)
    if distance > A.settings.releaseRadius then D.release(caravan, "far") return end
    if caravan.halted and caravan.haltUntilMs ~= nil and now >= caravan.haltUntilMs then
        D.resume(caravan)
        local shell = D.driverShell(caravan)
        if shell ~= nil then A.Lines.say(shell, "farewell", { uid = caravan.actorUids and caravan.actorUids[1] }) end
    end
    if caravan.state == "rendered" and (caravan.arrivals or 0) >= math.max(1, #caravan.vehicleIds) then
        caravan.arrivals = 0
        caravan.trips = (caravan.trips or 0) + 1
        if caravan.trips >= A.settings.tripsPerCaravan then
            D.release(caravan, "journey_complete")
            D.retire(caravan, "journey_complete")
            return
        end
        local last = caravan.route[#caravan.route]
        if D.newTrip(G, caravan, last) then
            A.log(caravan.id, "reached", D.nodeName(G, last) .. "; next stop", caravan.destName)
            D.publishDirty = true
        else
            D.release(caravan, "no_next_trip")
            D.retire(caravan, "no_next_trip")
        end
    end
    if caravan.state == "fighting" and now - (caravan.fightingAtMs or now) > 240000 then
        caravan.state = "stranded"
        caravan.strandedAtMs = now
    end
end

function D.driverShell(caravan)
    local uid = caravan.actorUids and caravan.actorUids[1] or nil
    if uid == nil then return nil end
    local p = P()
    if p.Talk ~= nil and type(p.Talk.shellFor) == "function" then
        local ok, shell = pcall(p.Talk.shellFor, uid)
        if ok and shell ~= nil then return shell, uid end
    end
    if p.Speech ~= nil and type(p.Speech.findShell) == "function" then
        local ok, shell = pcall(p.Speech.findShell, uid)
        if ok and shell ~= nil then return shell, uid end
    end
    return nil, uid
end

-- Driving-side view of every caravan car (single player: direct; multiplayer: broadcast).
function D.knownTable()
    local known = {}
    for _, caravan in ipairs(A.Ledger.list()) do
        if caravan.state == "rendered" or caravan.state == "rendering" then
            for _, id in ipairs(caravan.vehicleIds or {}) do
                local goals = {}
                for index = caravan.goalIndex or 1, #(caravan.goals or {}) do
                    goals[#goals + 1] = { x = caravan.goals[index].x, y = caravan.goals[index].y }
                    if #goals >= 40 then break end
                end
                known[id] = { caravanId = caravan.id, name = caravan.name, factionId = caravan.factionId, kind = caravan.kind,
                    speedKmh = caravan.speedKmh, goals = goals, halted = caravan.halted == true, dest = caravan.destName,
                    hostile = caravan.hostile == true, riders = caravan.riders == true, trade = caravan.offers ~= nil and #caravan.offers > 0 }
            end
        end
    end
    return known
end

function D.publish(force)
    local now = A.now()
    if not force and not D.publishDirty and now < D.publishAtMs then return end
    D.publishAtMs = now + 5000
    D.publishDirty = false
    local known = D.knownTable()
    if A.side() == "server" then
        pcall(sendServerCommand, A.MODULE, "state", { known = known })
    else
        A.Convoy.setKnown(known)
    end
end

function D.sendState(player)
    if A.side() == "server" then pcall(sendServerCommand, player, A.MODULE, "state", { known = D.knownTable() }) end
end

-- Reports from the driving side (car arrived at the last goal).
function D.onConvoyReport(player, command, args)
    if type(args) ~= "table" then return end
    local caravan = A.Ledger.byVehicle(args.vehicleId)
    if caravan == nil then return end
    if command == "arrived" then
        caravan.arrivals = (caravan.arrivals or 0) + 1
        local shell = D.driverShell(caravan)
        if shell ~= nil then A.Lines.say(shell, "arrive", { uid = caravan.actorUids[1], vars = { dest = caravan.destName } }) end
    end
end

function D.step(G, caravan, now, dt, players)
    local state = caravan.state or "offline"
    if state == "offline" then
        local result = D.advance(G, caravan, dt)
        if result == "end" then
            caravan.trips = (caravan.trips or 0) + 1
            if caravan.trips >= A.settings.tripsPerCaravan then D.retire(caravan, "journey_complete") return end
            if not D.newTrip(G, caravan, caravan.route[#caravan.route]) then D.retire(caravan, "no_next_trip") return end
        end
        D.tryRender(caravan, players, now)
    elseif state == "rendering" then
        if now - (caravan.renderingAtMs or now) > 120000 then
            A.Spawn.teardown(caravan, "alc_render_timeout")
            caravan.state = "offline"
            caravan.nextRenderAtMs = now + 60000
            A.log("render timed out:", caravan.id)
        end
    elseif state == "rendered" or state == "fighting" then
        D.observe(G, caravan, now, players)
    elseif state == "stranded" then
        local _, distance = nearestPlayer(players, caravan.x or 0, caravan.y or 0)
        if distance > A.settings.releaseRadius or now - (caravan.strandedAtMs or now) > 1800000 then
            -- crew back into the ledger, cars stay where they stopped
            A.Spawn.teardownActors(caravan.actorUids, "alc_stranded")
            caravan.actorUids = {}
            caravan.vehicleIds = {}
            D.retire(caravan, "stranded")
        end
    end
end

function D.tick()
    if not A.authority() then return end
    local now = A.now()
    if now < D.nextTickMs then return end
    D.nextTickMs = now + D.intervalMs
    local dt = D.lastTickMs and math.min(10, (now - D.lastTickMs) / 1000) or 0
    D.lastTickMs = now
    if not A.settings.enabled then return end
    local G = D.graph()
    if G == nil then return end
    local players = D.playerRows()
    local store = A.Ledger.open()
    if A.Ledger.count() < A.settings.maxCaravans and now >= (tonumber(store.nextFoundAtMs) or 0) then
        local ok, result = D.found(now, players)
        local base = A.settings.foundIntervalMinutes * 60000
        store.nextFoundAtMs = now + (ok and (base * (0.7 + A.randFloat() * 0.6)) or 30000)
        if not ok then A.debug("founding skipped:", result) end
    end
    for _, caravan in ipairs(A.Ledger.list()) do
        local ok, err = pcall(D.step, G, caravan, now, dt, players)
        if not ok then A.fail("director step " .. tostring(caravan.id), err) end
    end
    D.publish(false)
end

function D.describe()
    local lines = {}
    local G = D.graph()
    for _, caravan in ipairs(A.Ledger.list()) do
        lines[#lines + 1] = string.format("%s %s [%s] %s at %d,%d leg %d/%d -> %s cars=%d crew=%d%s",
            tostring(caravan.id), tostring(caravan.name), tostring(caravan.kind), tostring(caravan.state),
            math.floor(caravan.x or 0), math.floor(caravan.y or 0), caravan.leg or 1, math.max(1, #(caravan.route or {}) - 1),
            tostring(caravan.destName), #(caravan.vehicleIds or {}), #(caravan.actorUids or {}),
            caravan.halted and " HALTED" or "")
    end
    if #lines == 0 then lines[1] = "no caravans" .. (G == nil and " (no road graph)" or "") end
    return lines
end

return D
