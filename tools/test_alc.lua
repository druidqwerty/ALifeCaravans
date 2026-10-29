-- Simulation test for A-Life: Caravans (run by run_test.py through lupa).
-- Stubs the Project A-Life tables and the game objects the mod touches, loads
-- the mod in single-player mode and drives a caravan through its whole life.

local ROOT = MOD_ROOT .. "/42/media/lua/"
local loaded = {}
function require(name)
    if loaded[name] ~= nil then return loaded[name] end
    local chunk = loadfile(ROOT .. "shared/" .. name .. ".lua") or loadfile(ROOT .. "server/" .. name .. ".lua")
        or loadfile(ROOT .. "client/" .. name .. ".lua")
    assert(chunk, "require failed: " .. name)
    local result = chunk()
    loaded[name] = result == nil and true or result
    return loaded[name]
end

local failed, passed = 0, 0
local function check(name, condition, detail)
    if condition then passed = passed + 1 else
        failed = failed + 1
        print("FAIL " .. name .. (detail ~= nil and (" :: " .. tostring(detail)) or ""))
    end
end

-- ---------------------------------------------------------------- PZ globals
CLOCK = 1000000
function getTimestampMs() return CLOCK end
local seed = 12345
function ZombRand(a, b)
    seed = (seed * 1103515245 + 12345) % 2147483648
    local high = math.floor(seed / 65536)
    if b ~= nil then return a + high % (b - a) end
    return high % a
end
function ZombRandFloat(a, b) return a + (ZombRand(1000000) / 1000000) * (b - a) end
function isServer() return false end
function isClient() return false end
function instanceof(object, class) return type(object) == "table" and object.__class == class end
function getText(key) local v = TRANSLATIONS[key] if v == nil then return key end return v end
function getItemNameFromFullType(fullType) return (string.gsub(fullType, "^Base%.", "")) end
function getGameTime() return { getNightsSurvived = function() return 2 end, getTimeOfDay = function() return 12 end } end
Events = setmetatable({}, { __index = function(t, name)
    local event = { handlers = {} }
    function event.Add(fn) event.handlers[#event.handlers + 1] = fn end
    function event.Remove(fn)
        for index = #event.handlers, 1, -1 do if event.handlers[index] == fn then table.remove(event.handlers, index) end end
    end
    function event.fire(...)
        local copy = {}
        for index, fn in ipairs(event.handlers) do copy[index] = fn end
        for _, fn in ipairs(copy) do fn(...) end
    end
    rawset(t, name, event)
    return event
end })
SERVER_SENT, CLIENT_SENT = {}, {}
function sendServerCommand(...) SERVER_SENT[#SERVER_SENT + 1] = { ... } end
function sendClientCommand(...) CLIENT_SENT[#CLIENT_SENT + 1] = { ... } end
NOTICES = {}
HaloTextHelper = { addText = function(player, text) NOTICES[#NOTICES + 1] = text end, getColorGreen = function() return 1 end }

-- the player and the inventory
ITEMS = {}
local INV = {}
function INV:getCountTypeRecurse(t) local n = 0 for _, item in ipairs(ITEMS) do if item.type == t then n = n + 1 end end return n end
function INV:getFirstTypeRecurse(t) for _, item in ipairs(ITEMS) do if item.type == t then return item end end return nil end
function INV:Remove(item) for i, it in ipairs(ITEMS) do if it == item then table.remove(ITEMS, i) return end end end
function INV:AddItem(t) ITEMS[#ITEMS + 1] = { type = t, getContainer = function() return INV end } end
for _ = 1, 100 do INV:AddItem("Base.Money") end
PLAYER = { __class = "IsoPlayer", x = 20, y = 100 }
function PLAYER:getX() return self.x end
function PLAYER:getY() return self.y end
function PLAYER:getZ() return 0 end
function PLAYER:getUsername() return "ivan" end
function PLAYER:isDead() return false end
function PLAYER:getPlayerNum() return 0 end
function PLAYER:getInventory() return INV end
function PLAYER:Say() end
function getSpecificPlayer(n) if n == 0 then return PLAYER end return nil end
function getPlayer() return PLAYER end

-- the world: a road along y=100 (x 0..400) and a road along x=200 (y 0..100)
local function isRoad(x, y)
    x, y = math.floor(x), math.floor(y)
    if y >= 98 and y <= 101 and x >= 0 and x <= 400 then return true end
    if x >= 199 and x <= 202 and y >= 0 and y <= 100 then return true end
    return false
end
VEHICLES, NEXT_VEHICLE = {}, 100
function newVehicle(script, x, y)
    NEXT_VEHICLE = NEXT_VEHICLE + 1
    local v = { __class = "BaseVehicle", id = NEXT_VEHICLE, script = script, x = x, y = y, modData = {}, lights = false, seats = 4 }
    function v:getId() return self.id end
    function v:getX() return self.x end
    function v:getY() return self.y end
    function v:getZ() return 0 end
    function v:getModData() return self.modData end
    function v:setHeadlightsOn(on) self.lights = on end
    function v:getHeadlightsOn() return self.lights end
    function v:getDriver() return nil end
    function v:isEngineRunning() return true end
    function v:shutOff() end
    function v:getMaxPassengers() return self.seats end
    function v:getCharacter() return self.occupied and PLAYER or nil end
    function v:isSeatInstalled() return true end
    VEHICLES[v.id] = v
    return v
end
function getVehicleById(id) local v = VEHICLES[id] if v ~= nil and not v.removed then return v end return nil end
function getCell()
    return {
        getGridSquare = function(_, x, y, z)
            if x < 0 or x > 420 or y < 0 or y > 120 then return nil end
            return { isOutside = function() return true end, road = isRoad(x, y) }
        end,
        getVehicles = function()
            local list = {}
            for _, v in pairs(VEHICLES) do if not v.removed then list[#list + 1] = v end end
            return { size = function() return #list end, get = function(_, i) return list[i + 1] end }
        end,
    }
end
local SCRIPTS = {
    { name = "Base.CarNormal", seats = 4, wheels = 4, mass = 1000 },
    { name = "Base.StepVan", seats = 2, wheels = 4, mass = 1500 },
    { name = "Base.M998", seats = 4, wheels = 4, mass = 1800 },
    { name = "Base.PickUpTruck", seats = 2, wheels = 4, mass = 1300 },
    { name = "Base.CarNormalBurnt", seats = 4, wheels = 4, mass = 1000 },
    { name = "Base.Trailer", seats = 0, wheels = 2, mass = 300 },
    { name = "Base.CarLightsPolice", seats = 4, wheels = 4, mass = 1100 },
}
local function scriptObject(row)
    return { getFullName = function() return row.name end, getName = function() return row.name end,
        getPassengerCount = function() return row.seats end, getWheelCount = function() return row.wheels end,
        getMass = function() return row.mass end }
end
MISSING_ITEMS = { ["Base.MRE"] = true }
function getScriptManager()
    return {
        getAllVehicleScripts = function()
            return { size = function() return #SCRIPTS end, get = function(_, i) return scriptObject(SCRIPTS[i + 1]) end }
        end,
        getVehicle = function(_, name) for _, row in ipairs(SCRIPTS) do if row.name == name then return scriptObject(row) end end return nil end,
        getItem = function(_, name) if MISSING_ITEMS[name] then return nil end return { name = name } end,
    }
end
VehicleZoneDistribution = {
    military = { vehicles = { ["Base.M998"] = { spawnChance = 10 }, ["Mod.Ghost"] = { spawnChance = 50 } } },
    delivery = { vehicles = { ["Base.StepVan"] = { spawnChance = 10 } } },
    police = { vehicles = { ["Base.CarLightsPolice"] = { spawnChance = 10 } } },
    parkingstall = { vehicles = { ["Base.CarNormal"] = { spawnChance = 20 } } },
}
-- context menu stub
POPUPS = {}
local function newContext()
    local ctx = { options = {}, subs = {} }
    function ctx:addOption(name, target, fn, ...)
        local opt = { name = name, target = target, fn = fn, args = { ... } }
        self.options[#self.options + 1] = opt
        return opt
    end
    function ctx:getNew() return newContext() end
    function ctx:addSubMenu(opt, sub) self.subs[opt] = sub end
    return ctx
end
ISContextMenu = { get = function() local c = newContext() POPUPS[#POPUPS + 1] = c return c end }

-- ------------------------------------------------------------ Project A-Life
local function copyPoints(points)
    local out = {}
    for _, p in ipairs(points or {}) do out[#out + 1] = { x = p.x, y = p.y, kind = p.kind } end
    return out
end
local function makeALife()
    local P = {}
    P.Runtime = { started = true }
    BUCKETS, TOUCHES = {}, 0
    P.Persistence = { bucket = function(name, defaults) BUCKETS[name] = BUCKETS[name] or defaults return BUCKETS[name] end,
        touch = function() TOUCHES = TOUCHES + 1 end }
    P.RoadGraph = {
        nodes = { townA = { x = 20, y = 100, kind = "town", name = "Alpha" }, townB = { x = 380, y = 100, kind = "town", name = "Bravo" },
            townC = { x = 200, y = 10, kind = "town", name = "Charlie" } },
        adjacency = { townA = { townB = 360, townC = 201 }, townB = { townA = 360, townC = 201 }, townC = { townA = 201, townB = 201 } },
        displayName = function(id, node) return node.name end,
        importShipped = function() end,
    }
    function P.RoadGraph.interpolate(a, b, t)
        local na, nb = P.RoadGraph.nodes[a], P.RoadGraph.nodes[b]
        return { x = na.x + (nb.x - na.x) * t, y = na.y + (nb.y - na.y) * t, z = 0 }
    end
    local factions = {
        { id = "f_trade", general = { name = "Knox Traders" }, spawn = { enabled = true, program = "patrol" }, relations = { player = "neutral", bloc = "work" }, support = { vehicle = "workvan" } },
        { id = "f_army", general = { name = "Guard Infantry" }, spawn = { enabled = true, program = "patrol" }, relations = { player = "careful", bloc = "military" }, support = {} },
        { id = "f_raid", general = { name = "Road Wolves" }, spawn = { enabled = true, program = "looter" }, relations = { player = "hostile", bloc = "crime" }, support = {} },
    }
    local byId = {}
    for _, f in ipairs(factions) do byId[f.id] = f end
    local profiles = {}
    for _, f in ipairs(factions) do
        for i = 1, 3 do profiles[#profiles + 1] = { id = f.id .. "_p" .. i, general = { faction = f.id, spawnWeight = 1, name = "P" .. i } } end
    end
    P.Catalog = { current = { factions = byId, factionOrder = factions, npcOrder = profiles },
        faction = function(id) return byId[id] end,
        weightedProfile = function(roster, fraction) return roster[1 + math.floor(math.min(0.999, fraction) * #roster)] end }
    P.FactionSpawnRules = {
        pickList = function(catalog, enc, hostileOnly, day, hour, req, filter)
            local rows = {}
            for _, f in ipairs(catalog.factionOrder) do if filter == nil or filter(f) then rows[#rows + 1] = { faction = f, weight = 1 } end end
            return rows
        end,
        hostile = function(f) return f.relations.player == "hostile" end,
        blocOf = function(f) return f.relations.bloc end,
        clock = function() return 3, 12 end,
    }
    ACTORS, SHELLS, REMOVED_ACTORS, DEHYDRATED = {}, {}, 0, 0
    P.ActorRegistry = {
        read = function(uid) return ACTORS[uid] end,
        remove = function(uid, rev, reason) ACTORS[uid] = nil REMOVED_ACTORS = REMOVED_ACTORS + 1 return true end,
        updateTransient = function(uid, rev, fn) fn(ACTORS[uid]) return true end,
    }
    P.SpawnService = { dehydrate = function(uid, reason) if ACTORS[uid] then ACTORS[uid].lifecycle = "dormant" DEHYDRATED = DEHYDRATED + 1 return true end return false end }
    TOLERATED = {}
    P.Talk = { shellFor = function(uid) return SHELLS[uid] end, tolerate = function(record, key, untilMs) TOLERATED[key] = untilMs end }
    SAID = {}
    P.Speech = { say = function(shell, text, opts) SAID[#SAID + 1] = { shell = shell, text = text, face = opts and opts.face } return true end,
        display = function() return true end, playerKey = function(player) return player:getUsername() end,
        nearestTown = function() return "Muldraugh" end, variable = function(shell, name) return shell.vars and shell.vars[name] end,
        colorFor = function() return { 1, 1, 1 } end, findShell = function(uid) return SHELLS[uid] end }
    STANCE = {}
    P.Relations = { playerStance = function(actor, player) return STANCE[actor.factionId] or "neutral" end }
    PROVOKED, DAMAGED = {}, 0
    P.Reputation = { onPlayerDamagedActor = function() DAMAGED = DAMAGED + 1 end, onPlayerKilledActor = function() DAMAGED = DAMAGED + 1 end,
        onPlayerProvoked = function(player, factionId) PROVOKED[#PROVOKED + 1] = factionId end }
    RELEASED = {}
    P.DrivingDemo = { maxSpeedKmh = 75, release = function(s) RELEASED[#RELEASED + 1] = s end }
    P.DrivingTuning = { copy = function(values) return { speedKmh = values and values.speedKmh or 75, acceleration = 6 } end,
        apply = function(s, values) s.tuning = values end, value = function(s, key) return s.tuning[key] end }
    P.DrivingRoute = { maxPoints = 20, copy = copyPoints }
    function P.DrivingRoute.append(s, points)
        if not s.route or s.phase ~= "driving" or s.braking or s.exitAt then return nil, "not driving" end
        if #s.route + #points > 20 then return nil, "max 20" end
        local x, y = s.vehicle:getX(), s.vehicle:getY()
        local tail = s.route[#s.route]
        if tail then x, y = tail.x, tail.y end
        local extra = 0
        for _, p in ipairs(points) do
            local d = math.sqrt((p.x - x) ^ 2 + (p.y - y) ^ 2)
            if d < 1 then return nil, "too close" end
            extra = extra + d x, y = p.x, p.y
        end
        return copyPoints(points), extra
    end
    function P.DrivingRoute.extend(s, points, extra) for _, p in ipairs(points) do s.route[#s.route + 1] = p end s.routeLength = (s.routeLength or 0) + extra end
    P.DrivingFleet = { focus = function(owner, session, fn, ...)
        owner.active = session
        local ok, result = pcall(fn, ...)
        owner.active = nil
        return ok, result
    end }
    FORGOTTEN = 0
    P.DrivingLifecycle = { forget = function() FORGOTTEN = FORGOTTEN + 1 end }
    function P.DrivingLifecycle.create(owner, old, car, crew, token, route, boarding)
        local s = { manual = true, vehicle = car, route = copyPoints(route or old.route), phase = "driving", npc = SHELLS[crew[1].uid],
            uid = crew[1].uid, tuning = P.DrivingTuning.copy(old.tuning), speedKmh = old.speedKmh, cruiseSpeed = old.cruiseSpeed,
            player = old.player, token = token, trip = 0 }
        owner.sessions[car:getId()] = s
        return s
    end
    STOPPED, STARTED, WALKED = {}, {}, {}
    local Client = { sessions = {}, bindings = {}, sleeping = {}, departures = {}, pending = {}, tunings = {}, allowRiders = {}, carModes = {}, active = nil }
    function Client.stop() local s = Client.active s.braking = true s.stopReason = "stop" STOPPED[#STOPPED + 1] = s end
    function Client.appendRoute(points)
        local s = Client.active
        local additions, extra = P.DrivingRoute.append(s, points)
        if not additions then return end
        P.DrivingRoute.extend(s, additions, extra)
    end
    function Client.startDrive(id, route, speed)
        local s = Client.sessions[id]
        STARTED[#STARTED + 1] = { id = id, route = route, speed = speed }
        s.route = copyPoints(route) s.phase = "driving" s.braking = nil
    end
    function Client.arrivalWalk(s) WALKED[#WALKED + 1] = s s.exitRequested = true end
    function Client.message() end
    function Client.finish() end
    P.DrivingDemoClient = Client
    P.DrivingMultiplayer = { enabled = function() return true end, broadcastAt = 0 }
    FALLBACKS, FINISHED = 0, {}
    P.VehicleArrivals = { active = {}, journeys = {}, plans = {}, enabled = function() return true end,
        owner = function() return Client end, fallback = function() FALLBACKS = FALLBACKS + 1 end,
        finished = function(owner, s) FINISHED[#FINISHED + 1] = s end }
    P.VehicleArrivalSites = {
        context = function(player) return { players = { { x = player:getX(), y = player:getY() } }, bodies = {}, reserved = {} } end,
        road = function(scene, x, y) return isRoad(x, y) end,
        space = function(scene, x, y, spawn)
            for _, v in pairs(VEHICLES) do if not v.removed and (v.x - x) ^ 2 + (v.y - y) ^ 2 < 25 then return false end end
            return true
        end,
        link = function(scene, a, b)
            for i = 1, 4 do if not isRoad(a.x + (b.x - a.x) * i / 4, a.y + (b.y - a.y) * i / 4) then return false end end
            return true
        end,
        find = function(scene, target) return { x = target.x, y = target.y, z = 0, route = { { x = target.x + 10, y = target.y, kind = "dismount" } } } end,
    }
    CREATED, REMOVED_CARS = {}, 0
    P.VehicleArrivalVehicle = { script = "Base.CarNormal", night = function() return false end,
        create = function(site, requestId) local car = newVehicle(P.VehicleArrivalVehicle.script, site.x, site.y) CREATED[#CREATED + 1] = car return car, { 0, 1, 2, 3 } end,
        remove = function(car) if car.occupied then return false end car.removed = true REMOVED_CARS = REMOVED_CARS + 1 return true end }
    SPAWN_CALLS, WATCHERS, LAST_PLAN = {}, {}, nil
    P.DebugService = {
        rawSpawn = function(player, args, allow)
            SPAWN_CALLS[#SPAWN_CALLS + 1] = args
            local scene = P.VehicleArrivalSites.context(player)
            local assigned, cars = 0, {}
            while assigned < args.count do
                if #cars >= 2 then return { ok = false, reason = "too many cars" } end
                local site, why = P.VehicleArrivalSites.find(scene, { x = args.objectiveX, y = args.objectiveY })
                if not site then return { ok = false, reason = why } end
                local car, seats = P.VehicleArrivalVehicle.create(site, args.requestId)
                if not car then return { ok = false, reason = seats } end
                cars[#cars + 1] = { car = car, site = site, seats = seats }
                assigned = assigned + #seats
            end
            LAST_PLAN = { cars = cars, args = args }
            return { ok = true, requestId = args.requestId }
        end,
        watchGroup = function(requestId, listener) WATCHERS[requestId] = listener return true end,
    }
    return P
end

NEXT_UID = 0
function completeSpawn(requestId)
    local uids = {}
    local plan = LAST_PLAN
    for _, entry in ipairs(plan.cars) do
        local crew = {}
        for seat = 1, math.min(#entry.seats, plan.args.count - #uids) do
            NEXT_UID = NEXT_UID + 1
            local uid = "uid" .. NEXT_UID
            ACTORS[uid] = { uid = uid, revision = 1, lifecycle = "active", memory = {}, factionId = plan.args.factionId, generation = 1 }
            SHELLS[uid] = { vars = { ALifeUID = uid, ALifeFactionId = plan.args.factionId }, uid = uid }
            uids[#uids + 1] = uid
            crew[#crew + 1] = { uid = uid, generation = 1, seat = seat - 1 }
        end
        local old = { player = PLAYER, systemArrival = true, tuning = ProjectALife.DrivingTuning.copy(), speedKmh = 75, cruiseSpeed = 75 / 3.6,
            route = entry.site.route, boardingDepart = true }
        ProjectALife.DrivingLifecycle.create(ProjectALife.DrivingDemoClient, old, entry.car, crew, "token" .. entry.car:getId(), entry.site.route)
    end
    WATCHERS[requestId]({ ok = true, actorUids = uids })
    return uids
end

-- -------------------------------------------------------------- load the mod
require "ALifeCaravans/00_ALC_Core"
require "ALifeCaravans/ALC_Boot"
require "ALifeCaravans/ALC_Client"
local A = ALifeCaravans
local Lines, Vehicles, Roads, Convoy, Ledger, Director, Spawn, Interact, Client =
    A.Lines, A.Vehicles, A.Roads, A.Convoy, A.Ledger, A.Director, A.Spawn, A.Interact, A.Client

-- 1. boot waits for A-Life, then installs the hooks
Events.OnGameStart.fire()
check("not installed without A-Life", not A.Boot.installed)
ProjectALife = makeALife()
check("default cruise 35", A.settings.cruiseKmh == 35)
SandboxVars = { ALifeCaravans = { CruiseKmh = 30, MaxCaravans = 1, FoundIntervalMinutes = 1, RenderRadius = 120, ReleaseRadius = 50,
    MinSpawnDistance = 25, CrewMin = 5, CrewMax = 5, MaxVehicles = 2, OfflineSpeedPercent = 100, HaltSeconds = 60, Debug = true } }
Events.OnTick.fire()
check("installed on tick", A.Boot.installed)
for _, label in ipairs({ "VehicleArrivalSites.find", "VehicleArrivalVehicle.create", "DrivingLifecycle.create",
    "VehicleArrivals.fallback", "VehicleArrivals.finished", "Reputation.onPlayerDamagedActor", "Reputation.onPlayerKilledActor" }) do
    check("wrapped " .. label, A.wrapped[label] ~= nil)
end
check("ledger uses A-Life bucket", BUCKETS.alc_caravans ~= nil and not Ledger.fallback)

-- 2. settings (applied at install from SandboxVars)
A.refreshSettings()
check("sandbox cruise", A.settings.cruiseKmh == 30)
check("sandbox max caravans", A.settings.maxCaravans == 1)
check("release radius kept above render", A.settings.releaseRadius == 150)
check("crew clamp", A.settings.crewMin == 5 and A.settings.crewMax == 5)
check("missing option keeps default", A.settings.tripsPerCaravan == 2)

-- 3. vehicles
local scan = Vehicles.scan(true)
check("scan drops wrecks and trailers", scan.byName["Base.CarNormalBurnt"] == nil and scan.byName["Base.Trailer"] == nil)
check("scan keeps drivable", scan.byName["Base.M998"] ~= nil and scan.byName["Base.StepVan"] ~= nil)
check("zone pick skips missing script", Vehicles.pick("military", 0.99) == "Base.M998")
check("class from bloc military", Vehicles.classFor(ProjectALife.Catalog.faction("f_army")) == "military")
check("class from bloc crime", Vehicles.classFor(ProjectALife.Catalog.faction("f_raid")) == "raider")
check("class from support hint", Vehicles.classFor(ProjectALife.Catalog.faction("f_trade")) == "trade")
check("police class from zone", Vehicles.pick("police", 0.5) == "Base.CarLightsPolice")
local convoy, seats = Vehicles.convoy("trade", 5, 2)
check("convoy two cars for five crew", #convoy == 2 and seats >= 4, #convoy .. "/" .. seats)
check("pattern fallback when zone empty", Vehicles.pick("raider", 0.5) ~= nil)

-- 4. roads
local scene = Roads.scene(PLAYER)
local points, info = Roads.scout(scene, { x = 10, y = 100 }, { x = 200, y = 20 }, { maxPoints = 30 })
check("scout reaches the goal", info.reached == true, info.distance)
check("scout returns waypoints", #points >= 2 and #points <= 30, #points)
local short = Roads.scout(scene, { x = 10, y = 100 }, { x = 200, y = 20 }, { maxPoints = 5 })
check("scout truncates to maxPoints", #short == 5, #short)
local bend = false
for _, p in ipairs(points) do if math.abs(p.x - 200.5) < 3 and p.y > 90 then bend = true end end
check("scout keeps the bend", bend)
local last = points[#points]
check("scout ends near the goal", last.y < 30 and math.abs(last.x - 200.5) < 3, last.x .. "," .. last.y)
local none, info2 = Roads.scout(scene, { x = 50, y = 50 }, { x = 200, y = 20 }, {})
check("scout off road fails softly", #none == 0 and info2.reason ~= nil)
local site = Roads.siteNear(scene, 80, 100, { { x = 20, y = 100 } }, { radius = 30, minPlayer = 45 })
check("site near is a road tile away from the player", site ~= nil and isRoad(site.x, site.y) and site.x - 20 >= 45, site and site.x)
local behind = Roads.behind(scene, { x = 120.5, y = 100.5 }, { x = 150.5, y = 100.5 }, 9, { { x = 20, y = 100 } }, 25)
check("second car site behind the first", behind ~= nil and behind.x < 120 and behind.x >= 108, behind and behind.x)

-- 5. founding (player at Alpha; destination 150..900 away, start >= release+60 away)
CLOCK = CLOCK + 5000
Director.tick()
check("one caravan founded", Ledger.count() == 1, Ledger.count())
local caravan = Ledger.list()[1]
check("caravan has a route", caravan ~= nil and #caravan.route >= 2)
check("crew size from sandbox", #caravan.crew == 5, #caravan.crew)
check("vehicles chosen", #caravan.vehicles >= 1)
check("goals ahead", #caravan.goals >= 1)
check("start far from player", math.sqrt((caravan.x - 20) ^ 2 + (caravan.y - 100) ^ 2) >= 200, caravan.x .. "," .. caravan.y)
check("offers generated", caravan.offers ~= nil and #caravan.offers >= 1)
check("max caravans respected", (function() CLOCK = CLOCK + 120000 Director.tick() return Ledger.count() end)() == 1)

-- 6. offline travel
local before = { x = caravan.x, y = caravan.y, leg = caravan.leg, t = caravan.t }
local result = Director.advance(ProjectALife.RoadGraph, caravan, 10)
check("advance moves the caravan", result == "moving" and (caravan.t > before.t or caravan.leg > before.leg))

-- 7. rendering: put the caravan on the road near the player
caravan.factionId, caravan.factionName, caravan.class, caravan.kind, caravan.hostile = "f_trade", "Knox Traders", "trade", "trade", false
caravan.route, caravan.leg, caravan.t = { "townA", "townB", "townC" }, 1, 100 / 360
caravan.x, caravan.y = 120, 100
caravan.goals = { { x = 200, y = 100 }, { x = 200, y = 20 }, { x = 200, y = 10 } }
caravan.goalIndex = 1
caravan.vehicles = { "Base.CarNormal", "Base.StepVan" }
caravan.speedKmh = 30
CLOCK = CLOCK + 20000
Director.renderCooldownUntilMs = 0
check("render accepted", Director.tryRender(caravan, Director.playerRows(), CLOCK) == true, caravan.state)
check("state rendering", caravan.state == "rendering")
local args = SPAWN_CALLS[#SPAWN_CALLS]
check("arrival by car requested", args ~= nil and args.arrival == "ground" and args.count == 5 and #args.profileIds == 5)
check("two cars created", #CREATED == 2, #CREATED)
check("cars tagged", A.vehicleTag(CREATED[1]) == caravan.id and A.vehicleTag(CREATED[2]) == caravan.id)
check("vehicle scripts applied", CREATED[1].script == "Base.CarNormal" and CREATED[2].script == "Base.StepVan", CREATED[1].script .. "/" .. CREATED[2].script)
check("lead car away from the player", CREATED[1].x - 20 >= 25)
check("script restored", ProjectALife.VehicleArrivalVehicle.script == "Base.CarNormal")
local uids = completeSpawn(caravan.requestId)
check("state rendered", caravan.state == "rendered")
check("crew recorded", #caravan.actorUids == 5)
local lead = ProjectALife.DrivingDemoClient.sessions[CREATED[1]:getId()]
check("session speed injected", lead ~= nil and lead.speedKmh == 30 and lead.tuning.speedKmh == 30, lead and lead.speedKmh)
Director.publish(true)
check("known cars published", Convoy.known[CREATED[1]:getId()] ~= nil and Convoy.known[CREATED[2]:getId()] ~= nil)
check("known entry carries goals and speed", Convoy.known[CREATED[1]:getId()].goals[1].x == 200 and Convoy.known[CREATED[1]:getId()].speedKmh == 30)

-- 8. route extension on the driving side
lead.route = { { x = 180.5, y = 100.5 } }
Convoy.nextTickMs = 0
CLOCK = CLOCK + 1000
Convoy.tick()
check("route extended when low", #lead.route > 1, #lead.route)
check("extension heads up the north road", lead.route[#lead.route].y < 90, lead.route[#lead.route].y)
check("legs counted", A.metrics.legs >= 1)
-- stuck behind something: the driver complains once
lead.obstacleSince = CLOCK - 7000
Convoy.nextTickMs = 0
local saidBefore = #SAID
Convoy.tick()
check("blocked line said", #SAID == saidBefore + 1 and SAID[#SAID].text ~= "")
lead.obstacleSince = nil

-- 9. hail -> halt -> stop; talk; trade; ride; wait; farewell -> restart
PLAYER.x, PLAYER.y = caravan.x - 6, caravan.y
check("hail command halts", (function() Interact.command(PLAYER, "hail", { vehicleId = CREATED[1]:getId() }) return caravan.halted == true end)())
check("driver answered the hail", SAID[#SAID].face == nil and SAID[#SAID].text ~= "")
Convoy.nextTickMs = 0
Convoy.tick()
check("halted convoy stops the car", #STOPPED >= 1 and lead.braking == true)
lead.phase = "seated" lead.braking = nil
check("hail while halted answers busy", (function() local n = #SAID Interact.command(PLAYER, "hail", { vehicleId = CREATED[1]:getId() }) return #SAID == n + 1 end)())
check("news answered", (function() local n = #SAID Interact.command(PLAYER, "news", { vehicleId = CREATED[1]:getId() }) return #SAID == n + 1 and not string.find(SAID[#SAID].text, "{", 1, true) end)(), SAID[#SAID].text)
Interact.command(PLAYER, "offers", { vehicleId = CREATED[1]:getId() })
check("offers shown in a popup", #POPUPS >= 1 and #POPUPS[#POPUPS].options >= 2, #POPUPS)
local offerIndex = POPUPS[#POPUPS].options[2].args[1]
local offer = caravan.offers[offerIndex]
local stockBefore, moneyBefore = offer.stock, INV:getCountTypeRecurse("Base.Money")
Interact.command(PLAYER, "buy", { vehicleId = CREATED[1]:getId(), index = offerIndex })
check("trade took the money", INV:getCountTypeRecurse("Base.Money") == moneyBefore - offer.price, INV:getCountTypeRecurse("Base.Money"))
check("trade gave the item", INV:getCountTypeRecurse(offer.item) >= 1)
check("stock reduced", offer.stock == stockBefore - 1)
check("trade notice shown", #NOTICES >= 1)
Interact.command(PLAYER, "ride", { vehicleId = CREATED[1]:getId() })
check("ride allowed on the car", ProjectALife.DrivingDemoClient.allowRiders[CREATED[1]:getId()] == true and caravan.riders == true)
local haltBefore = caravan.haltUntilMs
CLOCK = CLOCK + 10000
Interact.command(PLAYER, "wait", { vehicleId = CREATED[1]:getId() })
check("wait extends the halt", caravan.haltUntilMs > haltBefore)
Interact.command(PLAYER, "farewell", { vehicleId = CREATED[1]:getId() })
check("farewell resumes", caravan.halted == nil and ProjectALife.DrivingDemoClient.allowRiders[CREATED[1]:getId()] == false)
Director.publish(true)
lead.route = {}
Convoy.nextTickMs = 0
CLOCK = CLOCK + 100
Convoy.tick()
CLOCK = CLOCK + 4000
Convoy.nextTickMs = 0
Convoy.tick()
check("parked car restarts toward the next goal", #STARTED >= 1 and STARTED[#STARTED].speed == 30, #STARTED)

-- 10. threaten a trade caravan: it folds and flees
local moneyNow = INV:getCountTypeRecurse("Base.Money")
local itemsBefore = #ITEMS
Interact.command(PLAYER, "threaten", { vehicleId = CREATED[1]:getId() })
check("traders hand something over", #ITEMS == itemsBefore + 1 and INV:getCountTypeRecurse("Base.Money") == moneyNow)
check("traders flee faster", caravan.speedKmh == 45 and lead.tuning.speedKmh == 45, caravan.speedKmh)
check("threat provokes the faction", PROVOKED[#PROVOKED] == "f_trade")

-- 11. arrival at the last goal, then the next trip
Convoy.known[CREATED[1]:getId()].goalIndex = 99
lead.route = {} lead.phase = "driving"
Convoy.nextTickMs = 0
CLOCK = CLOCK + 3000
Convoy.tick()
check("arrival reported", caravan.arrivals == 1, caravan.arrivals)
caravan.arrivals = #caravan.vehicleIds
CLOCK = CLOCK + 3000
Director.nextTickMs = 0
Director.tick()
check("next trip planned after arrival", caravan.trips == 1 and caravan.state == "rendered" and caravan.goals ~= nil and #caravan.route >= 2, caravan.state)

-- 12. attacked by the player: traders flee (reputation wrapper)
caravan.attackedAtMs = 0
local flights = A.metrics.flights
ProjectALife.Reputation.onPlayerDamagedActor(PLAYER, { uid = uids[1] })
check("attack reaction via reputation hook", A.metrics.flights == flights + 1 and DAMAGED == 1)

-- 13. horn hails
caravan.halted = nil
caravan.x, caravan.y = 40, 100
PLAYER.x, PLAYER.y = 48, 100
check("angry traders refuse the horn", (function() local n = #SAID Events.OnVehicleHorn.fire(PLAYER, nil, true) return caravan.halted == nil and #SAID == n + 1 end)())
caravan.angry = nil
Interact.hornAt = nil
Events.OnVehicleHorn.fire(PLAYER, nil, true)
check("horn flags down the nearest caravan", caravan.halted == true)
caravan.halted = nil

-- 14. release when the player is far
PLAYER.x, PLAYER.y = 1000, 1000
CLOCK = CLOCK + 3000
Director.nextTickMs = 0
Director.tick()
check("released when far", caravan.state == "offline", caravan.state)
check("cars removed", REMOVED_CARS == 2 and getVehicleById(CREATED[1]:getId()) == nil, REMOVED_CARS)
check("crew back in the ledger", DEHYDRATED == 5 and REMOVED_ACTORS == 5, DEHYDRATED .. "/" .. REMOVED_ACTORS)
check("sessions released", #RELEASED >= 2 and ProjectALife.DrivingDemoClient.sessions[CREATED[1]:getId()] == nil)
Director.publish(true)
check("known cleared", next(Convoy.known) == nil)
check("progress snapped to the route", caravan.leg >= 1 and caravan.t >= 0)

-- 15. a raider caravan: toll, then truce
PLAYER.x, PLAYER.y = 20, 100
Ledger.reset()
local raiders = Ledger.create({ name = "Road Wolves", factionId = "f_raid", factionName = "Road Wolves", kind = "raid", class = "raider", hostile = true,
    vehicles = { "Base.PickUpTruck" }, crew = { "f_raid_p1", "f_raid_p2" }, speedKmh = 35, route = { "townA", "townB" }, leg = 1, t = 0.3,
    x = 120, y = 100, trips = 0, state = "offline", createdMs = CLOCK, vehicleIds = {}, actorUids = {}, renderFailures = 0, nextRenderAtMs = 0,
    truce = {}, goalIndex = 1, goals = { { x = 200, y = 100 }, { x = 380, y = 100 } }, destName = "Bravo", offers = {} })
STANCE.f_raid = "hostile"
CREATED = {}
CLOCK = CLOCK + 20000
Director.renderCooldownUntilMs = 0
check("raiders render", Director.tryRender(raiders, Director.playerRows(), CLOCK) == true)
completeSpawn(raiders.requestId)
check("raiders rendered with one car", raiders.state == "rendered" and #raiders.vehicleIds == 1)
PLAYER.x, PLAYER.y = CREATED[1].x - 6, CREATED[1].y
raiders.x, raiders.y = CREATED[1].x, CREATED[1].y
local raiderCar = CREATED[1]:getId()
local tolls = A.metrics.tolls
Interact.command(PLAYER, "hail", { vehicleId = raiderCar })
check("raiders demand a toll", raiders.halted == true and A.metrics.tolls == tolls + 1 and string.find(SAID[#SAID].text, "60", 1, true) ~= nil, SAID[#SAID].text)
local money = INV:getCountTypeRecurse("Base.Money")
Interact.command(PLAYER, "toll", { vehicleId = raiderCar })
check("toll paid", INV:getCountTypeRecurse("Base.Money") == money - 60 and raiders.truce["ivan"] ~= nil and raiders.halted == nil, INV:getCountTypeRecurse("Base.Money"))
check("crew tolerates the player", TOLERATED["ivan"] ~= nil)
check("truce makes them neutral", Interact.stanceFor(raiders, PLAYER) == "neutral")
-- threaten raiders: they fight
local fights = A.metrics.fights
Interact.command(PLAYER, "threaten", { vehicleId = raiderCar })
check("raiders fight back", A.metrics.fights == fights + 1 and #WALKED >= 1 and raiders.state == "fighting")
check("fight sets the objective on the crew", ACTORS[raiders.actorUids[1]].memory.arrivalObjective ~= nil)

-- 16. stranded: every session finished
raiders.state = "rendered"
Director.onSessionFinished(raiders.id, raiderCar, "Driver died")
check("stranded when every car stopped", raiders.state == "stranded")
check("fallback skipped for our cars", (function() ProjectALife.VehicleArrivals.fallback(nil, raiderCar, nil, CLOCK) return FALLBACKS == 0 end)())

-- 17. lines and translations
local keys = Lines.keys()
local missing = {}
for _, key in ipairs(keys) do if TRANSLATIONS[key] == nil then missing[#missing + 1] = key end end
check("every line translated", #missing == 0, table.concat(missing, ","))
check("render fills variables", Lines.render("to {dest} via {town}", { dest = "A", town = "B" }) == "to A via B")
check("ui text fallback", Lines.ui("nope", "fallback {x}", { x = 1 }) == "fallback 1")
check("ui text translated", Lines.ui("hail", "x") ~= "x")

-- 18. client menu
raiders.state = "rendered"
Director.publish(true)
local ctx = newContext()
PLAYER.x, PLAYER.y = CREATED[1].x - 5, CREATED[1].y
Client.fill(0, ctx, {}, false)
check("menu root added", #ctx.options == 1 and string.find(ctx.options[1].name, "Caravan", 1, true) ~= nil, ctx.options[1] and ctx.options[1].name)
local sub = ctx.subs[ctx.options[1]]
check("menu has actions", sub ~= nil and #sub.options >= 3, sub and #sub.options)
check("no menu when the option is off", (function() Client.options.menu = false local c = newContext() Client.fill(0, c, {}, false) Client.options.menu = true return #c.options == 0 end)())
check("no menu far away", (function() PLAYER.x = 900 local c = newContext() Client.fill(0, c, {}, false) return #c.options == 0 end)())

-- 19. counters and status do not throw
check("status runs", pcall(A.status))
check("no errors counted", A.metrics.errors == 0, A.metrics.errors)

print(string.format("checks passed=%d failed=%d", passed, failed))
return failed
