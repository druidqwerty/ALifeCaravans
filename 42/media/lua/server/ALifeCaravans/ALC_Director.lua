-- A-Life: Caravans - the director (server / single player). Founds caravans in
-- towns of A-Life's road graph, moves them along town-to-town routes while no
-- player is near ("ledger": fast far away, slowing to the cruising speed as a
-- player comes close so nothing pops), puts them on the road through ALC_Spawn
-- when a player comes within the render radius (two units for 3-4 cars),
-- follows them while they drive (re-crews a car after its driver died, leaves
-- cars without fuel or engine behind, releases a stuck caravan only out of
-- sight), runs escorts, ambushes and radio chatter, and takes them back into
-- the ledger when every player is far away.

require "ALifeCaravans/00_ALC_Core"
require "ALifeCaravans/01_ALC_Lines"
require "ALifeCaravans/02_ALC_Vehicles"
require "ALifeCaravans/03_ALC_Roads"
require "ALifeCaravans/04_ALC_Convoy"
require "ALifeCaravans/05_ALC_Trade"
require "ALifeCaravans/ALC_Ledger"
require "ALifeCaravans/ALC_Spawn"
require "ALifeCaravans/ALC_SOSMonitor"

local A = ALifeCaravans
local D = { nextTickMs = 0, intervalMs = 2000, lastTickMs = nil, renderCooldownUntilMs = 0, publishAtMs = 0,
    publishDirty = false, maxRendered = 3, maxCars = 8, goalSpacing = 55, radioAtMs = 0, radioEveryMs = 300000,
    arrivalPauseSeconds = 60, escortRadius = 70, escortGraceMs = 60000, ambushLead = 60, outOfSight = 60,
    eventCheckAtMs = 0, eventEveryMs = 1800000, scavengingCheckAtMs = 0, scavengingEveryMs = 300000,
    breakdownCheckAtMs = 0, refuelCheckAtMs = 0, mergeCheckAtMs = 0, mergeEveryMs = 600000,
    weatherCheckAtMs = 0, weatherEveryMs = 60000, distressCheckAtMs = 0, distressEveryMs = 120000,
    livingWorldCheckAtMs = 0, livingWorldEveryMs = 300000 }
A.Director = D

local KIND_BY_CLASS = { military = "convoy", police = "patrol", rescue = "rescue", trade = "trade", raider = "raid", civilian = "trade" }
D.callsigns = { "Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot", "Golf", "Hotel", "Kilo", "Lima", "Mike",
    "November", "Oscar", "Papa", "Romeo", "Sierra", "Tango", "Victor", "Whiskey", "Yankee", "Zulu" }

local function P() return ProjectALife end

function D.graph()
    local p = P()
    local G = p and p.RoadGraph or nil
    if G == nil or type(G.nodes) ~= "table" then return nil end
    if A.isEmpty(G.nodes) and type(G.importShipped) == "function" then pcall(G.importShipped) end
    if A.isEmpty(G.nodes) then return nil end
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

local function playerByKey(rows, key)
    for _, row in ipairs(rows) do if row.key == key then return row end end
    return nil
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

-- A persistent leader: the first crew profile's name and a convoy callsign.
function D.leaderFor(catalog, crew, seed)
    local p = P()
    local name = "Leader"
    local profile = nil
    if p and p.Catalog and type(p.Catalog.npc) == "function" and crew[1] then
        local ok, found = pcall(p.Catalog.npc, crew[1])
        if ok then profile = found end
    end
    if profile ~= nil and profile.general and type(profile.general.name) == "string" and profile.general.name ~= "" then
        name = profile.general.name
    end
    local hash = A.hash(tostring(seed) .. tostring(crew[1]))
    local callsign = D.callsigns[hash % #D.callsigns + 1] .. "-" .. tostring(hash % 9 + 1)
    return name, callsign
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

-- Heading of the ledger travel (radians) for the map markers.
function D.heading(G, caravan)
    local route = caravan.route or {}
    local leg = caravan.leg or 1
    local na, nb = G.nodes[route[leg]], G.nodes[route[leg + 1]]
    if na == nil or nb == nil then return 0 end
    return A.atan2(nb.y - na.y, nb.x - na.x)
end

-- Ledger speed multiplier: the full offline percentage far away, easing down to
-- the cruising speed (1.0) within the render radius so a caravan a player
-- approaches does not jump.
function D.speedFactor(distance)
    local radius = A.settings.renderRadius
    local far = A.settings.offlineSpeedPercent / 100
    if distance == nil or distance == math.huge then return far end
    if distance <= radius then return 1 end
    return A.lerp(1, far, (distance - radius) / (radius * 1.5))
end

-- Advance the ledger position by dt seconds of real time.
function D.advance(G, caravan, dt, players)
    local route = caravan.route or {}
    if route[(caravan.leg or 1) + 1] == nil then return "end" end
    local _, distance = nearestPlayer(players or {}, caravan.x or 0, caravan.y or 0)
    local factor = D.speedFactor(#(players or {}) > 0 and distance or nil)
    local tilesPerSecond = (tonumber(caravan.speedKmh) or A.settings.cruiseKmh) / 3.6 * factor
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

function D.refreshStock(caravan)
    caravan.stock = A.Trade.stockFor(caravan.kind)
end

function D.newTrip(G, caravan, fromId)
    local route = D.planRoute(G, fromId, 2 + A.rand(3))
    if route == nil then return false end
    caravan.route, caravan.leg, caravan.t = route, 1, 0
    caravan.destName = D.nodeName(G, route[#route])
    caravan.goals = D.goalsFor(G, caravan)
    caravan.goalIndex = 1
    caravan.arrivals = 0
    caravan.trip = (caravan.trip or 0) + 1
    caravan.ambush = nil
    D.refreshStock(caravan)
    D.armAmbush(caravan)
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
    local class = A.Vehicles.classFor(faction)
    local maxVehicles = A.settings.maxVehicles
    if class ~= "military" and class ~= "police" and maxVehicles > 2 then maxVehicles = 2 + A.rand(maxVehicles - 1) end
    local crewCount = A.settings.crewMin + A.rand(A.settings.crewMax - A.settings.crewMin + 1)
    local vehicles, seats = A.Vehicles.convoy(class, crewCount, maxVehicles)
    if #vehicles == 0 then return false, "no_vehicles" end
    crewCount = math.max(2, #vehicles, math.min(crewCount, seats, 16))
    local crew = D.crewFor(catalog, faction, crewCount)
    if crew == nil then return false, "no_profiles" end
    local towns = {}
    for id, node in pairs(G.nodes) do
        if node.kind == nil or node.kind == "town" then towns[#towns + 1] = id end
    end
    table.sort(towns)
    if #towns < 2 then return false, "no_towns" end
    local candidates = {}
    for _, id in ipairs(towns) do
        local node = G.nodes[id]
        local _, d = nearestPlayer(players, node.x, node.y)
        if #players == 0 or (d >= 150 and d <= 900) then candidates[#candidates + 1] = id end
    end
    if #candidates == 0 then candidates = towns end
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
    if route == nil or bestD < A.settings.renderRadius then return false, "no_route" end
    local kind = KIND_BY_CLASS[class] or "trade"
    local rules = P().FactionSpawnRules
    local hostile = rules ~= nil and type(rules.hostile) == "function" and rules.hostile(faction) == true or false
    if hostile and kind ~= "convoy" and kind ~= "patrol" then kind = "raid" end
    local speed = A.settings.cruiseKmh
    if class == "military" then speed = speed - 5 elseif class == "raider" then speed = speed + 5 end
    local factionName = tostring(faction.general and faction.general.name or faction.id)
    local caravan = {
        name = factionName, factionId = faction.id, factionName = factionName,
        kind = kind, class = class, hostile = hostile,
        vehicles = vehicles, crew = crew, speedKmh = math.max(10, math.min(70, speed)),
        route = route, leg = 1, t = 0, trips = 0, trip = 0, state = "offline", createdMs = now, lastMs = now,
        vehicleIds = {}, actorUids = {}, abandoned = {}, renderFailures = 0, nextRenderAtMs = 0, truce = {}, goalIndex = 1, units = 0,
    }
    caravan.leaderName, caravan.callsign = D.leaderFor(catalog, crew, now)
    caravan.destName = D.nodeName(G, route[#route])
    caravan.goals = D.goalsFor(G, caravan)
    caravan.trip = 1
    D.refreshStock(caravan)
    D.armAmbush(caravan)
    local point = D.offlinePosition(G, caravan)
    if point ~= nil then caravan.x, caravan.y = point.x, point.y end
    A.Ledger.create(caravan)
    A.metrics.founded = A.metrics.founded + 1
    A.log("founded", caravan.id, caravan.name, caravan.callsign, "(" .. kind .. ", " .. #crew .. " crew, " .. #vehicles .. " car(s))",
        "from", D.nodeName(G, route[1]), "to", caravan.destName)
    return true, caravan
end

function D.retire(caravan, reason)
    A.SOS.finish(caravan, false, "lost")
    if caravan.state == "rendered" or caravan.state == "rendering" or caravan.state == "fighting" or caravan.state == "stranded" then
        A.Spawn.teardown(caravan, "alc_retire")
    end
    A.Ledger.remove(caravan.id)
    A.metrics.retired = A.metrics.retired + 1
    A.debug("retired", caravan.id, reason)
    D.publishDirty = true
end

function D.release(caravan, reason)
    A.SOS.onRelease(caravan, reason)
    local G = D.graph()
    local kept = A.Spawn.teardown(caravan, "alc_release")
    if G ~= nil and caravan.x ~= nil then D.snapProgress(G, caravan, caravan.x, caravan.y) end
    caravan.state = "offline"
    caravan.halted, caravan.haltUntilMs, caravan.riders, caravan.recrew, caravan.stuckReport = nil, nil, nil, nil, nil
    caravan.ambush = caravan.ambush and caravan.ambush.state == "armed" and caravan.ambush or nil
    caravan.units = 0
    caravan.nextRenderAtMs = A.now() + 30000
    if G ~= nil then caravan.goals = D.goalsFor(G, caravan) caravan.goalIndex = 1 end
    A.metrics.released = A.metrics.released + 1
    A.log("released", caravan.id, reason, #kept > 0 and ("(" .. #kept .. " car(s) left with players inside)") or "")
    D.publishDirty = true
    A.Ledger.touch()
end

function D.countRendered()
    local count, cars = 0, 0
    for _, caravan in ipairs(A.Ledger.list()) do
        if caravan.state == "rendering" or caravan.state == "rendered" or caravan.state == "fighting" then
            count = count + 1
            cars = cars + #(caravan.vehicleIds or {})
        end
    end
    return count, cars
end

function D.tryRender(caravan, players, now)
    if now < (caravan.nextRenderAtMs or 0) or now < D.renderCooldownUntilMs then return false end
    local rendered, cars = D.countRendered()
    if rendered >= D.maxRendered or cars + math.min(2, #(caravan.vehicles or {})) > D.maxCars then return false end
    local row, distance = nearestPlayer(players, caravan.x, caravan.y)
    if row == nil or distance > A.settings.renderRadius or distance < A.settings.minSpawnDistance * 0.6 then return false end
    D.renderCooldownUntilMs = now + 15000
    local ok, reason = A.Spawn.render(caravan, row.player, A.players(), 1)
    if ok then
        caravan.state = "rendering"
        caravan.renderingAtMs = now
        caravan.renderUnit = 1
        caravan.actorUids = {}
        A.debug("rendering", caravan.id, "near", row.key, "at", math.floor(caravan.x), math.floor(caravan.y))
        return true
    end
    A.metrics.renderRefused = A.metrics.renderRefused + 1
    caravan.renderFailures = (caravan.renderFailures or 0) + 1
    caravan.nextRenderAtMs = now + 20000 * math.min(6, caravan.renderFailures)
    A.debug("render refused", caravan.id, reason)
    return false
end

function D.onSpawnOutcome(id, outcome, unit)
    local caravan = A.Ledger.get(id)
    if caravan == nil then return end
    unit = unit or 1
    if type(outcome) == "table" and outcome.ok == true then
        caravan.actorUids = caravan.actorUids or {}
        for _, uid in ipairs(outcome.actorUids or {}) do caravan.actorUids[#caravan.actorUids + 1] = uid end
        caravan.units = unit
        caravan.renderFailures = 0
        if unit == 1 and #(caravan.vehicles or {}) > 2 then
            caravan.state = "rendering"
            caravan.pendingUnit = 2
            caravan.unitAtMs = A.now() + 2500
            A.debug("unit 1 on the road:", caravan.id, "waiting to place unit 2")
            return
        end
        caravan.state = "rendered"
        caravan.pendingUnit = nil
        caravan.renderedAtMs = A.now()
        A.metrics.rendered = A.metrics.rendered + 1
        A.log("on the road:", caravan.id, caravan.name, caravan.callsign, "cars", table.concat(caravan.vehicleIds or {}, ","), "crew", #caravan.actorUids)
        D.publishDirty = true
        return
    end
    local reason = type(outcome) == "table" and tostring(outcome.reason or "unknown") or "unknown"
    if unit == 2 then
        -- the convoy drives on with its first unit
        A.log("unit 2 spawn failed:", caravan.id, reason)
        for index = #caravan.vehicleIds, 1, -1 do
            local car = getVehicleById(caravan.vehicleIds[index])
            local _, carIndex = A.vehicleTag(car)
            if car ~= nil and (tonumber(carIndex) or 0) > 2 then
                A.Spawn.teardownVehicles({ caravan.vehicleIds[index] })
                table.remove(caravan.vehicleIds, index)
            end
        end
        caravan.state = "rendered"
        caravan.pendingUnit = nil
        caravan.renderedAtMs = A.now()
        A.metrics.rendered = A.metrics.rendered + 1
        D.publishDirty = true
        return
    end
    A.Spawn.teardown(caravan, "alc_spawn_failed")
    caravan.state = "offline"
    caravan.units = 0
    caravan.renderFailures = (caravan.renderFailures or 0) + 1
    caravan.nextRenderAtMs = A.now() + 30000 * math.min(6, caravan.renderFailures)
    A.metrics.renderRefused = A.metrics.renderRefused + 1
    A.log("crew spawn failed:", caravan.id, reason)
    D.publishDirty = true
end

-- A driving session of one of our cars ended (A-Life released the crew).
function D.onSessionFinished(caravanId, vehicleId, reason)
    local caravan = A.Ledger.get(caravanId)
    if caravan == nil or vehicleId == nil then return end
    reason = tostring(reason or "stopped")
    if caravan.ambush ~= nil and caravan.ambush.state == "fighting" then return end
    if caravan.state ~= "rendered" and caravan.state ~= "fighting" then return end
    caravan.recrew = caravan.recrew or {}
    caravan.recrewCount = caravan.recrewCount or {}
    local key = tostring(vehicleId)
    caravan.recrewCount[key] = (caravan.recrewCount[key] or 0) + 1
    if caravan.recrewCount[key] > 3 then
        A.log(caravan.id, "car", vehicleId, "gave up after repeated stops:", reason)
        D.abandonCar(caravan, vehicleId, "stops")
        return
    end
    caravan.recrew[key] = { dueMs = A.now() + 4000, reason = reason, vehicleId = vehicleId }
    A.log(caravan.id, "car", vehicleId, "stopped (" .. reason .. "); re-crewing")
    if string.find(reason, "Driver died", 1, true) or string.find(reason, "died", 1, true) then
        local shell = D.driverShell(caravan)
        if shell ~= nil then A.Lines.say(shell, "driver_down", { uid = caravan.actorUids and caravan.actorUids[1], cooldownMs = 30000 }) end
    end
    D.publishDirty = true
end

function D.abandonCar(caravan, vehicleId, why)
    A.Spawn.abandon(caravan, vehicleId)
    caravan.recrew = caravan.recrew or {}
    caravan.recrew[tostring(vehicleId)] = nil
    A.log(caravan.id, "car", vehicleId, "abandoned:", why)
    local shell = D.driverShell(caravan)
    if shell ~= nil then A.Lines.say(shell, "abandon", { uid = caravan.actorUids and caravan.actorUids[1], cooldownMs = 30000 }) end
    if #(caravan.vehicleIds or {}) == 0 then
        caravan.state = "stranded"
        caravan.strandedAtMs = A.now()
        A.log("stranded:", caravan.id, why)
    end
    D.publishDirty = true
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
    caravan.haltReason = nil
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

function D.ridersAboard(caravan)
    for _, id in ipairs(caravan.vehicleIds or {}) do
        local car = getVehicleById(id)
        if car ~= nil and A.vehicleHasPlayer(car) then return true end
    end
    return false
end

-- Re-crew requests that came due; cars nobody can drive are abandoned.
function D.recrewTick(caravan, now)
    local pending = 0
    for _, request in pairs(caravan.recrew or {}) do if now >= (request.dueMs or 0) then pending = pending + 1 end end
    if pending == 0 then return end
    local free = 0
    for _, row in ipairs(A.Spawn.survivors(caravan, caravan.x or 0, caravan.y or 0, 60)) do
        if row.inCar == nil then free = free + 1 end
    end
    local limit = math.max(1, math.ceil(free / pending))
    local reserved = {}
    for key, request in pairs(caravan.recrew or {}) do
        if now >= (request.dueMs or 0) then
            local ok, detail = A.Spawn.recrew(caravan, request.vehicleId, nil, limit, reserved)
            if ok then
                caravan.recrew[key] = nil
                A.log(caravan.id, "car", request.vehicleId, "re-crewed with", detail, "NPC(s)")
                D.publishDirty = true
            else
                request.tries = (request.tries or 0) + 1
                request.dueMs = now + 5000
                if request.tries >= 6 or detail == "no_survivors" or detail == "no_car" then
                    D.abandonCar(caravan, request.vehicleId, tostring(detail))
                end
            end
        end
    end
end

-- Cars without fuel or a working engine are left behind.
function D.carsTick(caravan, now)
    if not A.settings.abandonCars or now < (caravan.carCheckAtMs or 0) then return end
    caravan.carCheckAtMs = now + 10000
    for _, id in ipairs(A.copy(caravan.vehicleIds or {})) do
        local car = getVehicleById(id)
        if car ~= nil and not A.vehicleHasPlayer(car) then
            local fuel, engine = A.Spawn.carHealth(car)
            if fuel <= 0.3 or engine == false then D.abandonCar(caravan, id, fuel <= 0.3 and "no fuel" or "engine dead") end
        end
    end
end

-- Escort contract: the escorting player must stay within escortRadius.
function D.escortTick(caravan, now, players)
    local escort = caravan.escort
    if escort == nil then return end
    local row = playerByKey(players, escort.playerKey)
    local lead = caravan.x and { x = caravan.x, y = caravan.y } or nil
    if row ~= nil and lead ~= nil and A.dist(row.x, row.y, lead.x, lead.y) <= D.escortRadius then
        escort.lastSeenMs = now
    elseif now - (escort.lastSeenMs or now) > D.escortGraceMs then
        caravan.escort = nil
        A.Ledger.addFavor(escort.playerKey, caravan.factionId, -1)
        local shell = D.driverShell(caravan)
        if shell ~= nil then A.Lines.say(shell, "escort_void", { uid = caravan.actorUids and caravan.actorUids[1] }) end
        A.log(caravan.id, "escort by", escort.playerKey, "void: left the convoy")
        D.publishDirty = true
    end
end

function D.armAmbush(caravan)
    caravan.ambush = nil
    if A.settings.ambushPercent <= 0 or caravan.kind == "raid" then return end
    if A.rand(100) >= A.settings.ambushPercent then return end
    local goals = caravan.goals or {}
    if #goals < 4 then return end
    local index = 2 + A.rand(#goals - 3)
    local kind = "zombies"
    if A.settings.allowHostile and A.rand(100) < 40 then kind = "raiders" end
    caravan.ambush = { kind = kind, goalIndex = index, state = "armed", x = goals[index].x, y = goals[index].y }
end

-- Ambush state machine: armed -> fighting (crew out) -> boarding (back in) -> done.
function D.ambushTick(caravan, now, players)
    local ambush = caravan.ambush
    if ambush == nil or caravan.state ~= "rendered" then return end
    if ambush.state == "armed" then
        local row, distance = nearestPlayer(players, ambush.x, ambush.y)
        if row == nil or distance > 90 then return end
        if A.dist(caravan.x, caravan.y, ambush.x, ambush.y) > D.ambushLead then return end
        local ok, reason = A.Spawn.ambush(caravan, ambush.kind, ambush.x, ambush.y, row.player)
        if not ok then
            A.debug("ambush skipped:", caravan.id, reason)
            caravan.ambush = nil
            return
        end
        ambush.state = "fighting"
        ambush.sinceMs = now
        if A.SOS.start(caravan, now) then D.distressCheckAtMs = 0 end
        A.metrics.ambushes = A.metrics.ambushes + 1
        D.halt(caravan, 300, "ambush")
        local shell = D.driverShell(caravan)
        if shell ~= nil then A.Lines.say(shell, ambush.kind == "raiders" and "ambush_raiders" or "ambush_zombies", { uid = caravan.actorUids[1] }) end
        A.Spawn.dismount(caravan, { x = ambush.x, y = ambush.y })
        A.log(caravan.id, "ambush:", ambush.kind, "at", math.floor(ambush.x), math.floor(ambush.y))
        if caravan.escort ~= nil then caravan.escort.ambushed = true end
    elseif ambush.state == "fighting" then
        local clear = A.Spawn.zombiesNear(caravan.x, caravan.y, 18) == 0
        if ambush.kind == "raiders" then clear = now - ambush.sinceMs > 60000 end
        if clear then
            ambush.clearSinceMs = ambush.clearSinceMs or now
        else
            ambush.clearSinceMs = nil
        end
        if (ambush.clearSinceMs ~= nil and now - ambush.clearSinceMs > 10000) or now - ambush.sinceMs > 150000 then
            ambush.state = "boarding"
            ambush.boardingAtMs = now
            caravan.halted, caravan.haltUntilMs = nil, nil
            local shell = D.driverShell(caravan)
            if shell ~= nil then A.Lines.say(shell, "ambush_clear", { uid = caravan.actorUids[1] }) end
            caravan.recrew = caravan.recrew or {}
            for _, id in ipairs(caravan.vehicleIds or {}) do
                caravan.recrew[tostring(id)] = { dueMs = now + 1000, reason = "ambush", vehicleId = id }
            end
            if caravan.escort ~= nil and caravan.escort.ambushed then
                A.Ledger.addFavor(caravan.escort.playerKey, caravan.factionId, 2)
            end
            D.publish(true)
        end
    elseif ambush.state == "boarding" then
        if A.isEmpty(caravan.recrew) or now - ambush.boardingAtMs > 120000 then caravan.ambush = nil end
    end
end

-- Convoy chatter on A-Life's Knox County Radio when a caravan is in range.
function D.radioTick(now, players)
    if not A.settings.radioChatter or now < D.radioAtMs then return end
    D.radioAtMs = now + D.radioEveryMs
    local radio = P() and P().KnoxCountyRadio
    if radio == nil or type(radio.enabled) ~= "function" or radio.channel == nil then return end
    local ok, enabled = pcall(radio.enabled)
    if not ok or not enabled then return end
    local best, bestD = nil, 600
    for _, caravan in ipairs(A.Ledger.list()) do
        local _, d = nearestPlayer(players, caravan.x or 0, caravan.y or 0)
        if d < bestD and caravan.kind ~= "raid" then best, bestD = caravan, d end
    end
    if best == nil or type(RadioBroadCast) ~= "table" and type(RadioBroadCast) ~= "userdata" then return end
    local text = A.Lines.text("radio", D.vars(best))
    if text == nil then return end
    local sent = pcall(function()
        local channel = radio.channel
        if channel:getAiringBroadcast() ~= nil then error("busy") end
        local broadcast = RadioBroadCast.new("alc-" .. tostring(now), -1, -1)
        broadcast:AddRadioLine(RadioLine.new(text, 0.8, 0.9, 0.75))
        channel:setAiringBroadcast(broadcast)
    end)
    if sent then A.metrics.radio = A.metrics.radio + 1 end
end

function D.vars(caravan)
    local town
    local speech = P() and P().Speech
    if speech ~= nil and type(speech.nearestTown) == "function" then
        local ok, name = pcall(speech.nearestTown, caravan.x or 0, caravan.y or 0)
        if ok and type(name) == "string" and name ~= "" then town = name end
    end
    local day = D.clock()
    return { dest = tostring(caravan.destName or "?"), town = tostring(town or caravan.destName or "?"),
        faction = tostring(caravan.factionName or caravan.name), name = tostring(caravan.callsign or caravan.name),
        leader = tostring(caravan.leaderName or "the driver"), day = tostring(day) }
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
    caravan.ridersAboard = D.ridersAboard(caravan)
    local _, distance = nearestPlayer(players, caravan.x, caravan.y)
    if distance > A.settings.releaseRadius and not caravan.ridersAboard then D.release(caravan, "far") return end
    if caravan.halted and caravan.haltUntilMs ~= nil and now >= caravan.haltUntilMs and not (caravan.ambush and caravan.ambush.state == "fighting") then
        D.resume(caravan)
        local shell = D.driverShell(caravan)
        if shell ~= nil then A.Lines.say(shell, "farewell", { uid = caravan.actorUids and caravan.actorUids[1] }) end
    end
    D.recrewTick(caravan, now)
    D.carsTick(caravan, now)
    D.escortTick(caravan, now, players)
    D.ambushTick(caravan, now, players)
    local stuck = caravan.stuckReport
    if stuck ~= nil and now - stuck.atMs < 90000 then
        local _, d = nearestPlayer(players, stuck.x, stuck.y)
        if d > D.outOfSight and not caravan.ridersAboard then D.release(caravan, "stuck_out_of_sight") return end
    end
    if caravan.state == "rendered" and (caravan.arrivals or 0) >= math.max(1, #caravan.vehicleIds) then
        caravan.arrivals = 0
        caravan.trips = (caravan.trips or 0) + 1
        local shell = D.driverShell(caravan)
        if caravan.escort ~= nil and A.Interact ~= nil and type(A.Interact.escortReward) == "function" then
            pcall(A.Interact.escortReward, caravan, players)
        end
        if caravan.trips >= A.settings.tripsPerCaravan then
            D.release(caravan, "journey_complete")
            D.retire(caravan, "journey_complete")
            return
        end
        local last = caravan.route[#caravan.route]
        if D.newTrip(G, caravan, last) then
            A.log(caravan.id, "reached", D.nodeName(G, last) .. "; next stop", caravan.destName)
            D.halt(caravan, math.min(A.settings.haltSeconds, D.arrivalPauseSeconds), "arrived")
            if shell ~= nil then A.Lines.say(shell, caravan.ridersAboard and "arrive_riders" or "arrive", { uid = caravan.actorUids[1], vars = D.vars(caravan) }) end
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
            for index, id in ipairs(caravan.vehicleIds or {}) do
                local goals = {}
                for goalIndex = caravan.goalIndex or 1, #(caravan.goals or {}) do
                    goals[#goals + 1] = { x = caravan.goals[goalIndex].x, y = caravan.goals[goalIndex].y }
                    if #goals >= 40 then break end
                end
                known[id] = { caravanId = caravan.id, index = index, name = caravan.name, callsign = caravan.callsign, leader = caravan.leaderName,
                    factionId = caravan.factionId, kind = caravan.kind, speedKmh = caravan.speedKmh, goals = goals, trip = caravan.trip or 1,
                    halted = caravan.halted == true, dest = caravan.destName, hostile = caravan.hostile == true, riders = caravan.riders == true,
                    sosState = caravan.sos and caravan.sos.state, sosOwner = caravan.sos and caravan.sos.owner,
                    trade = caravan.stock ~= nil and #caravan.stock > 0, escort = caravan.escort ~= nil and caravan.escort.playerKey or nil }
            end
        end
    end
    return known
end

-- Map markers of every caravan (ledger and on the road).
function D.markerTable()
    local markers = {}
    if not A.settings.markers then return markers end
    local G = D.graph()
    for _, caravan in ipairs(A.Ledger.list()) do
        if caravan.x ~= nil then
            markers[#markers + 1] = { id = caravan.id, name = caravan.name, callsign = caravan.callsign, kind = caravan.kind,
                x = math.floor(caravan.x), y = math.floor(caravan.y), heading = G and D.heading(G, caravan) or 0,
                state = caravan.state, halted = caravan.halted == true, dest = caravan.destName, cars = #(caravan.vehicles or {}) }
            markers[#markers].sos = A.SOS.active(caravan)
        end
    end
    return markers
end

function D.publish(force)
    local now = A.now()
    if not force and not D.publishDirty and now < D.publishAtMs then return end
    D.publishAtMs = now + 4000
    D.publishDirty = false
    local known, markers = D.knownTable(), D.markerTable()
    if A.side() == "server" then
        pcall(sendServerCommand, A.MODULE, "state", { known = known, markers = markers })
    else
        A.Convoy.setKnown(known)
        if A.Client ~= nil and type(A.Client.setMarkers) == "function" then pcall(A.Client.setMarkers, markers) end
    end
end

function D.sendState(player)
    if A.side() == "server" then pcall(sendServerCommand, player, A.MODULE, "state", { known = D.knownTable(), markers = D.markerTable() }) end
end

-- Reports from the driving side.
function D.onConvoyReport(player, command, args)
    if type(args) ~= "table" then return end
    local caravan = A.Ledger.byVehicle(args.vehicleId)
    if caravan == nil then return end
    if command == "arrived" then
        caravan.arrivals = (caravan.arrivals or 0) + 1
    elseif command == "stuck" then
        caravan.stuckReport = { vehicleId = args.vehicleId, x = tonumber(args.x) or caravan.x, y = tonumber(args.y) or caravan.y, atMs = A.now() }
        A.log(caravan.id, "car", args.vehicleId, "reports itself stuck")
    end
end

function D.step(G, caravan, now, dt, players)
    local state = caravan.state or "offline"
    if state == "offline" then
        local result = D.advance(G, caravan, dt, players)
        if result == "end" then
            caravan.trips = (caravan.trips or 0) + 1
            if caravan.trips >= A.settings.tripsPerCaravan then D.retire(caravan, "journey_complete") return end
            if not D.newTrip(G, caravan, caravan.route[#caravan.route]) then D.retire(caravan, "no_next_trip") return end
        end
        D.tryRender(caravan, players, now)
    elseif state == "rendering" then
        if caravan.pendingUnit == 2 and now >= (caravan.unitAtMs or 0) then
            caravan.pendingUnit = nil
            local row = nearestPlayer(players, caravan.x, caravan.y)
            local ok, reason = false, "no_player"
            if row ~= nil then ok, reason = A.Spawn.render(caravan, row.player, A.players(), 2) end
            if ok then
                caravan.renderUnit = 2
                caravan.renderingAtMs = now
            else
                A.log("unit 2 not placed:", caravan.id, reason)
                caravan.state = "rendered"
                caravan.renderedAtMs = now
                A.metrics.rendered = A.metrics.rendered + 1
                D.publishDirty = true
            end
        elseif now - (caravan.renderingAtMs or now) > 120000 then
            A.Spawn.teardown(caravan, "alc_render_timeout")
            caravan.state = "offline"
            caravan.units = 0
            caravan.nextRenderAtMs = now + 60000
            A.log("render timed out:", caravan.id)
        end
    elseif state == "rendered" or state == "fighting" then
        D.observe(G, caravan, now, players)
    elseif state == "stranded" then
        local _, distance = nearestPlayer(players, caravan.x or 0, caravan.y or 0)
        if distance > A.settings.releaseRadius or now - (caravan.strandedAtMs or now) > 1800000 then
            A.Spawn.teardownActors(caravan.actorUids, "alc_stranded")
            caravan.actorUids = {}
            caravan.vehicleIds = {}
            D.retire(caravan, "stranded")
        end
    end
end

-- NEW FEATURE: Event caravans (supply drops, refugees, etc.)
function D.eventCaravanTick(now, players)
    if not A.settings.eventCaravans or now < D.eventCheckAtMs then return end
    D.eventCheckAtMs = now + D.eventEveryMs
    if A.rand(100) >= 15 then return end -- 15% chance per check
    local G = D.graph()
    if G == nil then return end
    local eventTypes = { "supply_drop", "refugees", "medical_aid", "trade_fair", "scavenger_haul" }
    local eventType = eventTypes[A.rand(#eventTypes) + 1]
    local faction, catalog = D.pickFaction()
    if faction == nil then return end
    local class = A.Vehicles.classFor(faction)
    local maxVehicles = A.settings.maxVehicles
    if class ~= "military" and class ~= "police" and maxVehicles > 2 then maxVehicles = 2 + A.rand(maxVehicles - 1) end
    local crewCount = A.settings.crewMin + A.rand(A.settings.crewMax - A.settings.crewMin + 1)
    local vehicles, seats = A.Vehicles.convoy(class, crewCount, maxVehicles)
    if #vehicles == 0 then return end
    crewCount = math.max(2, #vehicles, math.min(crewCount, seats, 16))
    local crew = D.crewFor(catalog, faction, crewCount)
    if crew == nil then return end
    local towns = {}
    for id, node in pairs(G.nodes) do if node.kind == nil or node.kind == "town" then towns[#towns + 1] = id end end
    table.sort(towns)
    if #towns < 2 then return end
    local destination = towns[A.rand(#towns) + 1]
    local back = D.planRoute(G, destination, 2 + A.rand(3))
    if back == nil then return end
    local route = {}
    for i = #back, 1, -1 do route[#route + 1] = back[i] end
    local kind = KIND_BY_CLASS[class] or "trade"
    local rules = P().FactionSpawnRules
    local hostile = rules ~= nil and type(rules.hostile) == "function" and rules.hostile(faction) == true or false
    if hostile and kind ~= "convoy" and kind ~= "patrol" then kind = "raid" end
    local speed = A.settings.cruiseKmh
    if class == "military" then speed = speed - 5 elseif class == "raider" then speed = speed + 5 end
    local factionName = tostring(faction.general and faction.general.name or faction.id)
    local caravan = {
        name = factionName, factionId = faction.id, factionName = factionName,
        kind = kind, class = class, hostile = hostile,
        vehicles = vehicles, crew = crew, speedKmh = math.max(10, math.min(70, speed)),
        route = route, leg = 1, t = 0, trips = 0, trip = 0, state = "offline", createdMs = now, lastMs = now,
        vehicleIds = {}, actorUids = {}, abandoned = {}, renderFailures = 0, nextRenderAtMs = 0, truce = {}, goalIndex = 1, units = 0,
        eventType = eventType, eventData = {},
    }
    caravan.leaderName, caravan.callsign = D.leaderFor(catalog, crew, now)
    caravan.destName = D.nodeName(G, route[#route])
    caravan.goals = D.goalsFor(G, caravan)
    caravan.trip = 1
    D.refreshStock(caravan)
    D.armAmbush(caravan)
    local point = D.offlinePosition(G, caravan)
    if point ~= nil then caravan.x, caravan.y = point.x, point.y end
    A.Ledger.create(caravan)
    A.metrics.founded = A.metrics.founded + 1
    A.metrics.events = A.metrics.events + 1
    A.log("EVENT CARAVAN founded", caravan.id, caravan.name, caravan.callsign, "(" .. eventType .. ", " .. kind .. ", " .. #crew .. " crew, " .. #vehicles .. " car(s))")
end

-- NEW FEATURE: Scavenging while travelling
function D.scavengingTick(caravan, now, players)
    if not A.settings.scavengingEnabled or caravan.state ~= "rendered" or caravan.halted then return end
    if now < (caravan.scavengeNextAtMs or 0) then return end
    caravan.scavengeNextAtMs = now + A.settings.scavengingEveryMs or 300000
    if A.rand(100) >= 30 then return end -- 30% chance
    local lootTables = {
        { "Base.CannedCornedBeef", "Base.CannedChili", "Base.TinnedBeans", "Base.Cigarettes" },
        { "Base.Bandage", "Base.Pills", "Base.Disinfectant", "Base.Antibiotics" },
        { "Base.Bullets9mmBox", "Base.ShotgunShellsBox", "Base.556Box" },
        { "Base.PetrolCan", "Base.EmptyPetrolCan", "Base.Battery" },
        { "Base.Axe", "Base.Hammer", "Base.Saw", "Base.Crowbar", "Base.Wrench" },
    }
    local loot = lootTables[A.rand(#lootTables) + 1]
    local item = loot[A.rand(#loot) + 1]
    if not A.Trade.exists(item) then return end
    local count = 1 + A.rand(2)
    local added = false
    for _, row in ipairs(caravan.stock or {}) do
        if row.item == item then
            row.count = math.min(A.Trade.maxCount * 2, row.count + count)
            added = true
            break
        end
    end
    if not added and #(caravan.stock or {}) < A.Trade.maxStock then
        caravan.stock[#caravan.stock + 1] = { item = item, name = A.Trade.name(item), value = A.Trade.valueOf(item), count = count }
        added = true
    end
    if added then
        A.metrics.scavenging = A.metrics.scavenging + 1
        A.log(caravan.id, "scavenged", count, item)
        local shell = D.driverShell(caravan)
        if shell ~= nil then A.Lines.say(shell, "scavenged", { uid = caravan.actorUids[1], vars = { item = A.Trade.name(item) } }) end
        D.publishDirty = true
    end
end

-- NEW FEATURE: Vehicle breakdowns
function D.breakdownTick(caravan, now, players)
    if caravan.state ~= "rendered" or caravan.halted then return end
    if now < (caravan.breakdownCheckAtMs or 0) then return end
    caravan.breakdownCheckAtMs = now + 120000 -- check every 2 minutes
    if A.rand(100) >= (A.settings.breakdownChance or 10) then return end
    if #(caravan.vehicleIds or {}) == 0 then return end
    local vehicleId = caravan.vehicleIds[A.rand(#caravan.vehicleIds) + 1]
    local car = getVehicleById(vehicleId)
    if car == nil or A.vehicleHasPlayer(car) then return end
    -- Damage the engine
    pcall(function()
        local engine = car:getPartById("Engine")
        if engine then engine:setCondition(0) end
    end)
    A.metrics.breakdowns = A.metrics.breakdowns + 1
    A.log(caravan.id, "breakdown on car", vehicleId)
    local shell = D.driverShell(caravan)
    if shell ~= nil then A.Lines.say(shell, "breakdown", { uid = caravan.actorUids[1], cooldownMs = 60000 }) end
    D.halt(caravan, 300, "breakdown")
    D.publishDirty = true
end

-- NEW FEATURE: Refuel at gas stations
function D.refuelTick(caravan, now, players)
    if not A.settings.refuelEnabled or caravan.state ~= "rendered" then return end
    if now < (caravan.refuelCheckAtMs or 0) then return end
    caravan.refuelCheckAtMs = now + 60000
    for _, id in ipairs(caravan.vehicleIds or {}) do
        local car = getVehicleById(id)
        if car ~= nil and not A.vehicleHasPlayer(car) then
            local fuel = 1
            pcall(function()
                local tank = car:getPartById("GasTank")
                if tank then fuel = tank:getContainerContentAmount() end
            end)
            if fuel <= 0.25 then
                -- Find nearby gas station
                local G = D.graph()
                if G == nil then return end
                local cx, cy = A.xyz(car)
                if cx == nil then return end
                -- Simple check: are we near a gas station zone?
                local square = getCell():getGridSquare(math.floor(cx), math.floor(cy), 0)
                if square ~= nil then
                    local zone = square:getZone()
                    if zone and string.find(tostring(zone:getName()), "Gas", 1, true) then
                        pcall(function()
                            local tank = car:getPartById("GasTank")
                            if tank then tank:setContainerContentAmount(tank:getContainerCapacity()) end
                        end)
                        A.metrics.refuels = A.metrics.refuels + 1
                        A.log(caravan.id, "refueled at gas station", vehicleId)
                        local shell = D.driverShell(caravan)
                        if shell ~= nil then A.Lines.say(shell, "refueled", { uid = caravan.actorUids[1], vars = {}, cooldownMs = 60000 }) end
                        D.publishDirty = true
                        return
                    end
                end
            end
        end
    end
end

-- NEW FEATURE: Merge same-faction caravans
function D.mergeTick(now, players)
    if not A.settings.mergeCaravans or now < D.mergeCheckAtMs then return end
    D.mergeCheckAtMs = now + D.mergeEveryMs
    local list = A.Ledger.list()
    for i = 1, #list do
        local a = list[i]
        if a.state == "rendered" and not a.halted and a.factionId ~= nil then
            for j = i + 1, #list do
                local b = list[j]
                if b.state == "rendered" and not b.halted and b.factionId == a.factionId then
                    local _, dist = nearestPlayer({{x=a.x, y=a.y}}, b.x or 0, b.y or 0)
                    if dist <= 80 then -- close enough to merge
                        -- Move b's crew and vehicles into a
                        for _, uid in ipairs(b.actorUids or {}) do a.actorUids[#a.actorUids + 1] = uid end
                        for _, vid in ipairs(b.vehicleIds or {}) do a.vehicleIds[#a.vehicleIds + 1] = vid end
                        -- Combine stock
                        for _, rowB in ipairs(b.stock or {}) do
                            local found = false
                            for _, rowA in ipairs(a.stock or {}) do
                                if rowA.item == rowB.item then
                                    rowA.count = rowA.count + rowB.count
                                    found = true
                                    break
                                end
                            end
                            if not found and #a.stock < A.Trade.maxStock then
                                a.stock[#a.stock + 1] = rowB
                            end
                        end
                        A.metrics.merges = A.metrics.merges + 1
                        A.log("MERGED", b.id, "into", a.id)
                        local shell = D.driverShell(a)
                        if shell ~= nil then A.Lines.say(shell, "merged", { uid = a.actorUids[1] }) end
                        D.release(b, "merged")
                        D.retire(b, "merged")
                        D.publishDirty = true
                        break
                    end
                end
            end
        end
    end
end

-- NEW FEATURE: Weather effects on speed
function D.weatherTick(now, players)
    if not A.settings.weatherEffects or now < D.weatherCheckAtMs then return end
    D.weatherCheckAtMs = now + D.weatherEveryMs
    local climate = getClimateManager and getClimateManager() or nil
    local isRaining = false
    local isSnowing = false
    local isFoggy = false
    if climate ~= nil then
        pcall(function() isRaining = climate:isRaining() end)
        pcall(function() isSnowing = climate:isSnowing() end)
        pcall(function() isFoggy = climate:getFogIntensity() > 0.5 end)
    end
    local multiplier = 1.0
    if isRaining then multiplier = multiplier * 0.8 end
    if isSnowing then multiplier = multiplier * 0.6 end
    if isFoggy then multiplier = multiplier * 0.7 end
    -- Night penalty
    local _, hour = D.clock()
    if hour >= 22 or hour <= 5 then multiplier = multiplier * (A.settings.nightTravelPenalty or 0.7) end
    for _, caravan in ipairs(A.Ledger.list()) do
        if caravan.state == "rendered" and not caravan.halted then
            caravan.weatherMultiplier = multiplier
            local baseSpeed = tonumber(caravan.baseSpeedKmh) or caravan.speedKmh
            caravan.speedKmh = math.max(10, math.floor(baseSpeed * multiplier))
        end
    end
end

-- NEW FEATURE: Distress calls
function D.distressTick(now, players)
    if not A.settings.distressCalls or now < D.distressCheckAtMs then return end
    D.distressCheckAtMs = now + D.distressEveryMs
    for _, caravan in ipairs(A.Ledger.list()) do
        if caravan.state == "rendered" then
            if caravan.ambush and caravan.ambush.state == "fighting" then
                if not caravan.distressSent then
                    caravan.distressSent = true
                    local radio = P() and P().KnoxCountyRadio
                    if radio and radio.channel then
                        local text = "MAYDAY MAYDAY: " .. (caravan.callsign or caravan.name) .. " under attack at " .. math.floor(caravan.x) .. "," .. math.floor(caravan.y) .. ". Request immediate assistance."
                        pcall(function()
                            local broadcast = RadioBroadCast.new("alc-distress-" .. tostring(now), -1, -1)
                            broadcast:AddRadioLine(RadioLine.new(text, 0.9, 0.3, 0.3))
                            radio.channel:setAiringBroadcast(broadcast)
                        end)
                        A.log(caravan.id, "DISTRESS CALL sent")
                    end
                    -- Mark on map for players
                    caravan.distress = { x = caravan.x, y = caravan.y, sinceMs = now }
                end
            else
                caravan.distressSent = nil
                if caravan.distress and now - caravan.distress.sinceMs > 600000 then caravan.distress = nil end
            end
        end
    end
end

-- NEW FEATURE: Living world interactions
function D.livingWorldTick(now, players)
    if not A.settings.livingWorld or now < D.livingWorldCheckAtMs then return end
    D.livingWorldCheckAtMs = now + D.livingWorldEveryMs
    for _, caravan in ipairs(A.Ledger.list()) do
        local cx, cy = caravan.x, caravan.y
        if caravan.state == "rendered" and cx ~= nil then
            -- Check for zombie hordes nearby
            local hordeCount = 0
            pcall(function()
                local list = getCell():getZombieList()
                for index = 0, list:size() - 1 do
                    local zombie = list:get(index)
                    local zx, zy = A.xyz(zombie)
                    if zx and not zombie:isDead() and A.dist(zx, zy, cx, cy) <= 50 then
                        local data = zombie:getModData()
                        if not (data and data.ProjectALifeOwned == true) then hordeCount = hordeCount + 1 end
                    end
                end
            end)
            if hordeCount >= 20 and A.rand(100) < 40 then
                -- Large horde blocks the road
                D.halt(caravan, 180, "horde_block")
                local shell = D.driverShell(caravan)
                if shell ~= nil then A.Lines.say(shell, "horde_block", { uid = caravan.actorUids[1] }) end
                A.log(caravan.id, "HORDE BLOCK", hordeCount, "zombies")
                D.publishDirty = true
            end
            -- Check for player bases nearby (safehouses)
            local safehouse = nil
            pcall(function()
                local SafeHouse = SafeHouse and SafeHouse.getSafeHouse
                if SafeHouse then safehouse = SafeHouse(cx, cy, 0) end
            end)
            if safehouse ~= nil then
                local owner = safehouse:getOwner()
                if owner and owner ~= "" then
                    local key = tostring(owner)
                    -- Friendly faction gets a discount, hostile pays toll
                    local relations = P() and P().Relations
                    local stance = "neutral"
                    if relations and type(relations.playerStance) == "function" then
                        local actor = D.driverShell(caravan)
                        if actor then
                            local p = A.players()[1]
                            if p then pcall(function() stance = relations.playerStance(actor, p) end) end
                        end
                    end
                    if stance == "friendly" and caravan.halted == false and A.rand(100) < 20 then
                        D.halt(caravan, 120, "safehouse_visit")
                        A.log(caravan.id, "visiting safehouse of", owner)
                        D.publishDirty = true
                    end
                end
            end
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
    if not A.settings.enabled then
        for _, caravan in ipairs(A.Ledger.list()) do A.SOS.tick(caravan, now, D.playerRows()) end
        return
    end
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
        local okSOS, errSOS = pcall(A.SOS.tick, caravan, now, players)
        if not okSOS then A.fail("SOS " .. tostring(caravan.id), errSOS) end
        -- NEW FEATURE TICKS
        if caravan.state == "rendered" then
            pcall(D.scavengingTick, caravan, now, players)
            pcall(D.breakdownTick, caravan, now, players)
            pcall(D.refuelTick, caravan, now, players)
        end
    end
    pcall(D.eventCaravanTick, now, players)
    pcall(D.mergeTick, now, players)
    pcall(D.weatherTick, now, players)
    pcall(D.distressTick, now, players)
    pcall(D.livingWorldTick, now, players)
    local okRadio, errRadio = pcall(D.radioTick, now, players)
    if not okRadio then A.fail("radio", errRadio) end
    D.publish(false)
end

function D.describe()
    local lines = {}
    local G = D.graph()
    for _, caravan in ipairs(A.Ledger.list()) do
        lines[#lines + 1] = string.format("%s %s %s [%s] %s at %d,%d leg %d/%d -> %s cars=%d crew=%d trip=%d%s%s",
            tostring(caravan.id), tostring(caravan.name), tostring(caravan.callsign), tostring(caravan.kind), tostring(caravan.state),
            math.floor(caravan.x or 0), math.floor(caravan.y or 0), caravan.leg or 1, math.max(1, #(caravan.route or {}) - 1),
            tostring(caravan.destName), #(caravan.vehicleIds or {}), #(caravan.actorUids or {}), caravan.trip or 0,
            caravan.halted and " HALTED" or "", caravan.escort and (" escort=" .. tostring(caravan.escort.playerKey)) or "")
    end
    if #lines == 0 then lines[1] = "no caravans" .. (G == nil and " (no road graph)" or "") end
    return lines
end

return D
