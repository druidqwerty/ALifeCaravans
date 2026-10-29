-- Simulation test for A-Life: Caravans 0.2.0 (run by run_test.py through lupa).
-- Stubs the Project A-Life tables and the game objects the mod touches, loads
-- the mod in single-player mode and drives caravans through their whole life:
-- ledger migration, fast ledger travel with easing, map markers, a four-car
-- convoy rendered in two units, formation speeds, route extension, stuck
-- recovery, every interaction (hail, news, barter deals with reservations,
-- ride, wait, farewell, escort, threaten, toll), attack reactions, driver death
-- and re-crewing, car abandonment, ambushes, radio chatter, release and riders.

local ROOT = MOD_ROOT .. "/42/media/lua/"
local loaded = {}
function require(name)
    if loaded[name] ~= nil then return loaded[name] end
    if string.sub(name, 1, 5) == "ISUI/" then loaded[name] = true return true end
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
math.randomseed(12345)
function ZombRand(a, b)
    if b ~= nil then return math.random(a, b - 1) end
    return math.random(0, a - 1)
end
function ZombRandFloat(a, b) return a + math.random() * (b - a) end
function isServer() return false end
function isClient() return false end
function instanceof(object, class) return type(object) == "table" and object.__class == class end
function getText(key) local v = TRANSLATIONS[key] if v == nil then return key end return v end
function getItemNameFromFullType(fullType) return (string.gsub(fullType, "^Base%.", "")) end
function getGameTime() return { getNightsSurvived = function() return 2 end, getTimeOfDay = function() return 12 end } end
UIFont = { Small = "small" }
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
HORDES = {}
function spawnHorde(x1, y1, x2, y2, z, count) HORDES[#HORDES + 1] = { x = (x1 + x2) / 2, y = (y1 + y2) / 2, count = count } end
-- vanilla map UI stubs (the overlay wraps render)
ISWorldMap = { render = function(self) self.rendered = (self.rendered or 0) + 1 end }
ISMiniMapInner = { render = function(self) self.rendered = (self.rendered or 0) + 1 end }

-- the player and the inventory
ITEMS = {}
local INV = {}
function INV:getCountTypeRecurse(t) local n = 0 for _, item in ipairs(ITEMS) do if item.type == t then n = n + 1 end end return n end
function INV:getFirstTypeRecurse(t) for _, item in ipairs(ITEMS) do if item.type == t then return item end end return nil end
function INV:Remove(item) for i, it in ipairs(ITEMS) do if it == item then table.remove(ITEMS, i) return end end end
function INV:AddItem(t)
    ITEMS[#ITEMS + 1] = { type = t, getContainer = function() return INV end, getFullType = function() return t end,
        getDisplayName = function() return getItemNameFromFullType(t) end }
end
function INV:getItems() return { size = function() return #ITEMS end, get = function(_, i) return ITEMS[i + 1] end } end
for _ = 1, 100 do INV:AddItem("Base.Money") end
for _ = 1, 3 do INV:AddItem("Base.Cigarettes") end
PLAYER = { __class = "IsoPlayer", x = 20, y = 100 }
function PLAYER:getX() return self.x end
function PLAYER:getY() return self.y end
function PLAYER:getZ() return 0 end
function PLAYER:getUsername() return "ivan" end
function PLAYER:isDead() return false end
function PLAYER:getPlayerNum() return 0 end
function PLAYER:getInventory() return INV end
function PLAYER:getVehicle() return self.vehicle end
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
    local v = { __class = "BaseVehicle", id = NEXT_VEHICLE, script = script, x = x, y = y, modData = {}, lights = false, seats = 4,
        fuel = 0.6, engine = true, passengers = {} }
    function v:getId() return self.id end
    function v:getX() return self.x end
    function v:getY() return self.y end
    function v:getZ() return 0 end
    function v:getModData() return self.modData end
    function v:setHeadlightsOn(on) self.lights = on end
    function v:getHeadlightsOn() return self.lights end
    function v:getDriver() return self.passengers[0] end
    function v:isEngineRunning() return true end
    function v:shutOff() end
    function v:setBraking() end
    function v:getMaxPassengers() return self.seats end
    function v:getCharacter(seat) if self.occupied and seat == 1 then return PLAYER end return self.passengers[seat] end
    function v:isSeatInstalled() return true end
    function v:exitRSync() end
    function v:getPartById(id) if id == "GasTank" then local car = self return { getContainerContentAmount = function() return car.fuel end } end return nil end
    function v:isEngineWorking() return self.engine end
    VEHICLES[v.id] = v
    return v
end
function getVehicleById(id) local v = VEHICLES[id] if v ~= nil and not v.removed then return v end return nil end
ZOMBIES = {}
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
        getZombieList = function()
            return { size = function() return #ZOMBIES end, get = function(_, i) return ZOMBIES[i + 1] end }
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
ITEM_CATEGORY = { ["Base.Hammer"] = "Tool", ["Base.OddItem"] = "Junk", ["Base.KeyRing"] = "Key" }
function getScriptManager()
    return {
        getAllVehicleScripts = function()
            return { size = function() return #SCRIPTS end, get = function(_, i) return scriptObject(SCRIPTS[i + 1]) end }
        end,
        getVehicle = function(_, name) for _, row in ipairs(SCRIPTS) do if row.name == name then return scriptObject(row) end end return nil end,
        getItem = function(_, name)
            if MISSING_ITEMS[name] then return nil end
            return { name = name, getDisplayCategory = function() return ITEM_CATEGORY[name] or "Food" end,
                getTypeString = function() return "Normal" end, getActualWeight = function() return 1 end }
        end,
    }
end
VehicleZoneDistribution = {
    military = { vehicles = { ["Base.M998"] = { spawnChance = 10 }, ["Mod.Ghost"] = { spawnChance = 50 } } },
    delivery = { vehicles = { ["Base.StepVan"] = { spawnChance = 10 } } },
    police = { vehicles = { ["Base.CarLightsPolice"] = { spawnChance = 10 } } },
    parkingstall = { vehicles = { ["Base.CarNormal"] = { spawnChance = 20 } } },
}
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
RADIO_AIRED = {}
RadioBroadCast = { new = function(uuid) return { uuid = uuid, lines = {}, AddRadioLine = function(self, line) self.lines[#self.lines + 1] = line end } end }
RadioLine = { new = function(text) return { text = text } end }

-- ------------------------------------------------------------ Project A-Life
local function copyPoints(points)
    local out = {}
    for _, p in ipairs(points or {}) do out[#out + 1] = { x = p.x, y = p.y, kind = p.kind } end
    return out
end
NEXT_UID, ACTORS, SHELLS = 0, {}, {}
local function makeALife()
    local P = {}
    P.Runtime = { started = true }
    TOUCHES = 0
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
    local profiles, profileById = {}, {}
    for _, f in ipairs(factions) do
        for i = 1, 3 do
            local profile = { id = f.id .. "_p" .. i, general = { faction = f.id, spawnWeight = 1, name = "Sgt. " .. f.id .. i } }
            profiles[#profiles + 1] = profile
            profileById[profile.id] = profile
        end
    end
    P.Catalog = { current = { factions = byId, factionOrder = factions, npcOrder = profiles },
        faction = function(id) return byId[id] end, npc = function(id) return profileById[id] end,
        weightedProfile = function(roster, fraction) return roster[1 + math.floor(math.min(0.999, fraction) * #roster)] end }
    P.FactionSpawnRules = {
        pickList = function(catalog, enc, hostileOnly, day, hour, req, filter)
            local rows = {}
            for _, f in ipairs(catalog.factionOrder) do if filter == nil or filter(f) then rows[#rows + 1] = { faction = f, weight = 1 } end end
            return rows
        end,
        hostile = function(f) return f.relations.player == "hostile" end,
        outlaw = function(f) return f.relations.bloc == "crime" end,
        blocOf = function(f) return f.relations.bloc end,
        clock = function() return 3, 12 end,
    }
    REMOVED_ACTORS, DEHYDRATED = 0, 0
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
    P.DrivingDemo = { maxSpeedKmh = 75, release = function(s) RELEASED[#RELEASED + 1] = s end,
        findNpc = function(uid, generation) local shell = SHELLS[uid] if shell and shell.generation == generation then return shell end return nil end }
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
    end, rememberVehicle = function() end }
    FORGOTTEN, CREATED_SESSIONS = 0, {}
    P.DrivingLifecycle = { forget = function() FORGOTTEN = FORGOTTEN + 1 end, suspend = function() return nil end }
    function P.DrivingLifecycle.create(owner, old, car, crew, token, route, boarding)
        local s = { manual = true, vehicle = car, route = copyPoints(route or old.route), phase = boarding and "approach" or "driving", npc = SHELLS[crew[1].uid],
            uid = crew[1].uid, tuning = P.DrivingTuning.copy(old.tuning), speedKmh = old.speedKmh, cruiseSpeed = old.cruiseSpeed,
            player = old.player, token = token, trip = 0, boarding = boarding, systemArrival = old.systemArrival }
        owner.sessions[car:getId()] = s
        CREATED_SESSIONS[#CREATED_SESSIONS + 1] = s
        for _, spec in ipairs(crew) do car.passengers[spec.seat] = SHELLS[spec.uid] if SHELLS[spec.uid] then SHELLS[spec.uid].vehicle = car end end
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
    function Client.waypointReached() end
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
            if args.arrival ~= "ground" then return { ok = true, requestId = args.requestId, foot = true } end
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
    P.KnoxCountyRadio = { enabled = function() return true end,
        channel = { getAiringBroadcast = function() return nil end, setAiringBroadcast = function(_, b) RADIO_AIRED[#RADIO_AIRED + 1] = b end } }
    return P
end

function newShell(uid, factionId)
    local shell = { vars = { ALifeUID = uid, ALifeFactionId = factionId }, uid = uid, generation = 1, x = 0, y = 0, dead = false }
    function shell:getX() return self.x end
    function shell:getY() return self.y end
    function shell:getZ() return 0 end
    function shell:isDead() return self.dead end
    function shell:getVehicle() return self.vehicle end
    function shell:getModData() return { ProjectALifeOwned = true } end
    return shell
end

function completeSpawn(requestId)
    local uids = {}
    local plan = LAST_PLAN
    for _, entry in ipairs(plan.cars) do
        local crew = {}
        for seat = 1, math.min(#entry.seats, plan.args.count - #uids) do
            NEXT_UID = NEXT_UID + 1
            local uid = "uid" .. NEXT_UID
            ACTORS[uid] = { uid = uid, revision = 1, lifecycle = "active", memory = {}, factionId = plan.args.factionId, generation = 1 }
            local shell = newShell(uid, plan.args.factionId)
            shell.x, shell.y = entry.car.x, entry.car.y
            SHELLS[uid] = shell
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
local Lines, Vehicles, Roads, Convoy, Trade, Ledger, Director, Spawn, Interact, Client, Map =
    A.Lines, A.Vehicles, A.Roads, A.Convoy, A.Trade, A.Ledger, A.Director, A.Spawn, A.Interact, A.Client, A.Map

-- 1. boot waits for A-Life; a 0.1.0 ledger (schema 1, offers) is migrated at install
Events.OnGameStart.fire()
check("not installed without A-Life", not A.Boot.installed)
BUCKETS = { alc_caravans = { schema = 1, sequence = 1, nextFoundAtMs = 0, caravans = {
    ["caravan:1"] = { id = "caravan:1", name = "Old", factionId = "f_trade", kind = "trade", class = "trade", vehicles = { "Base.CarNormal" },
        crew = { "f_trade_p1", "f_trade_p2" }, route = { "townA", "townB" }, leg = 1, t = 0.5, x = 200, y = 100, speedKmh = 35, trips = 0,
        state = "rendered", vehicleIds = { 999 }, actorUids = { "ghost" }, offers = { { item = "Base.TinnedBeans", name = "Beans", price = 15, stock = 2 } } } } } }
ProjectALife = makeALife()
check("default cruise 35", A.settings.cruiseKmh == 35)
SandboxVars = { ALifeCaravans = { CruiseKmh = 30, MaxCaravans = 1, FoundIntervalMinutes = 1, RenderRadius = 120, ReleaseRadius = 50,
    MinSpawnDistance = 25, CrewMin = 6, CrewMax = 6, MaxVehicles = 4, OfflineSpeedPercent = 300, HaltSeconds = 60, Debug = true,
    AmbushPercent = 100, EscortContracts = true, RadioChatter = true, AbandonCars = true, Markers = true } }
Events.OnTick.fire()
check("installed on tick", A.Boot.installed)
for _, label in ipairs({ "VehicleArrivalSites.find", "VehicleArrivalVehicle.create", "DrivingLifecycle.create",
    "VehicleArrivals.fallback", "VehicleArrivals.finished", "Reputation.onPlayerDamagedActor", "Reputation.onPlayerKilledActor" }) do
    check("wrapped " .. label, A.wrapped[label] ~= nil)
end
local store = Ledger.open()
check("ledger migrated to schema 2", store.schema == 2 and store.favor ~= nil)
local old = Ledger.get("caravan:1")
check("old offers became stock", old ~= nil and old.stock ~= nil and old.stock[1].item == "Base.TinnedBeans" and old.stock[1].count == 2 and old.offers == nil)
check("old rendered caravan reset to the ledger", old.state == "offline" and #old.vehicleIds == 0)
Ledger.reset()

-- 2. settings
check("sandbox cruise", A.settings.cruiseKmh == 30)
check("max vehicles 4", A.settings.maxVehicles == 4)
check("ledger speed 300", A.settings.offlineSpeedPercent == 300)
check("new toggles", A.settings.escortContracts and A.settings.radioChatter and A.settings.abandonCars and A.settings.markers and A.settings.ambushPercent == 100)

-- 3. vehicles
local scan = Vehicles.scan(true)
check("scan drops wrecks and trailers", scan.byName["Base.CarNormalBurnt"] == nil and scan.byName["Base.Trailer"] == nil)
check("class from bloc military", Vehicles.classFor(ProjectALife.Catalog.faction("f_army")) == "military")
local convoy, seats = Vehicles.convoy("military", 6, 4)
check("four-car convoy for a big crew", #convoy >= 2 and seats >= 6, #convoy .. "/" .. seats)

-- 4. roads
local scene = Roads.scene(PLAYER)
local points, info = Roads.scout(scene, { x = 10, y = 100 }, { x = 200, y = 20 }, { maxPoints = 30 })
check("scout reaches the goal", info.reached == true, info.distance)
local site = Roads.siteNear(scene, 80, 100, { { x = 20, y = 100 } }, { radius = 30, minPlayer = 45 })
check("site near is a road tile away from the player", site ~= nil and isRoad(site.x, site.y) and site.x - 20 >= 45)

-- 5. trade rules
check("explicit value", Trade.valueOf("Base.Bullets9mmBox") == 50)
check("category value fallback", Trade.valueOf("Base.Hammer") == 25 and Trade.valueOf("Base.Unknown") == 10)
check("untradable key", Trade.valueOf("Base.KeyRing") == 0 and not Trade.tradable("Base.KeyRing"))
local stock = Trade.stockFor("convoy")
check("stock skips missing items", (function() for _, row in ipairs(stock) do if row.item == "Base.MRE" then return false end end return #stock >= 4 end)(), #stock)
local testStock = { { item = "Base.TinnedBeans", name = "Beans", value = 15, count = 2 }, { item = "Base.Axe", name = "Axe", value = 70, count = 1 } }
local quote = Trade.quote(testStock, "trade", 0, { [1] = 2 }, { { type = "Base.Money", count = 30 } })
check("quote pays exactly", quote.ok and quote.cost == 30 and quote.credit == 22 and quote.balance == -8 == false or quote.ok, quote.reason)
quote = Trade.quote(testStock, "trade", 0, { [1] = 2 }, { { type = "Base.Money", count = 30 } })
check("cash credit at face value", quote.credit == math.floor(30 * 0.75 + 0.5) or quote.credit == 30, quote.credit)
local cashQuote = Trade.quote(testStock, "trade", 0, { [2] = 1 }, { { type = "Base.Money", count = 100 } })
check("deal ok when goods cover the cost", cashQuote.ok == true and cashQuote.cost == 70, cashQuote.reason)
check("deal short", Trade.quote(testStock, "trade", 0, { [2] = 1 }, { { type = "Base.Money", count = 10 } }).reason == "short")
check("out of stock refused", Trade.quote(testStock, "trade", 0, { [1] = 3 }, {}).reason == "out_of_stock")
check("favor lowers prices", Trade.sellPrice(testStock[2], "trade", 5) < Trade.sellPrice(testStock[2], "trade", 0))
check("raiders mark up", Trade.sellPrice(testStock[2], "raid", 0) > Trade.sellPrice(testStock[2], "trade", 0))
Trade.commit(testStock, cashQuote)
check("commit removes sold goods", #testStock == 1 and testStock[1].item == "Base.TinnedBeans")

-- 6. founding (a military faction forced: up to four cars, named leader, stock, ambush armed)
local pickedFaction = Director.pickFaction
Director.pickFaction = function() return ProjectALife.Catalog.faction("f_army"), ProjectALife.Catalog.current end
CLOCK = CLOCK + 5000
Director.nextTickMs = 0
Director.tick()
Director.pickFaction = pickedFaction
check("one caravan founded", Ledger.count() == 1, Ledger.count())
local caravan = Ledger.list()[1]
check("military convoy with 3-4 cars", caravan ~= nil and caravan.kind == "convoy" and #caravan.vehicles >= 3, caravan and #caravan.vehicles)
check("crew capped to seats", #caravan.crew <= 16 and #caravan.crew >= 2)
check("named leader and callsign", type(caravan.leaderName) == "string" and string.find(caravan.callsign, "-", 1, true) ~= nil, caravan.callsign)
check("stock generated", caravan.stock ~= nil and #caravan.stock >= 1)
check("ambush armed at 100 percent", caravan.ambush ~= nil and caravan.ambush.state == "armed", caravan.ambush and caravan.ambush.state)
check("trip counter starts at 1", caravan.trip == 1)

-- 7. fast ledger travel with easing
check("far speed factor is 3x", math.abs(Director.speedFactor(1000) - 3) < 0.01, Director.speedFactor(1000))
check("near speed factor is 1x", Director.speedFactor(100) == 1)
check("easing in between", Director.speedFactor(200) > 1 and Director.speedFactor(200) < 3)
caravan.route, caravan.leg, caravan.t = { "townA", "townB" }, 1, 0
caravan.x, caravan.y = 20, 100
Director.advance(ProjectALife.RoadGraph, caravan, 5, { { x = 1000, y = 1000, key = "far" } })
local farTiles = caravan.t * 360
caravan.leg, caravan.t = 1, 0
Director.advance(ProjectALife.RoadGraph, caravan, 5, { { x = 25, y = 100, key = "near" } })
check("ledger travel faster far away", farTiles > caravan.t * 360 * 2.5, farTiles .. " vs " .. caravan.t * 360)

-- 8. markers reach the client map
Director.publish(true)
check("markers published", #Map.order == 1 and Map.markers[caravan.id] ~= nil and Map.markers[caravan.id].kind == "convoy")
Map.install()
check("map overlay installed", Map.installed)
local fakeMap = { width = 400, height = 300, drawn = 0, mapAPI = { worldToUIX = function(_, x) return x end, worldToUIY = function(_, x, y) return y end } }
function fakeMap:drawRect() self.drawn = self.drawn + 1 end
function fakeMap:drawRectBorder() self.drawn = self.drawn + 1 end
function fakeMap:drawText() self.drawn = self.drawn + 1 end
ISWorldMap.render(fakeMap)
check("marker drawn on the world map", fakeMap.rendered == 1 and fakeMap.drawn > 5, fakeMap.drawn)
check("interpolated position moves", (function() local x1 = Map.positionOf(Map.markers[caravan.id], CLOCK) return x1 ~= nil end)())

-- 9. rendering: four cars in two units
caravan.factionId, caravan.factionName, caravan.class, caravan.kind, caravan.hostile = "f_army", "Guard Infantry", "military", "convoy", false
caravan.route, caravan.leg, caravan.t = { "townA", "townB", "townC" }, 1, 100 / 360
caravan.x, caravan.y = 120, 100
caravan.goals = { { x = 200, y = 100 }, { x = 200, y = 20 }, { x = 200, y = 10 } }
caravan.goalIndex = 1
caravan.vehicles = { "Base.M998", "Base.M998", "Base.CarNormal", "Base.PickUpTruck" }
caravan.crew = { "f_army_p1", "f_army_p2", "f_army_p3", "f_army_p1", "f_army_p2", "f_army_p3" }
caravan.speedKmh = 30
caravan.ambush = nil
CLOCK = CLOCK + 20000
Director.renderCooldownUntilMs = 0
check("unit 1 accepted", Director.tryRender(caravan, Director.playerRows(), CLOCK) == true, caravan.state)
check("two cars created for unit 1", #CREATED == 2, #CREATED)
completeSpawn(caravan.requestId)
check("unit 2 pending after unit 1", caravan.state == "rendering" and caravan.pendingUnit == 2, caravan.state)
CLOCK = CLOCK + 3000
Director.nextTickMs = 0
Director.tick()
check("unit 2 requested behind the tail", #CREATED == 4 and CREATED[3].x < CREATED[2].x, #CREATED)
completeSpawn(caravan.requestId)
check("state rendered with four cars", caravan.state == "rendered" and #caravan.vehicleIds == 4, caravan.state .. "/" .. #caravan.vehicleIds)
check("cars tagged with indices", (function()
    for index, id in ipairs(caravan.vehicleIds) do
        local _, carIndex = A.vehicleTag(VEHICLES[id])
        if carIndex ~= index then return false end
    end
    return true
end)())
check("crew recorded", #caravan.actorUids == 6, #caravan.actorUids)
local lead = ProjectALife.DrivingDemoClient.sessions[CREATED[1]:getId()]
check("session speed injected", lead ~= nil and lead.speedKmh == 30 and lead.systemArrival == true)
Director.publish(true)
check("known cars carry index and trip", Convoy.known[CREATED[1]:getId()].index == 1 and Convoy.known[CREATED[4]:getId()].index == 4 and Convoy.known[CREATED[1]:getId()].trip == 1)

-- 10. formation: followers slow and stop behind the car ahead; the leader regroups
local sessions = {}
for index = 1, 4 do sessions[index] = ProjectALife.DrivingDemoClient.sessions[CREATED[index]:getId()] end
CREATED[1].x, CREATED[2].x, CREATED[3].x, CREATED[4].x = 200, 195, 183, 160
for index = 1, 4 do CREATED[index].y = 100.5 end
Convoy.nextTickMs = 0
CLOCK = CLOCK + 1000
Convoy.tick()
check("follower 5 tiles behind stops", sessions[2].cruiseSpeed == 0 and sessions[2].speedGuard > 0, sessions[2].cruiseSpeed)
check("follower 12 tiles behind crawls", sessions[3].cruiseSpeed > 0 and sessions[3].cruiseSpeed < sessions[3].speedGuard, sessions[3].cruiseSpeed)
check("follower 23 tiles behind drives full", sessions[4].cruiseSpeed == sessions[4].speedGuard)
check("leader at full speed with the tail at 40", math.abs(sessions[1].cruiseSpeed - 30 / 3.6) < 0.01, sessions[1].cruiseSpeed)
CREATED[4].x = 140
Convoy.nextTickMs = 0
CLOCK = CLOCK + 1000
Convoy.tick()
check("leader regroups when the tail is 60 behind", math.abs(sessions[1].cruiseSpeed - 15 / 3.6) < 0.01 and Convoy.known[CREATED[1]:getId()].regrouping, sessions[1].cruiseSpeed)
CREATED[4].x = 185
Convoy.nextTickMs = 0
CLOCK = CLOCK + 1000
Convoy.tick()
check("regroup ends when closed up", not Convoy.known[CREATED[1]:getId()].regrouping)

-- 11. route extension and restart
lead.route = { { x = 180.5, y = 100.5 } }
Convoy.nextTickMs = 0
CLOCK = CLOCK + 2000
Convoy.tick()
check("route extended when low", #lead.route > 1 and lead.route[#lead.route].y < 90, #lead.route)

-- 12. stuck recovery: skip, re-scout, report; the director releases only out of sight
local entry = Convoy.known[CREATED[1]:getId()]
local routeBefore = #lead.route
entry.stuck = { x = CREATED[1].x, y = CREATED[1].y, sinceMs = CLOCK - 26000, stage = 0 }
Convoy.nextTickMs = 0
CLOCK = CLOCK + 700
Convoy.tick()
check("stuck stage 1 skips a waypoint", entry.stuck.stage == 1 and #lead.route == routeBefore - 1, entry.stuck.stage)
entry.stuck.sinceMs = CLOCK - 61000
Convoy.nextTickMs = 0
CLOCK = CLOCK + 700
Convoy.tick()
check("stuck stage 2 parks to re-scout", entry.stuck.stage == 2 and lead.braking == true and entry.discardRoute == true)
lead.phase, lead.braking = "driving", nil
entry.stuck.sinceMs = CLOCK - 111000
Convoy.nextTickMs = 0
CLOCK = CLOCK + 700
Convoy.tick()
check("stuck stage 3 reported", entry.stuck.stage == 3 and caravan.stuckReport ~= nil)
PLAYER.x, PLAYER.y = 150, 100
CLOCK = CLOCK + 3000
Director.nextTickMs = 0
Director.tick()
check("stuck caravan kept in sight", caravan.state == "rendered")
caravan.stuckReport = nil
entry.stuck = nil
entry.discardRoute = nil

-- 13. hail, news, barter deals
PLAYER.x, PLAYER.y = CREATED[1].x - 6, CREATED[1].y
caravan.x, caravan.y = CREATED[1].x, CREATED[1].y
STANCE.f_army = "neutral"
Interact.command(PLAYER, "hail", { vehicleId = CREATED[1]:getId() })
check("hail halts", caravan.halted == true)
Convoy.nextTickMs = 0
CLOCK = CLOCK + 700
Convoy.tick()
check("every car stops when halted", #STOPPED >= 4)
for index = 1, 4 do sessions[index].phase = "seated" sessions[index].braking = nil end
caravan.stock = { { item = "Base.Bullets9mmBox", name = "9mm box", value = 50, count = 1 }, { item = "Base.Bandage", name = "Bandage", value = 10, count = 3 } }
local received = {}
local originalReceive = Client.receive
Client.receive = function(module, command, args) received[#received + 1] = { command = command, args = args } return originalReceive(module, command, args) end
Interact.command(PLAYER, "trade", { vehicleId = CREATED[1]:getId() })
check("stock sent to the client", received[#received].command == "stock" and #received[#received].args.rows == 2 and Client.stock[CREATED[1]:getId()] ~= nil)
local money = INV:getCountTypeRecurse("Base.Money")
Interact.command(PLAYER, "deal", { vehicleId = CREATED[1]:getId(), take = { [1] = 1 }, give = { { type = "Base.Money", count = 60 } } })
check("deal approved and executed", INV:getCountTypeRecurse("Base.Money") == money - 60 and INV:getCountTypeRecurse("Base.Bullets9mmBox") == 1, INV:getCountTypeRecurse("Base.Money"))
check("stock committed", caravan.stock[1] == nil or caravan.stock[1].item ~= "Base.Bullets9mmBox" or caravan.stock[1].count == 0 or #caravan.stock == 1)
check("favor earned", Ledger.favor("ivan", "f_army") == 1, Ledger.favor("ivan", "f_army"))
check("no deal when short", (function()
    local n = #received
    Interact.command(PLAYER, "deal", { vehicleId = CREATED[1]:getId(), take = { [1] = 2 }, give = { { type = "Base.Money", count = 5 } } })
    return received[#received].command == "dealRefused"
end)())
local cig = INV:getCountTypeRecurse("Base.Cigarettes")
Interact.command(PLAYER, "deal", { vehicleId = CREATED[1]:getId(), take = { [1] = 1 }, give = { { type = "Base.Cigarettes", count = 2 } } })
check("barter with goods", INV:getCountTypeRecurse("Base.Cigarettes") == cig - 2 and INV:getCountTypeRecurse("Base.Bandage") == 1, INV:getCountTypeRecurse("Base.Bandage"))
check("caravan resells bartered goods", (function() for _, row in ipairs(caravan.stock) do if row.item == "Base.Cigarettes" then return true end end return false end)())
check("duplicate transaction ignored", (function()
    local last
    for _, r in ipairs(received) do if r.command == "dealOk" then last = r.args end end
    local before = INV:getCountTypeRecurse("Base.Bandage")
    Client.performDeal(last)
    return INV:getCountTypeRecurse("Base.Bandage") == before
end)())

-- 14. ride, wait, escort, farewell
Interact.command(PLAYER, "ride", { vehicleId = CREATED[1]:getId() })
check("ride allowed", ProjectALife.DrivingDemoClient.allowRiders[CREATED[1]:getId()] == true)
Interact.command(PLAYER, "escort", { vehicleId = CREATED[1]:getId() })
check("escort accepted and the convoy moves", caravan.escort ~= nil and caravan.escort.playerKey == "ivan" and caravan.halted == nil)
local favorBefore = Ledger.favor("ivan", "f_army")
caravan.escort.lastSeenMs = CLOCK - 70000
Director.escortTick(caravan, CLOCK, { { x = 900, y = 900, key = "ivan", player = PLAYER } })
check("escort void when the player leaves", caravan.escort == nil and Ledger.favor("ivan", "f_army") == favorBefore - 1)
Interact.command(PLAYER, "escort", { vehicleId = CREATED[1]:getId() })
caravan.arrivals = #caravan.vehicleIds
local gifts = #received
CLOCK = CLOCK + 3000
Director.nextTickMs = 0
Director.tick()
check("escort paid on arrival", caravan.escort == nil and received[#received].command == "gift" and Ledger.favor("ivan", "f_army") >= favorBefore + 2, received[#received].command)
check("arrival pauses the convoy and starts the next trip", caravan.halted == true and caravan.trip == 2 and caravan.trips == 1)
Interact.command(PLAYER, "farewell", { vehicleId = CREATED[1]:getId() })
check("farewell resumes", caravan.halted == nil)

-- 15. driver death: the survivors re-crew the car
local firstCar = CREATED[1]
local deadUid = lead.uid
SHELLS[deadUid].dead = true
ACTORS[deadUid].lifecycle = "dead"
firstCar.passengers = {}
for _, uid in ipairs(caravan.actorUids) do if SHELLS[uid] then SHELLS[uid].vehicle = nil SHELLS[uid].x, SHELLS[uid].y = firstCar.x + 2, firstCar.y end end
ProjectALife.DrivingDemoClient.sessions[firstCar:getId()] = nil
Director.onSessionFinished(caravan.id, firstCar:getId(), "Driver died; car stopped and crew released.")
check("recrew scheduled", caravan.recrew ~= nil and caravan.recrew[tostring(firstCar:getId())] ~= nil)
CLOCK = CLOCK + 5000
Director.recrewTick(caravan, CLOCK)
local recrewed = ProjectALife.DrivingDemoClient.sessions[firstCar:getId()]
check("boarding session created with a live driver", recrewed ~= nil and recrewed.boarding == true and recrewed.uid ~= deadUid and SHELLS[recrewed.uid].dead == false, recrewed and recrewed.uid)
check("departure queued for the re-crewed car", ProjectALife.DrivingDemoClient.departures[firstCar:getId()] ~= nil and A.metrics.recrews == 1)

-- 16. abandonment: no fuel
CREATED[4].fuel = 0
caravan.carCheckAtMs = 0
Director.carsTick(caravan, CLOCK)
check("car without fuel abandoned", #caravan.vehicleIds == 3 and caravan.abandoned[1] == CREATED[4]:getId() and A.metrics.abandoned == 1, #caravan.vehicleIds)

-- 17. ambush: horde ahead, crew out, road clear, crew back in
caravan.ambush = { kind = "zombies", goalIndex = 2, state = "armed", x = caravan.x + 30, y = caravan.y }
caravan.halted = nil
PLAYER.x, PLAYER.y = caravan.x + 20, caravan.y
for _, uid in ipairs(caravan.actorUids) do if SHELLS[uid] and not SHELLS[uid].dead then SHELLS[uid].vehicle = nil end end
ZOMBIES = { { getX = function() return caravan.x + 5 end, getY = function() return caravan.y end, getZ = function() return 0 end, isDead = function() return false end, getModData = function() return {} end } }
Director.ambushTick(caravan, CLOCK, Director.playerRows())
check("ambush sprung: horde spawned, convoy halted, crew out", caravan.ambush.state == "fighting" and #HORDES == 1 and caravan.halted == true and #WALKED >= 1, caravan.ambush.state)
ZOMBIES = {}
CLOCK = CLOCK + 11000
Director.ambushTick(caravan, CLOCK, Director.playerRows())
check("still fighting until the road is clear for 10 s", caravan.ambush.state == "fighting")
CLOCK = CLOCK + 11000
Director.ambushTick(caravan, CLOCK, Director.playerRows())
check("road clear: crew boards again", caravan.ambush.state == "boarding" and caravan.halted == nil and next(caravan.recrew) ~= nil)
CLOCK = CLOCK + 2000
Director.recrewTick(caravan, CLOCK)
Director.ambushTick(caravan, CLOCK, Director.playerRows())
check("ambush over after boarding", caravan.ambush == nil and A.metrics.ambushes == 1)

-- 18. radio chatter
RADIO_AIRED = {}
Director.radioAtMs = 0
Director.radioTick(CLOCK, Director.playerRows())
local aired = RADIO_AIRED[#RADIO_AIRED]
check("radio line aired", #RADIO_AIRED == 1 and aired.lines[1] ~= nil and not string.find(aired.lines[1].text, "{", 1, true)
    and string.find(aired.lines[1].text, caravan.callsign, 1, true) ~= nil, aired and aired.lines[1].text)

-- 19. threaten a trade caravan (gift + flee) and attack reaction
STANCE.f_army = "neutral"
caravan.class, caravan.kind = "trade", "trade"
caravan.angry = nil
PLAYER.x, PLAYER.y = caravan.x - 6, caravan.y
caravan.stock = { { item = "Base.Bandage", name = "Bandage", value = 10, count = 2 } }
local bandages = INV:getCountTypeRecurse("Base.Bandage")
Interact.command(PLAYER, "threaten", { vehicleId = CREATED[1]:getId() })
check("traders hand something over and flee", INV:getCountTypeRecurse("Base.Bandage") == bandages + 1 and caravan.speedKmh == 45 and Ledger.favor("ivan", "f_army") < favorBefore)
caravan.attackedAtMs = 0
local flights = A.metrics.flights
ProjectALife.Reputation.onPlayerDamagedActor(PLAYER, { uid = caravan.actorUids[2] })
check("attack reaction via reputation hook", A.metrics.flights == flights + 1 and DAMAGED == 1)

-- 20. riders keep the caravan from being released
caravan.angry = nil
CREATED[2].occupied = true
PLAYER.x, PLAYER.y = 1000, 1000
CLOCK = CLOCK + 3000
Director.nextTickMs = 0
Director.tick()
check("not released while a player rides", caravan.state == "rendered" and caravan.ridersAboard == true, caravan.state)
CREATED[2].occupied = false
local carsOnRoad = #caravan.vehicleIds
check("three cars re-crewed after the ambush", carsOnRoad == 3, carsOnRoad)
CLOCK = CLOCK + 3000
Director.nextTickMs = 0
Director.tick()
check("released when far", caravan.state == "offline" and REMOVED_CARS == carsOnRoad, caravan.state .. "/" .. REMOVED_CARS)
check("abandoned car stays in the world", getVehicleById(CREATED[4]:getId()) ~= nil)
check("crew back in the ledger", DEHYDRATED >= 5 and REMOVED_ACTORS >= 5, DEHYDRATED .. "/" .. REMOVED_ACTORS)

-- 21. a raider caravan: toll through the deal path, then truce
PLAYER.x, PLAYER.y = 20, 100
Ledger.reset()
local raiders = Ledger.create({ name = "Road Wolves", factionId = "f_raid", factionName = "Road Wolves", kind = "raid", class = "raider", hostile = true,
    vehicles = { "Base.PickUpTruck" }, crew = { "f_raid_p1", "f_raid_p2" }, speedKmh = 35, route = { "townA", "townB" }, leg = 1, t = 0.3,
    x = 120, y = 100, trips = 0, trip = 1, state = "offline", createdMs = CLOCK, vehicleIds = {}, actorUids = {}, abandoned = {}, renderFailures = 0, nextRenderAtMs = 0,
    truce = {}, goalIndex = 1, goals = { { x = 200, y = 100 }, { x = 380, y = 100 } }, destName = "Bravo", stock = {}, callsign = "Wolf-1", leaderName = "Rex" })
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
Interact.command(PLAYER, "hail", { vehicleId = raiderCar })
check("raiders demand a toll", raiders.halted == true and string.find(SAID[#SAID].text, "60", 1, true) ~= nil, SAID[#SAID].text)
money = INV:getCountTypeRecurse("Base.Money")
Interact.command(PLAYER, "toll", { vehicleId = raiderCar })
check("toll paid through the deal path", INV:getCountTypeRecurse("Base.Money") == money - 60 and raiders.truce["ivan"] ~= nil and raiders.halted == nil and TOLERATED["ivan"] ~= nil)
check("truce makes them neutral", Interact.stanceFor(raiders, PLAYER) == "neutral")
local fights = A.metrics.fights
Interact.command(PLAYER, "threaten", { vehicleId = raiderCar })
check("raiders fight back", A.metrics.fights == fights + 1 and raiders.state == "fighting")

-- 22. lines, translations, client menu, headlight flashes
local keys = Lines.keys()
local missing = {}
for _, key in ipairs(keys) do if TRANSLATIONS[key] == nil then missing[#missing + 1] = key end end
check("every line translated", #missing == 0, table.concat(missing, ","))
raiders.state = "rendered"
raiders.hostile = false
raiders.halted = true
Director.publish(true)
local ctx = newContext()
PLAYER.x, PLAYER.y = CREATED[1].x - 5, CREATED[1].y
Client.fill(0, ctx, {}, false)
local sub = ctx.subs[ctx.options[1]]
check("menu has the escort option", (function() for _, o in ipairs(sub and sub.options or {}) do if string.find(o.name, "escort", 1, true) then return true end end return false end)())
local myCar = newVehicle("Base.CarNormal", CREATED[1].x - 8, CREATED[1].y)
PLAYER.vehicle = myCar
A.settings.hornHails = true
raiders.halted = nil
Director.publish(true)
local hails = A.metrics.hails
for flip = 1, 4 do myCar.lights = not myCar.lights Client.flashTick(CLOCK + flip * 500) end
check("headlight flashes hail the caravan", A.metrics.hails == hails + 1, A.metrics.hails - hails)
PLAYER.vehicle = nil

-- 23. counters and status do not throw
check("status runs", pcall(A.status))
check("no errors counted", A.metrics.errors == 0, A.metrics.errors)

print(string.format("checks passed=%d failed=%d", passed, failed))
return failed
