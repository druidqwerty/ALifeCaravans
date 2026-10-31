-- A-Life: Caravans - materialising a caravan (server / single player).
-- A caravan near a player becomes real through A-Life's own "arrive by car"
-- pipeline (DebugService.rawSpawn with arrival="ground" -> VehicleArrivals):
-- A-Life creates the cars, spawns the crew straight into the seats, hands the
-- car to a driving session (and, in multiplayer, to the nearest client). The
-- pipeline makes at most two cars per request, so a convoy of three or four
-- cars is rendered in two "units", the second one behind the first.
-- Four small hooks make the pipeline ours while one of our requests is in flight:
--   VehicleArrivalSites.find      -> our road site on the caravan's route and our waypoints
--   VehicleArrivalVehicle.create  -> our vehicle script per car, car tagged with the caravan id
--   DrivingLifecycle.create       -> convoy cruising speed
--   VehicleArrivals.fallback/finished -> no "walk to the objective after five minutes"
-- Re-crewing (a dead driver, crews back into the cars after a fight) creates a
-- boarding session the same way A-Life does for its own crews: directly on the
-- driving side in single player, suspended with a hand-off in multiplayer.

require "ALifeCaravans/00_ALC_Core"
require "ALifeCaravans/02_ALC_Vehicles"
require "ALifeCaravans/03_ALC_Roads"
require "ALifeCaravans/04_ALC_Convoy"
require "ALifeCaravans/ALC_Arrival"

local A = ALifeCaravans
local S = { pending = nil, installed = false, serial = 0, lastReason = nil, recrewSerial = 0 }
A.Spawn = S

local function P() return ProjectALife end

function S.caravanFor(tag)
    return A.Ledger ~= nil and A.Ledger.get(tag) or nil
end

function S.install()
    if S.installed then return true end
    local p = P()
    if p == nil or p.VehicleArrivalSites == nil or p.VehicleArrivalVehicle == nil or p.VehicleArrivals == nil
            or p.DrivingLifecycle == nil then
        return false
    end
    S.installed = true
    A.wrap(p.VehicleArrivalSites, "find", function(original)
        return function(scene, target)
            local pending = S.pending
            if pending ~= nil then
                pending.siteIndex = (pending.siteIndex or 0) + 1
                local site = pending.sites[pending.siteIndex]
                if site ~= nil then
                    local copy = { x = site.x, y = site.y, z = 0, route = {} }
                    for _, point in ipairs(site.route) do copy.route[#copy.route + 1] = { x = point.x, y = point.y } end
                    return copy
                end
                return nil, "caravan has no site for another car"
            end
            return original(scene, target)
        end
    end, "VehicleArrivalSites.find")
    A.wrap(p.VehicleArrivalVehicle, "create", function(original)
        return function(site, requestId)
            local pending = S.pending
            if pending == nil then return original(site, requestId) end
            local V = p.VehicleArrivalVehicle
            local previous = V.script
            pending.carIndex = (pending.carIndex or 0) + 1
            local script = pending.scripts[pending.carIndex] or pending.scripts[#pending.scripts]
            if script ~= nil then V.script = script end
            local called, car, seats
            if type(addVehicleDebug)=="function" then
                called, car, seats=pcall(A.Arrival.create,V.script,site,requestId)
            else
                called, car, seats=pcall(original,site,requestId)
            end
            V.script = previous
            if not called then error(car) end
            if car ~= nil then
                -- A-Life fills a car before it creates the next one; handing back
                -- fewer usable seats spreads the crew over the convoy's cars.
                local wanted = pending.perCar and pending.perCar[pending.carIndex] or nil
                if type(seats) == "table" and wanted ~= nil and #seats > wanted then
                    local trimmed = {}
                    for index = 1, math.max(1, wanted) do trimmed[index] = seats[index] end
                    seats = trimmed
                end
                A.tagVehicle(car, pending.caravan.id, (pending.indexBase or 0) + pending.carIndex)
                local ok, id = pcall(function() return car:getId() end)
                if ok then pending.cars[#pending.cars + 1] = id end
                pcall(function() car:setHeadlightsOn(p.VehicleArrivalVehicle.night()) end)
            else
                S.lastReason = seats
            end
            return car, seats
        end
    end, "VehicleArrivalVehicle.create")
    A.wrap(p.DrivingLifecycle, "create", function(original)
        return function(owner, old, car, crew, token, route, boarding)
            local tag = A.vehicleTag(car)
            local caravan = tag ~= nil and S.caravanFor(tag) or nil
            if caravan ~= nil and type(old) == "table" then
                local kmh = tonumber(caravan.speedKmh) or A.settings.cruiseKmh
                local T = p.DrivingTuning
                if T ~= nil and type(T.copy) == "function" then
                    local tuning = T.copy(old.tuning)
                    tuning.speedKmh = kmh
                    old.tuning = tuning
                end
                old.speedKmh = kmh
                old.cruiseSpeed = kmh / 3.6
                old.systemArrival = true
            end
            return original(owner, old, car, crew, token, route, boarding)
        end
    end, "DrivingLifecycle.create")
    A.wrap(p.VehicleArrivals, "fallback", function(original)
        return function(owner, id, s, now)
            local car = type(getVehicleById) == "function" and getVehicleById(id) or nil
            if car ~= nil and A.vehicleTag(car) ~= nil then return end
            return original(owner, id, s, now)
        end
    end, "VehicleArrivals.fallback")
    A.wrap(p.VehicleArrivals, "finished", function(original)
        return function(owner, s)
            local car = s and s.vehicle or nil
            local tag = car ~= nil and A.vehicleTag(car) or nil
            if tag ~= nil then
                local ok, id = pcall(function() return car:getId() end)
                local journey = ok and p.VehicleArrivals.journeys[id] or nil
                local x, y = A.xyz(car)
                if journey ~= nil and x ~= nil then
                    journey.followPlayer = false
                    journey.target = { x = x, y = y, z = 0 }
                end
                local result = original(owner, s)
                if A.Director ~= nil and type(A.Director.onSessionFinished) == "function" then
                    pcall(A.Director.onSessionFinished, tag, ok and id or nil, s.finishReason or s.stopReason)
                end
                return result
            end
            return original(owner, s)
        end
    end, "VehicleArrivals.finished")
    return true
end

function S.ready()
    local p = P()
    if p == nil or p.DebugService == nil or type(p.DebugService.rawSpawn) ~= "function" then return false, "no_spawn_service" end
    if p.VehicleArrivals == nil or type(p.VehicleArrivals.enabled) ~= "function" then return false, "no_vehicle_arrivals" end
    local ok, enabled = pcall(p.VehicleArrivals.enabled)
    if not ok or not enabled then return false, "vehicle_arrivals_disabled" end
    if p.Runtime ~= nil and p.Runtime.started == false then return false, "runtime_not_started" end
    return true
end

local function playersXY(players)
    local out = {}
    for _, player in ipairs(players or {}) do
        local x, y = A.xyz(player)
        if x ~= nil then out[#out + 1] = { x = x, y = y } end
    end
    return out
end

-- Scripts and crew of a render unit (1: cars 1-2, 2: cars 3-4). The crew is
-- shared between the units in proportion to their seats, at least a driver per car.
function S.unitPlan(caravan, unit)
    local scripts, crew = {}, {}
    local all = {}
    for _, name in ipairs(caravan.vehicles or {}) do
        if A.Vehicles.valid(name) then all[#all + 1] = name end
    end
    local first = unit == 2 and 3 or 1
    for index = first, math.min(#all, first + 1) do scripts[#scripts + 1] = all[index] end
    local unitSeats, totalSeats, unit1Seats = 0, 0, 0
    for index, name in ipairs(all) do
        local n = A.Vehicles.seats(name)
        totalSeats = totalSeats + n
        if index <= 2 then unit1Seats = unit1Seats + n end
    end
    for _, name in ipairs(scripts) do unitSeats = unitSeats + A.Vehicles.seats(name) end
    local total = #(caravan.crew or {})
    local unit1Cars = math.min(2, #all)
    local unit1Crew = total
    if #all > 2 then
        unit1Crew = math.floor(total * unit1Seats / math.max(1, totalSeats))
        unit1Crew = math.max(unit1Cars, math.min(unit1Crew, total - (#all - unit1Cars), unit1Seats, 8))
    end
    local from, to
    if unit == 1 then from, to = 1, unit1Crew else from, to = unit1Crew + 1, total end
    for index = from, math.min(to, total) do
        if #crew < math.min(8, unitSeats) then crew[#crew + 1] = caravan.crew[index] end
    end
    -- crew per car inside the unit: half and half, at least a driver each
    local perCar = {}
    if #scripts >= 2 and #crew >= 2 then
        local seats1, seats2 = A.Vehicles.seats(scripts[1]), A.Vehicles.seats(scripts[2])
        local c1 = math.min(seats1, math.ceil(#crew / 2))
        local c2 = math.min(seats2, #crew - c1)
        if c2 < 1 then c1, c2 = #crew - 1, 1 end
        while #crew > c1 + c2 do table.remove(crew) end
        perCar = { c1, c2 }
    elseif #scripts >= 1 then
        local seats1 = A.Vehicles.seats(scripts[1])
        while #crew > seats1 do table.remove(crew) end
        perCar = { #crew }
    end
    return scripts, crew, unitSeats, perCar
end

-- Try to put a render unit of the caravan on the road. Unit 1 starts near the
-- ledger position; unit 2 starts behind the last car of unit 1. Returns true
-- when A-Life accepted the crew request (the outcome arrives through watchGroup).
function S.render(caravan, player, players, unit)
    unit = unit or 1
    local p = P()
    local ok, reason = S.ready()
    if not ok then return false, reason end
    if not S.installed and not S.install() then return false, "hooks_not_installed" end
    local scripts, crew, _, perCar = S.unitPlan(caravan, unit)
    if #scripts == 0 then
        if unit == 2 then return false, "no_unit_2" end
        local name = A.Vehicles.pick(caravan.class or "civilian", A.randFloat())
        if name == nil then return false, "no_vehicle_script" end
        caravan.vehicles = { name }
        scripts, crew, _, perCar = S.unitPlan(caravan, unit)
    end
    if #crew == 0 then return false, "no_crew" end
    local scene = A.Roads.scene(player)
    local people = playersXY(players)
    local sites, points
    if unit == 1 then
        local goal = caravan.goals and caravan.goals[caravan.goalIndex or 1] or nil
        if goal == nil then return false, "no_goal" end
        local site, why = A.Roads.siteNear(scene, caravan.x, caravan.y, people, { radius = 36, minPlayer = A.settings.minSpawnDistance })
        if site == nil then return false, why end
        local info
        points, info = A.Roads.scout(scene, site, goal, { maxPoints = 10 })
        if #points == 0 then return false, info.reason or "no_road" end
        sites = { { x = site.x, y = site.y, z = 0, route = points } }
        if #scripts > 1 then
            local behind = A.Roads.behind(scene, site, points[1], 9, people, A.settings.minSpawnDistance)
            if behind ~= nil then
                local route = { { x = site.x, y = site.y } }
                for _, point in ipairs(points) do route[#route + 1] = { x = point.x, y = point.y } end
                sites[2] = { x = behind.x, y = behind.y, z = 0, route = route }
            else
                scripts = { scripts[1] }
            end
        end
        caravan.legPoints = points
        caravan.leadSite = { x = site.x, y = site.y }
    else
        local tailId = caravan.vehicleIds[#caravan.vehicleIds]
        local tail = tailId ~= nil and getVehicleById(tailId) or nil
        local tx, ty = A.xyz(tail)
        if tx == nil then return false, "no_tail_car" end
        local ahead = caravan.legPoints and caravan.legPoints[1] or caravan.leadSite or { x = tx + 1, y = ty }
        local tailSite = { x = math.floor(tx) + 0.5, y = math.floor(ty) + 0.5 }
        local first = A.Roads.behind(scene, tailSite, ahead, 10, people, 0)
        if first == nil then return false, "no_room_behind" end
        local route = {}
        for _, point in ipairs(caravan.legPoints or {}) do route[#route + 1] = { x = point.x, y = point.y } end
        if #route == 0 then route[1] = { x = ahead.x, y = ahead.y } end
        sites = { { x = first.x, y = first.y, z = 0, route = route } }
        if #scripts > 1 then
            local second = A.Roads.behind(scene, first, tailSite, 9, people, 0)
            if second ~= nil then
                local route2 = { { x = first.x, y = first.y } }
                for _, point in ipairs(route) do route2[#route2 + 1] = { x = point.x, y = point.y } end
                sites[2] = { x = second.x, y = second.y, z = 0, route = route2 }
            else
                scripts = { scripts[1] }
            end
        end
        points = sites[1].route
    end
    local seatsNow = 0
    for _, name in ipairs(scripts) do seatsNow = seatsNow + A.Vehicles.seats(name) end
    local limit = math.max(1, math.min(8, seatsNow - (caravan.renderFailures or 0)))
    while #crew > limit do table.remove(crew) end
    if #scripts == 1 then perCar = { #crew } end
    local last = points[#points]
    S.serial = S.serial + 1
    local requestId = "alc:" .. tostring(caravan.id) .. ":" .. tostring(S.serial)
    local args = {
        requestId = requestId,
        profileIds = crew,
        count = #crew,
        factionId = caravan.factionId,
        x = sites[1].x, y = sites[1].y, z = 0,
        mode = "patrol", radius = 12, distance = 0, separation = 1,
        arrival = "ground",
        objectiveX = last.x, objectiveY = last.y,
        atomicGroup = true,
        encounterId = "alc_caravan",
        encounterPersistent = false,
        supportPolicy = "disabled",
        playerKeepOut = 0,
        spawnDelayMs = 0,
        animation = "normal",
        conducts = { "leader" },
    }
    S.pending = { caravan = caravan, sites = sites, scripts = scripts, cars = {}, perCar = perCar, indexBase = unit == 2 and #caravan.vehicleIds or 0 }
    local okCall, result = pcall(p.DebugService.rawSpawn, player, args, true)
    local pending = S.pending
    S.pending = nil
    if not okCall then
        S.teardownVehicles(pending.cars, caravan.id)
        return false, "spawn_error:" .. tostring(result)
    end
    if type(result) ~= "table" or result.ok ~= true then
        S.teardownVehicles(pending.cars, caravan.id)
        local why = type(result) == "table" and result.reason or tostring(result)
        return false, tostring(why or "spawn_refused") .. (S.lastReason and (" (" .. tostring(S.lastReason) .. ")") or "")
    end
    caravan.requestId = requestId
    caravan.vehicleIds = caravan.vehicleIds or {}
    if unit == 1 then caravan.vehicleIds = {} end
    for _, id in ipairs(pending.cars) do caravan.vehicleIds[#caravan.vehicleIds + 1] = id end
    caravan.site = { x = sites[1].x, y = sites[1].y }
    if type(p.DebugService.watchGroup) == "function" then
        p.DebugService.watchGroup(requestId, function(outcome)
            if A.Director ~= nil and type(A.Director.onSpawnOutcome) == "function" then
                local okOutcome, err = pcall(A.Director.onSpawnOutcome, caravan.id, outcome, unit)
                if not okOutcome then A.fail("spawn outcome", err) end
            end
        end)
    end
    return true
end

-- Driving owner (A-Life's) and the session of a car, wherever it is kept.
function S.sessionOf(vehicleId)
    local p = P()
    if p == nil or p.VehicleArrivals == nil then return nil end
    local owner = p.VehicleArrivals.owner()
    if owner == nil then return nil end
    local s = owner.sessions and owner.sessions[vehicleId] or nil
    if s ~= nil then return owner, s, nil end
    local record = owner.sleeping and owner.sleeping[vehicleId] or nil
    if record ~= nil then return owner, record.restored or record.session, record end
    return owner, nil, nil
end

-- Release one car from A-Life's driving bookkeeping (mirrors VehicleArrivals.cancel).
function S.releaseCar(vehicleId, caravanId)
    local p = P()
    local owner, s, record = S.sessionOf(vehicleId)
    local car = type(getVehicleById)=="function" and getVehicleById(vehicleId) or nil
    if type(caravanId) ~= "string" then return false end
    -- IDs are transient. Prove ownership before releasing another mod's crew,
    -- native adapter or binding, including an unloaded car's saved session body.
    local proof = car or (s and s.vehicle)
    if proof == nil or A.vehicleTag(proof) ~= caravanId then return false end
    if s and s.vehicle and A.vehicleTag(s.vehicle) ~= caravanId then return false end
    if record then
        for _, previous in pairs({record.session, record.restored}) do
            if previous and previous.vehicle and A.vehicleTag(previous.vehicle) ~= caravanId then return false end
        end
    end
    if car and A.Physics.releaseSP then A.Physics.releaseSP(car) end
    if owner == nil then return true end
    local D, L = p.DrivingDemo, p.DrivingLifecycle
    pcall(function()
        if s ~= nil and D ~= nil then D.release(s) end
        if record ~= nil then
            if record.restored and record.restored ~= s then D.release(record.restored) end
            if record.session and record.session ~= s then D.release(record.session) end
        end
        if s ~= nil and L ~= nil and type(L.forget) == "function" then L.forget(s) end
    end)
    if owner.sessions then owner.sessions[vehicleId] = nil end
    if owner.sleeping then owner.sleeping[vehicleId] = nil end
    if owner.bindings then owner.bindings[vehicleId] = nil end
    if owner.tunings then owner.tunings[vehicleId] = nil end
    if owner.allowRiders then owner.allowRiders[vehicleId] = nil end
    if owner.carModes then owner.carModes[vehicleId] = nil end
    if owner.departures then owner.departures[vehicleId] = nil end
    if owner.active == s then owner.active = nil end
    p.VehicleArrivals.active[vehicleId] = nil
    p.VehicleArrivals.journeys[vehicleId] = nil
    return true
end

function S.teardownVehicles(ids, caravanId)
    local p = P()
    for _, id in ipairs(ids or {}) do
        local car = type(getVehicleById) == "function" and getVehicleById(id) or nil
        if car ~= nil and A.vehicleTag(car) == caravanId and p ~= nil and p.VehicleArrivalVehicle ~= nil and not A.vehicleHasPlayer(car) then
            if S.releaseCar(id, caravanId) then
                local ok, removed = pcall(p.VehicleArrivalVehicle.remove, car)
                if not ok then A.fail("vehicle remove", removed) end
            end
        end
    end
end

function S.teardownActors(uids, reason)
    local p = P()
    local registry = p and p.ActorRegistry
    local spawn = p and p.SpawnService
    for _, uid in ipairs(uids or {}) do
        if spawn ~= nil and type(spawn.dehydrate) == "function" then pcall(spawn.dehydrate, uid, reason) end
        if registry ~= nil then
            local ok, actor = pcall(registry.read, uid)
            if ok and actor ~= nil and actor.lifecycle ~= "active" then
                pcall(registry.remove, uid, actor.revision, reason)
            end
        end
    end
end

-- Take a caravan off the road: crew back into the ledger, cars gone. A car with
-- a player inside stays in the world (returned in `kept`); abandoned cars stay.
function S.teardown(caravan, reason)
    local kept = {}
    -- A passenger's convoy is still real gameplay, not disposable scenery.
    for _, id in ipairs(caravan.vehicleIds or {}) do
        local car = getVehicleById(id)
        if car and A.vehicleTag(car) == caravan.id and A.vehicleHasPlayer(car) then return {id}, "player_aboard" end
    end
    S.teardownActors(caravan.actorUids, reason or "alc_release")
    local p = P()
    for _, id in ipairs(caravan.vehicleIds or {}) do
        local released = S.releaseCar(id, caravan.id)
        local car = type(getVehicleById) == "function" and getVehicleById(id) or nil
        if car ~= nil and A.vehicleTag(car) == caravan.id and p ~= nil and p.VehicleArrivalVehicle ~= nil then
            if not released or A.vehicleHasPlayer(car) then
                kept[#kept + 1] = id
            else
                local ok, removed = pcall(p.VehicleArrivalVehicle.remove, car)
                if not ok or removed == false then kept[#kept + 1] = id end
            end
        end
    end
    for _, id in ipairs(caravan.abandoned or {}) do S.releaseCar(id, caravan.id) end
    caravan.actorUids = {}
    caravan.vehicleIds = {}
    caravan.abandoned = {}
    caravan.requestId = nil
    return kept
end

-- The crew leaves the cars and goes to `objective` on foot (fight or flee).
function S.dismount(caravan, objective)
    local p = P()
    local client = p and p.DrivingDemoClient
    for _, id in ipairs(caravan.vehicleIds or {}) do
        local owner, s = S.sessionOf(id)
        if s ~= nil then
            if type(isServer) == "function" and isServer() then
                if owner ~= nil and type(owner.send) == "function" and s.player ~= nil then
                    pcall(owner.send, s.player, "arrivalWalk", { token = s.token, trip = s.trip or 0 })
                end
            elseif client ~= nil and type(client.arrivalWalk) == "function" then
                pcall(client.arrivalWalk, s)
            end
        end
    end
    local registry = p and p.ActorRegistry
    if registry ~= nil and objective ~= nil then
        for _, uid in ipairs(caravan.actorUids or {}) do
            local ok, actor = pcall(registry.read, uid)
            if ok and actor ~= nil and actor.lifecycle ~= "dead" then
                pcall(registry.updateTransient, uid, actor.revision, function(record)
                    record.memory.arrivalObjective = { x = objective.x, y = objective.y, z = 0, untilMs = A.now() + 300000 }
                end)
            end
        end
    end
end

-- Let players use the free seats (hitch a ride) or not.
function S.setRiders(caravan, allowed)
    local p = P()
    for _, id in ipairs(caravan.vehicleIds or {}) do
        local owner = S.sessionOf(id)
        if owner ~= nil then
            owner.allowRiders = owner.allowRiders or {}
            owner.carModes = owner.carModes or {}
            owner.allowRiders[id] = allowed == true
            owner.carModes[id] = allowed and "mixed" or "npc"
        end
        if p ~= nil and p.DrivingMultiplayer ~= nil then p.DrivingMultiplayer.broadcastAt = 0 end
    end
end

-- Living crew of the caravan with a body near (x, y), as { uid, generation, shell } rows.
function S.survivors(caravan, x, y, radius)
    local p = P()
    local registry = p and p.ActorRegistry
    local demo = p and p.DrivingDemo
    local out = {}
    if registry == nil or demo == nil then return out end
    for _, uid in ipairs(caravan.actorUids or {}) do
        local ok, actor = pcall(registry.read, uid)
        if ok and actor ~= nil and actor.lifecycle == "active" then
            local okNpc, npc = pcall(demo.findNpc, uid, actor.generation)
            local nx, ny
            if okNpc then nx, ny = A.xyz(npc) end
            local dead = true
            pcall(function() dead = npc:isDead() end)
            if nx ~= nil and not dead and A.dist(nx, ny, x, y) <= (radius or 40) then
                out[#out + 1] = { uid = uid, generation = actor.generation, npc = npc, inCar = nil }
                pcall(function() out[#out].inCar = npc:getVehicle() end)
            end
        end
    end
    return out
end

-- DrivingCrewHome restores a binding and mixed-seat permission, but no session.
-- Only that parked, owned case may reconnect NPCs around an existing passenger.
function S.canRestoreRiders(caravan, vehicleId)
    local car = type(getVehicleById) == "function" and getVehicleById(vehicleId) or nil
    if not car or type(caravan.id) ~= "string" or A.vehicleTag(car) ~= caravan.id then return false end
    local owner, session, sleeping = S.sessionOf(vehicleId)
    local binding = owner and owner.bindings and owner.bindings[vehicleId]
    if session or sleeping or not binding or binding.restoredCrew ~= true then return false end
    if not (owner.allowRiders and owner.allowRiders[vehicleId] == true
            and owner.carModes and owner.carModes[vehicleId] == "mixed") then return false end
    if (owner.departures and owner.departures[vehicleId]) or (owner.pending and owner.pending[vehicleId]) then return false end
    local safe, parked = pcall(function()
        local speed = car:getCurrentSpeedKmHour()
        return type(speed) == "number" and speed == speed and math.abs(speed) <= 0.18
            and getCell():getGridSquare(math.floor(car:getX()), math.floor(car:getY()), math.floor(car:getZ())) ~= nil
            and not instanceof(car:getCharacter(0), "IsoPlayer")
    end)
    if not safe or not parked then return false end
    local owned, bound, available, bodies = {}, {}, false, {}
    for _, uid in ipairs(caravan.actorUids or {}) do owned[uid] = true end
    for _, spec in ipairs(binding.crew or {}) do
        if not owned[spec.uid] then return false end
        bound[spec.uid] = true
    end
    local x, y = A.xyz(car)
    for _, member in ipairs(S.survivors(caravan, x, y, 100)) do
        if member.inCar == nil or member.inCar == car then
            bodies[member.npc] = true
            if bound[member.uid] then available = true end
        end
    end
    if not available then return false end
    local passenger = false
    safe = pcall(function()
        for seat = 0, car:getMaxPassengers() - 1 do
            local occupant = car:getCharacter(seat)
            if occupant then
                if instanceof(occupant, "IsoPlayer") then passenger = seat > 0 or passenger
                elseif not bodies[occupant] then error("unowned occupant") end
            end
        end
    end)
    return safe and passenger
end

-- Put a crew back into a car: the survivors walk to the car, board it (a new
-- driver on seat 0) and drive the caravan's route on. `limit` caps additional
-- on-foot survivors; already seated crew do not consume this shared quota.
-- Returns true when the boarding session was created.
function S.recrew(caravan, vehicleId, route, limit, reserved)
    local p = P()
    local car = type(getVehicleById) == "function" and getVehicleById(vehicleId) or nil
    if car == nil or p == nil or p.DrivingLifecycle == nil or p.DrivingTuning == nil then return false, "no_car" end
    if A.vehicleTag(car) ~= caravan.id or type(caravan.id) ~= "string" then return false, "foreign_car" end
    local restoredRiders = A.vehicleHasPlayer(car)
    if restoredRiders and not S.canRestoreRiders(caravan, vehicleId) then return false, "player_aboard" end
    local cx, cy = A.xyz(car)
    if cx == nil then return false, "no_position" end
    local candidates = S.survivors(caravan, cx, cy, 100)
    -- crew already seated in another caravan car stays there
    local free = {}
    for _, row in ipairs(candidates) do
        local other = row.inCar
        if other == car or (other == nil and not (reserved and reserved[row.uid])) then free[#free + 1] = row end
    end
    if #free == 0 then return false, "no_survivors" end
    local seats, crew, assigned = {}, {}, {}
    local seatsOK = pcall(function()
        for seat = 0, math.min(15, car:getMaxPassengers() - 1) do
            if car:isSeatInstalled(seat) then
                local occupant = car:getCharacter(seat)
                if occupant == nil then seats[#seats + 1] = seat
                else
                    for _, row in ipairs(free) do
                        if row.inCar == car and row.npc == occupant then
                            crew[#crew + 1] = { uid = row.uid, generation = row.generation, seat = seat, boarded = true }
                            assigned[row.uid] = true
                            break
                        end
                    end
                end
            end
        end
    end)
    if not seatsOK then return false, "seat_query_failed" end
    -- limit is a quota of ON-FOOT survivors, not total crew. Keep seated
    -- identities in their real seats; never replace a player or unrelated NPC.
    local cap = math.max(0, math.min(#seats, math.floor(tonumber(limit) or #seats)))
    local added = 0
    for _, row in ipairs(free) do
        if added < cap and row.inCar == nil and not assigned[row.uid] then
            added = added + 1
            crew[#crew + 1] = { uid = row.uid, generation = row.generation, seat = seats[added] }
            assigned[row.uid] = true
        end
    end
    table.sort(crew, function(a, b) return a.seat < b.seat end)
    if crew[1] == nil or crew[1].seat ~= 0 then return false, "no_driver_seat" end
    local owner = p.VehicleArrivals.owner()
    if owner == nil then return false, "no_owner" end
    local player = A.players()[1]
    if type(getSpecificPlayer) == "function" and not (type(isServer) == "function" and isServer()) then
        local ok, local0 = pcall(getSpecificPlayer, 0)
        if ok and local0 ~= nil then player = local0 end
    elseif #A.players() > 1 then
        local best, bestD = player, math.huge
        for _, candidate in ipairs(A.players()) do
            local px, py = A.xyz(candidate)
            local d = px and A.dist(px, py, cx, cy) or math.huge
            if d < bestD then best, bestD = candidate, d end
        end
        player = best
    end
    if player == nil then return false, "no_player" end
    local points = {}
    if route then
        for _, point in ipairs(route) do points[#points+1]={x=point.x,y=point.y} end
    else
        -- Re-scout from the parked car, not the original spawn's old route.
        local entry = A.Convoy.entry(vehicleId) or {goals=caravan.goals,goalIndex=caravan.goalIndex or 1}
        local leg, reason = A.Convoy.legFor(entry,{vehicle=car,route={}},true)
        if leg then points=leg end
        if reason == "arrived" and #(entry.goals or {}) > 0 and A.Director then
            A.Director.onConvoyReport(nil,"arrived",{vehicleId=vehicleId})
            return false,"at_destination"
        end
        -- Legacy/testing caravans without goals may supply an explicit leg.
        if #points==0 and #(caravan.goals or {})==0 then
            for _, point in ipairs(caravan.legPoints or {}) do points[#points+1]={x=point.x,y=point.y} end
        end
    end
    if #points == 0 then return false, "no_route" end
    -- Arrival grants a key only to its original driver. A surviving passenger
    -- promoted after combat needs the same persistent, idempotent A-Life grant.
    -- Revalidate the selected real body/registry generation before any release.
    local driverSpec, owned, driverBody = crew[1], false, nil
    for _, uid in ipairs(caravan.actorUids or {}) do if uid == driverSpec.uid then owned = true break end end
    for _, row in ipairs(free) do
        if row.uid == driverSpec.uid and row.generation == driverSpec.generation then driverBody = row.npc break end
    end
    local valid, driverActor, npc = pcall(function()
        local actor = p.ActorRegistry and p.ActorRegistry.read(driverSpec.uid)
        if not owned or not actor or actor.uid ~= driverSpec.uid or actor.lifecycle ~= "active"
                or actor.generation ~= driverSpec.generation then return end
        local body = p.DrivingDemo.findNpc(driverSpec.uid, driverSpec.generation)
        if not body or body ~= driverBody or body:isDead() then return end
        return actor, body
    end)
    if not valid or not driverActor or not npc then return false, "driver_changed" end
    local keys = p.VehicleArrivalKeys
    if not keys or type(keys.grant) ~= "function" then return false, "driver_key_service_unavailable" end
    local keyOK, granted, keyReason = pcall(keys.grant, car, npc, driverActor)
    if not keyOK or granted ~= true then
        return false, "driver_key_failed:" .. tostring(keyOK and keyReason or granted)
    end
    -- Do all fallible planning before releasing the old session.
    if not S.releaseCar(vehicleId, caravan.id) then return false, "foreign_session" end
    owner.bindings = owner.bindings or {}
    local registry = p.ActorRegistry
    for _, member in ipairs(crew) do
        if registry and type(registry.updateTransient)=="function" then
            local readOK, actor=pcall(registry.read,member.uid)
            if readOK and actor then pcall(registry.updateTransient,member.uid,actor.revision,function(record)
                record.memory = record.memory or {}
                record.memory.arrivalObjective=nil
            end) end
        end
    end
    local T = p.DrivingTuning
    local tuning = T.copy()
    tuning.speedKmh = caravan.speedKmh
    S.recrewSerial = S.recrewSerial + 1
    local token = "alc-recrew:" .. tostring(vehicleId) .. ":" .. tostring(S.recrewSerial)
    local old = { player = player, systemArrival = true, tuning = tuning, speedKmh = caravan.speedKmh, cruiseSpeed = caravan.speedKmh / 3.6,
        route = points, boardingDepart = true, onWaypointReached = not (type(isServer) == "function" and isServer()) and owner.waypointReached or nil }
    local binding = { vehicleId = vehicleId, player = player, crew = crew, revision = ((owner.bindings[vehicleId] and owner.bindings[vehicleId].revision) or 0) + 1,
        status = "Caravan crew boarding.", restoredCrew = restoredRiders or nil }
    owner.bindings[vehicleId] = binding
    if type(p.DrivingFleet.rememberVehicle) == "function" then pcall(p.DrivingFleet.rememberVehicle, binding, car) end
    owner.tunings = owner.tunings or {}
    owner.allowRiders = owner.allowRiders or {}
    owner.carModes = owner.carModes or {}
    owner.tunings[vehicleId] = tuning
    owner.allowRiders[vehicleId] = restoredRiders == true
    owner.carModes[vehicleId] = restoredRiders and "mixed" or "npc"
    p.VehicleArrivals.active[vehicleId] = car
    p.VehicleArrivals.journeys[vehicleId] = { deadline = A.now() + 86400000, player = player, target = { x = points[#points].x, y = points[#points].y } }
    local ok, s, why = pcall(p.DrivingLifecycle.create, owner, old, car, crew, token, points, true)
    if not ok then return false, "create_error:" .. tostring(s) end
    if s == nil then return false, tostring(why or "create_refused") end
    if type(isServer) == "function" and isServer() then
        local L = p.DrivingLifecycle
        local record = L.suspend(owner, s, false)
        if record == nil then
            S.releaseCar(vehicleId, caravan.id)
            if restoredRiders then
                owner.bindings[vehicleId] = binding
                owner.allowRiders[vehicleId], owner.carModes[vehicleId] = true, "mixed"
            end
            return false, "suspend_refused"
        end
        record.resume, record.handoff = true, true
    else
        owner.departures = owner.departures or {}
        owner.departures[vehicleId] = { revision = binding.revision, options = { route = points, speedKmh = caravan.speedKmh } }
    end
    if p.DrivingMultiplayer ~= nil then p.DrivingMultiplayer.broadcastAt = 0 end
    A.metrics.recrews = A.metrics.recrews + 1
    if reserved then for _, member in ipairs(crew) do reserved[member.uid] = true end end
    return true, #crew
end

-- Leave a car behind (out of fuel, engine dead, nobody to drive it): its crew
-- gets out and stays with the caravan on foot until the ledger takes them back.
function S.abandon(caravan, vehicleId)
    local p = P()
    local car = type(getVehicleById) == "function" and getVehicleById(vehicleId) or nil
    if car == nil or A.vehicleTag(car) ~= caravan.id or A.vehicleHasPlayer(car) then return false end
    local owner, s = S.sessionOf(vehicleId)
    if not S.releaseCar(vehicleId, caravan.id) then return false end
    for index = #(caravan.vehicleIds or {}), 1, -1 do
        if caravan.vehicleIds[index] == vehicleId then table.remove(caravan.vehicleIds, index) end
    end
    caravan.abandoned = caravan.abandoned or {}
    caravan.abandoned[#caravan.abandoned + 1] = vehicleId
    A.metrics.abandoned = A.metrics.abandoned + 1
    pcall(function()
        local car = getVehicleById(vehicleId)
        if car ~= nil then
            car:setHeadlightsOn(false)
            if car:isEngineRunning() and car:getDriver() == nil then car:shutOff() end
        end
    end)
    return true
end

-- Fuel and engine of a car, for the abandonment rule.
function S.carHealth(car)
    local fuel, engine = 1, true
    pcall(function()
        local tank = car:getPartById("GasTank")
        if tank ~= nil then fuel = tank:getContainerContentAmount() end
    end)
    pcall(function() engine = car:isEngineWorking() end)
    return fuel, engine
end

-- Zombies (not A-Life NPCs) within `radius` of (x, y).
function S.zombiesNear(x, y, radius)
    local count = 0
    pcall(function()
        local list = getCell():getZombieList()
        for index = 0, list:size() - 1 do
            local zombie = list:get(index)
            local zx, zy = A.xyz(zombie)
            if zx ~= nil and not zombie:isDead() and A.dist(zx, zy, x, y) <= radius then
                local data = zombie:getModData()
                if not (data and data.ProjectALifeOwned == true) then count = count + 1 end
            end
        end
    end)
    return count
end

-- An ambush ahead of the convoy: a horde on the road, or raiders of an outlaw faction.
function S.ambush(caravan, kind, x, y, player)
    local p = P()
    if kind == "raiders" then
        local rules = p and p.FactionSpawnRules
        local catalog = p and p.Catalog and p.Catalog.current
        local outlaw
        for _, faction in ipairs(catalog and catalog.factionOrder or {}) do
            if rules ~= nil and type(rules.outlaw) == "function" and rules.outlaw(faction) and faction.id ~= caravan.factionId
                    and faction.spawn ~= nil and faction.spawn.enabled ~= false then
                outlaw = faction
                if A.rand(3) == 0 then break end
            end
        end
        if outlaw == nil or p.DebugService == nil then return false, "no_outlaw_faction" end
        S.serial = S.serial + 1
        local ok, result = pcall(p.DebugService.rawSpawn, player, {
            requestId = "alc-ambush:" .. tostring(caravan.id) .. ":" .. tostring(S.serial),
            factionId = outlaw.id, count = 3 + A.rand(2), x = x, y = y, z = 0,
            mode = "assault", radius = 10, distance = 0, separation = 2, atomicGroup = false,
            encounterId = "alc_ambush", encounterPersistent = false, supportPolicy = "disabled", playerKeepOut = 0,
            objectiveX = caravan.x, objectiveY = caravan.y, animation = "normal",
        }, true)
        if not ok or type(result) ~= "table" or result.ok ~= true then
            return false, tostring(ok and (result and result.reason) or result)
        end
        return true
    end
    local count = 8 + A.rand(7)
    local ok, err = pcall(function() spawnHorde(x - 4, y - 4, x + 4, y + 4, 0, count) end)
    if not ok then return false, tostring(err) end
    return true
end

return S
