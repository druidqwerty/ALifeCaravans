-- A-Life: Caravans - materialising a caravan (server / single player).
-- A caravan near a player becomes real through A-Life's own "arrive by car"
-- pipeline (DebugService.rawSpawn with arrival="ground" -> VehicleArrivals):
-- A-Life creates the cars, spawns the crew straight into the seats, hands the
-- car to a driving session (and, in multiplayer, to the nearest client). Four
-- small hooks make that pipeline ours while one of our requests is in flight:
--   VehicleArrivalSites.find      -> our road site on the caravan's route and our waypoints
--   VehicleArrivalVehicle.create  -> our vehicle script per car, car tagged with the caravan id
--   DrivingLifecycle.create       -> convoy cruising speed
--   VehicleArrivals.fallback/finished -> no "walk to the objective after five minutes"

require "ALifeCaravans/00_ALC_Core"
require "ALifeCaravans/02_ALC_Vehicles"
require "ALifeCaravans/03_ALC_Roads"
require "ALifeCaravans/04_ALC_Convoy"

local A = ALifeCaravans
local S = { pending = nil, installed = false, serial = 0, lastReason = nil }
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
            local car, seats = original(site, requestId)
            V.script = previous
            if car ~= nil then
                A.tagVehicle(car, pending.caravan.id, pending.carIndex)
                local ok, id = pcall(function() return car:getId() end)
                if ok then pending.cars[#pending.cars + 1] = id end
                pcall(function()
                    car:setHeadlightsOn(p.VehicleArrivalVehicle.night())
                end)
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

-- Try to put the caravan on the road near its ledger position. Returns true
-- when A-Life accepted the crew request (the outcome arrives through watchGroup).
function S.render(caravan, player, players)
    local p = P()
    local ok, reason = S.ready()
    if not ok then return false, reason end
    if not S.installed and not S.install() then return false, "hooks_not_installed" end
    local scene = A.Roads.scene(player)
    local people = playersXY(players)
    local goal = caravan.goals and caravan.goals[caravan.goalIndex or 1] or nil
    if goal == nil then return false, "no_goal" end
    local site, why = A.Roads.siteNear(scene, caravan.x, caravan.y, people, { radius = 36, minPlayer = A.settings.minSpawnDistance })
    if site == nil then return false, why end
    local points, info = A.Roads.scout(scene, site, goal, { maxPoints = 10 })
    if #points == 0 then return false, info.reason or "no_road" end
    local scripts = {}
    for _, name in ipairs(caravan.vehicles or {}) do
        if A.Vehicles.valid(name) then scripts[#scripts + 1] = name end
    end
    if #scripts == 0 then
        local name = A.Vehicles.pick(caravan.vehicleClass or "civilian", A.randFloat())
        if name == nil then return false, "no_vehicle_script" end
        scripts[1] = name
        caravan.vehicles = { name }
    end
    local sites = { { x = site.x, y = site.y, z = 0, route = points } }
    local seats = A.Vehicles.seats(scripts[1])
    if #scripts > 1 then
        local behind = A.Roads.behind(scene, site, points[1], 9, people, A.settings.minSpawnDistance)
        if behind ~= nil then
            local route = { { x = site.x, y = site.y } }
            for _, point in ipairs(points) do route[#route + 1] = { x = point.x, y = point.y } end
            sites[2] = { x = behind.x, y = behind.y, z = 0, route = route }
            seats = seats + A.Vehicles.seats(scripts[2])
        else
            scripts = { scripts[1] }
        end
    end
    local crew = {}
    local limit = math.max(1, math.min(8, seats - (caravan.renderFailures or 0)))
    for index, profileId in ipairs(caravan.crew or {}) do
        if index > limit then break end
        crew[#crew + 1] = profileId
    end
    if #crew == 0 then return false, "no_crew" end
    local last = points[#points]
    S.serial = S.serial + 1
    local requestId = "alc:" .. tostring(caravan.id) .. ":" .. tostring(S.serial)
    local args = {
        requestId = requestId,
        profileIds = crew,
        count = #crew,
        factionId = caravan.factionId,
        x = site.x, y = site.y, z = 0,
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
    S.pending = { caravan = caravan, sites = sites, scripts = scripts, cars = {} }
    local okCall, result = pcall(p.DebugService.rawSpawn, player, args, true)
    local pending = S.pending
    S.pending = nil
    if not okCall then
        S.teardownVehicles(pending.cars)
        return false, "spawn_error:" .. tostring(result)
    end
    if type(result) ~= "table" or result.ok ~= true then
        S.teardownVehicles(pending.cars)
        local why = type(result) == "table" and result.reason or tostring(result)
        return false, tostring(why or "spawn_refused") .. (S.lastReason and (" (" .. tostring(S.lastReason) .. ")") or "")
    end
    caravan.requestId = requestId
    caravan.vehicleIds = pending.cars
    caravan.vehicles = scripts
    caravan.route_points = nil
    caravan.site = { x = site.x, y = site.y }
    if type(p.DebugService.watchGroup) == "function" then
        p.DebugService.watchGroup(requestId, function(outcome)
            if A.Director ~= nil and type(A.Director.onSpawnOutcome) == "function" then
                local okOutcome, err = pcall(A.Director.onSpawnOutcome, caravan.id, outcome)
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
function S.releaseCar(vehicleId)
    local p = P()
    local owner, s, record = S.sessionOf(vehicleId)
    if owner == nil then return end
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
end

function S.teardownVehicles(ids)
    local p = P()
    for _, id in ipairs(ids or {}) do
        S.releaseCar(id)
        local car = type(getVehicleById) == "function" and getVehicleById(id) or nil
        if car ~= nil and p ~= nil and p.VehicleArrivalVehicle ~= nil then
            local ok, removed = pcall(p.VehicleArrivalVehicle.remove, car)
            if not ok then A.fail("vehicle remove", removed) end
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
-- a player inside stays in the world (returned in `kept`).
function S.teardown(caravan, reason)
    local kept = {}
    S.teardownActors(caravan.actorUids, reason or "alc_release")
    local p = P()
    for _, id in ipairs(caravan.vehicleIds or {}) do
        S.releaseCar(id)
        local car = type(getVehicleById) == "function" and getVehicleById(id) or nil
        if car ~= nil and p ~= nil and p.VehicleArrivalVehicle ~= nil then
            local ok, removed = pcall(p.VehicleArrivalVehicle.remove, car)
            if not ok or removed == false then kept[#kept + 1] = id end
        end
    end
    caravan.actorUids = {}
    caravan.vehicleIds = {}
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

return S
