-- A-Life: Caravans - the driving side. A caravan car is an A-Life driving
-- session (ProjectALife.DrivingDemoClient in single player and on the
-- multiplayer client that A-Life hands the car to). This module keeps those
-- sessions moving along the caravan's long route and in formation:
--   * when the queued waypoints run low it scouts the next stretch of loaded
--     road toward the next goal and appends it; a parked car restarts;
--   * followers slow down and stop behind the car ahead, the leader slows for
--     stragglers (regroup), every car parks when the caravan is halted;
--   * a car with no progress skips its waypoint, then re-scouts from where it
--     stands, then reports itself stuck (the director releases the caravan only
--     when no player can see it: nothing teleports in front of players).
-- Which cars are caravans comes from C.known (filled by the director directly
-- in single player, by the "state" server command in multiplayer).

require "ALifeCaravans/00_ALC_Core"
require "ALifeCaravans/01_ALC_Lines"
require "ALifeCaravans/03_ALC_Roads"
require "ALifeCaravans/06_ALC_Physics"

local A = ALifeCaravans
local C = { known = {}, nextTickMs = 0, intervalMs = 300, goalReach = 22, lowQueue = 3, restartDelayMs = 2000,
    tileCache = {}, bodyCache = nil, npcScanCache = nil, scoutedThisTick = false,
    formation = { fullGap = 16, stopGap = 7, regroupGap = 45, regroupDone = 25, regroupFactor = 0.5, crawl = 0.35 },
    stuck = { skipMs = 25000, rescoutMs = 60000, reportMs = 110000, moveTiles = 2.5 } }
A.Convoy = C

function C.owner()
    local server = type(isServer) == "function" and isServer()
    if server then return ProjectALife and ProjectALife.DrivingDemoServer or nil end
    return ProjectALife and ProjectALife.DrivingDemoClient or nil
end

function C.client()
    return ProjectALife and ProjectALife.DrivingDemoClient or nil
end

function C.entry(vehicleId)
    return C.known[vehicleId]
end

-- Replace the known table (server broadcast / director update). Per-car driving
-- state survives; a new trip (goals replaced) resets the goal cursor.
function C.setKnown(entries)
    local fresh = {}
    for id, entry in pairs(entries or {}) do
        local previous = C.known[id]
        if previous ~= nil and previous.caravanId == entry.caravanId and previous.trip == entry.trip then
            entry.goalIndex = math.max(entry.goalIndex or 1, previous.goalIndex or 1)
            entry.arrivedSent = previous.arrivedSent
            entry.parkedAt = previous.parkedAt
            entry.blockedSaidAt = previous.blockedSaidAt
            entry.passedAt = previous.passedAt
            entry.nextScoutAt = previous.nextScoutAt
            entry.stuck = previous.stuck
            entry.regroupSaidAt = previous.regroupSaidAt
            entry.discardRoute = previous.discardRoute
            entry.restartCount = previous.restartCount
        elseif previous ~= nil then
            -- A new destination must not restart the leftover endpoint of the
            -- previous trip (A-Life rejects a waypoint under the parked car).
            entry.discardRoute = true
        end
        fresh[id] = entry
    end
    C.known = fresh
    if A.Client and A.Client.invalidateTrade then A.Client.invalidateTrade(fresh) end
    if A.Physics.sweepSP then A.Physics.sweepSP() end
    for id, entry in pairs(fresh) do
        local s, sleeping = C.sessionFor(id)
        if s ~= nil and not sleeping then pcall(A.Physics.prepare, s, entry) end
    end
end

function C.sessionFor(id)
    local owner = C.owner()
    if owner == nil then return nil end
    local s = owner.sessions and owner.sessions[id] or nil
    if s ~= nil then return s end
    local record = owner.sleeping and owner.sleeping[id] or nil
    if record ~= nil then return record.restored or record.session, true end
    return nil
end

function C.localPlayer()
    if type(getSpecificPlayer) == "function" then
        local ok, player = pcall(getSpecificPlayer, 0)
        if ok and player ~= nil then return player end
    end
    return A.players()[1]
end

local function passedGoal(x, y, g1, g2)
    if g1 == nil or g2 == nil then return false end
    local vx, vy = g2.x - g1.x, g2.y - g1.y
    local len2 = vx * vx + vy * vy
    if len2 < 1 then return false end
    local t = ((x - g1.x) * vx + (y - g1.y) * vy) / len2
    if t <= 0.15 then return false end
    local clamped = math.max(0, math.min(1, t))
    local px, py = g1.x + vx * clamped, g1.y + vy * clamped
    if A.dist(x, y, px, py) > 40 then return false end
    return A.dist(x, y, g2.x, g2.y) < math.sqrt(len2)
end

local function vehicleHeading(vehicle)
    if vehicle == nil or type(vehicle.getForwardVector) ~= "function" or type(Vector3f) ~= "table" and type(Vector3f) ~= "userdata" then
        return nil
    end
    local ok, h = pcall(function()
        local f = vehicle:getForwardVector(Vector3f.new())
        return f and A.atan2(f:z(), f:x()) or nil
    end)
    return ok and type(h) == "number" and h or nil
end

-- The next goal for a car: the first route goal farther than goalReach from (x, y)
-- that has not already been passed along the current segment.
function C.goalFor(entry, x, y)
    local goals = entry.goals or {}
    local index = entry.goalIndex or 1
    local lookLimit = math.min(#goals - 1, index + 8)
    for k = index, lookLimit do
        if A.dist(x, y, goals[k].x, goals[k].y) <= C.goalReach
                or passedGoal(x, y, goals[k], goals[k + 1]) then
            index = k + 1
        end
    end
    while index <= #goals and (A.dist(x, y, goals[index].x, goals[index].y) <= C.goalReach
            or (index < #goals and passedGoal(x, y, goals[index], goals[index + 1]))) do
        index = index + 1
    end
    entry.goalIndex = index
    return goals[index], index
end

-- Scout the next waypoints for a session from its current queue tail (or from
-- the car itself when `fresh`).
function C.legFor(entry, s, fresh)
    local vehicle = s.vehicle
    local x, y = A.xyz(vehicle)
    if x == nil then return nil, "no vehicle position" end
    local tail = (not fresh) and s.route and s.route[#s.route] or nil
    local from = tail and { x = tail.x, y = tail.y } or { x = x, y = y }
    -- Only physical progress advances the shared goal cursor. A queued tail
    -- reaching the destination is not an arrival (nor an escort reward).
    local goal = C.goalFor(entry, x, y)
    if goal == nil then return nil, "arrived" end
    if tail then
        local lookahead = {goals=entry.goals, goalIndex=entry.goalIndex}
        goal = C.goalFor(lookahead, from.x, from.y)
        if goal == nil then return nil, "route_queued" end
    end
    local heading = fresh and vehicleHeading(vehicle) or nil
    if heading == nil and tail ~= nil and s.route ~= nil and #s.route >= 2 then
        local prev = s.route[#s.route - 1]
        if A.dist(tail.x, tail.y, prev.x, prev.y) >= 1 then
            heading = A.atan2(tail.y - prev.y, tail.x - prev.x)
        end
    end
    local scene = A.Roads.scene(C.localPlayer())
    local points, info = A.Roads.scout(scene, from, goal, { maxPoints = 10, heading = heading })
    if #points == 0 then return nil, info.reason or "no road" end
    local out = {}
    local lastX, lastY = from.x, from.y
    for _, p in ipairs(points) do
        if A.dist(p.x, p.y, lastX, lastY) >= 1.5 then
            out[#out + 1] = { x = p.x, y = p.y }
            lastX, lastY = p.x, p.y
        end
    end
    if fresh and heading ~= nil and #out >= 2 then
        local d1 = A.dist(out[1].x, out[1].y, from.x, from.y)
        local along = (out[1].x - from.x) * math.cos(heading) + (out[1].y - from.y) * math.sin(heading)
        if d1 < 6 and along < 2 then table.remove(out, 1) end
    end
    if #out == 0 then return nil, "no progress" end
    return out, info
end

-- Append waypoints to a driving session (single player directly, multiplayer
-- through A-Life's host-acknowledged route extension).
function C.extend(s, points)
    local Route = ProjectALife.DrivingRoute
    local client = C.client()
    if type(isClient) == "function" and isClient() and client ~= nil and type(client.appendRoute) == "function" then
        local fleet = ProjectALife.DrivingFleet
        if fleet ~= nil and type(fleet.focus) == "function" then
            local ok, result = fleet.focus(client, s, client.appendRoute, points)
            return ok and s.appendPending ~= nil, result
        end
        return false, "no fleet focus"
    end
    if Route == nil then return false, "no route module" end
    local additions, extra = Route.append(s, points)
    if not additions then return false, extra end
    Route.extend(s, additions, extra)
    return true
end

function C.stop(s, reason)
    local client = C.client()
    local fleet = ProjectALife.DrivingFleet
    if client == nil or fleet == nil or type(client.stop) ~= "function" then
        s.braking = true
        s.stopReason = reason or "caravan halt"
        return true
    end
    local ok = fleet.focus(client, s, client.stop)
    if reason then s.stopReason = reason end
    return ok
end

function C.start(id, points, speedKmh)
    local client = C.client()
    if client == nil or type(client.startDrive) ~= "function" then return false, "no driving client" end
    local ok, result = pcall(client.startDrive, id, points, speedKmh)
    if not ok then return false, result end
    local started = false
    if type(result)=="boolean" then
        started = result
    else
        -- Upstream returns nil both on rejection and success: inspect its queued
        -- request/state, not merely the absence of a Lua exception.
        local s=client.sessions and client.sessions[id]
        if client.departures and client.departures[id] then started = true
        elseif s and (s.drivePending or s.phase=="readywait" or s.phase=="driving") then started = true end
    end
    if started then
        local s = client.sessions and client.sessions[id]
        local entry = C.known[id]
        if s and entry and A.Physics and A.Physics.prepare then pcall(A.Physics.prepare, s, entry) end
        return true
    end
    local s = client.sessions and client.sessions[id]
    return false, s and s.status or "departure not queued"
end

function C.remainingRoute(s)
    local x,y=A.xyz(s.vehicle)
    if not x then return {} end
    local points={}
    for _,point in ipairs(s.route or {}) do
        if A.dist(x,y,point.x,point.y)>=1.5 then
            points[#points+1]={x=point.x,y=point.y}
            x,y=point.x,point.y
        end
    end
    return points
end

function C.report(command, args)
    if type(isClient) == "function" and isClient() then
        pcall(sendClientCommand, C.localPlayer(), A.MODULE, command, args)
    elseif A.Director ~= nil and type(A.Director.onConvoyReport) == "function" then
        pcall(A.Director.onConvoyReport, nil, command, args)
    end
end

function C.driverShell(s)
    return s and s.npc or nil
end

local function speedFor(entry)
    local kmh = tonumber(entry.speedKmh) or A.settings.cruiseKmh
    local demo = ProjectALife.DrivingDemo
    local limit = demo and tonumber(demo.maxSpeedKmh) or 75
    return math.max(5, math.min(limit, kmh))
end

-- Cars of one caravan on this side, ordered by their place in the convoy.
function C.groups()
    local groups = {}
    for id, entry in pairs(C.known) do
        local s, sleeping = C.sessionFor(id)
        local x, y
        if s ~= nil then x, y = A.xyz(s.vehicle) end
        local group = groups[entry.caravanId]
        if group == nil then group = {} groups[entry.caravanId] = group end
        group[#group + 1] = { id = id, entry = entry, s = (not sleeping) and s or nil, x = x, y = y, index = tonumber(entry.index) or 99 }
    end
    for _, group in pairs(groups) do
        table.sort(group, function(a, b) return a.index < b.index end)
    end
    return groups
end

-- Formation: the cruise speed of a car from the gap to the car ahead and from
-- the straggler behind the leader. s.speedGuard keeps A-Life's speed guard on
-- the full speed while we lower s.cruiseSpeed.
function C.formationSpeed(group, position)
    local row = group[position]
    local base = speedFor(row.entry) / 3.6
    local f = C.formation
    local factor = 1
    if position > 1 then
        local ahead = group[position - 1]
        if ahead ~= nil and ahead.x ~= nil and row.x ~= nil then
            local gap = A.dist(row.x, row.y, ahead.x, ahead.y)
            if gap <= f.stopGap then factor = 0
            elseif gap < f.fullGap then factor = math.max(f.crawl, (gap - f.stopGap) / (f.fullGap - f.stopGap)) end
        end
    else
        local tail = group[#group]
        if tail ~= row and tail.x ~= nil and row.x ~= nil then
            local gap = A.dist(row.x, row.y, tail.x, tail.y)
            local entry = row.entry
            if gap > f.regroupGap then entry.regrouping = true end
            if entry.regrouping and gap < f.regroupDone then entry.regrouping = nil end
            if entry.regrouping then factor = f.regroupFactor end
        end
    end
    return base * factor, base, factor
end

function C.applySpeed(s, cruise, full)
    s.speedGuard = full
    s.cruiseSpeed = cruise
end

-- No progress for a while: skip the waypoint, re-scout, then tell the director.
function C.stuckTick(id, entry, s, now, blockedByPlayer, waitingOnConvoy)
    local x, y = A.xyz(s.vehicle)
    if x == nil then return end
    local st = entry.stuck
    local physicsOff = type(s.vehicle.isPhysicsActive) == "function" and s.vehicle:isPhysicsActive() == false
    if st == nil or A.dist(x, y, st.x, st.y) >= C.stuck.moveTiles or s.braking or s.terrainWaiting or s.alcPhysicsWaiting or physicsOff or blockedByPlayer or waitingOnConvoy then
        entry.stuck = { x = x, y = y, sinceMs = now, stage = 0 }
        return
    end
    local age = now - st.sinceMs
    if st.stage == 0 and age >= C.stuck.skipMs then
        st.stage = 1
        if s.route ~= nil and #s.route > 1 then table.remove(s.route, 1) end
        s.navigation, s.detourPoints, s.detourIndex = nil, nil, nil
        A.metrics.unstuck = A.metrics.unstuck + 1
        A.debug("car", id, "stuck: skipping a waypoint")
    elseif st.stage == 1 and age >= C.stuck.rescoutMs then
        st.stage = 2
        entry.discardRoute = true
        C.stop(s, "stuck: re-scouting the road")
        A.metrics.rescouts = A.metrics.rescouts + 1
        A.Lines.say(C.driverShell(s), "stuck", { uid = s.uid, cooldownMs = 60000 })
        A.debug("car", id, "stuck: parking to re-scout")
    elseif st.stage == 2 and age >= C.stuck.reportMs then
        st.stage = 3
        C.report("stuck", { vehicleId = id, x = x, y = y })
        A.debug("car", id, "stuck: reported to the director")
    end
end

local function playerVehicleNear(vehicle, radius)
    local vx, vy = A.xyz(vehicle)
    if vx == nil then return false end
    for _, player in ipairs(A.players()) do
        local inside = false
        pcall(function() inside = player:getVehicle() ~= nil end)
        local px, py = A.xyz(player)
        if inside and px ~= nil and A.dist(px, py, vx, vy) <= radius then return true end
    end
    return false
end

function C.isCaravanVehicle(v)
    if v == nil or type(v.getId) ~= "function" then return false end
    local ok, id = pcall(v.getId, v)
    if ok and id ~= nil and C.known[id] ~= nil then return true, id, C.known[id] end
    local tag = A.vehicleTag(v)
    if tag ~= nil then return true, ok and id or nil, nil end
    if A.Spawn and A.Spawn.pending ~= nil then return true, ok and id or nil, nil end
    return false
end

function C.ensureTuning(s)
    if type(s) ~= "table" or type(s.tuning) ~= "table" or s.alcTuned then return end
    s.alcTuned = true
    s.tuning.reverseDelay = 2000
    s.tuning.reverseRetryMs = 4000
    s.tuning.reverseDistance = 2.5
    s.tuning.steeringSlow = 0.4
    s.tuning.precisionKmh = 16
    s.tuning.returnKmh = 11
    s.tuning.scanMs = 150
    s.tuning.nodesPerTick = 16
    s.tuning.searchBudgetMs = 2
    s.tuning.maxNodes = 2400
    s.tuning.horizon = 36
    s.tuning.maxHorizon = 96
end

function C.sharedTiles(now, z)
    local entry = C.tileCache[z]
    if entry == nil or now >= entry.expiresAtMs then
        entry = { squares = {}, edges = {}, expiresAtMs = now + 250 }
        C.tileCache[z] = entry
    end
    return entry
end

local function collectALifeNpcs(p, cell, now)
    local out, seen = {}, {}
    local function addShell(shell)
        if shell ~= nil and not seen[shell] then
            seen[shell] = true
            local dead = false
            pcall(function() dead = shell:isDead() end)
            if not dead then out[#out + 1] = shell end
        end
    end
    local usedFastTable = false
    if p.Watchdog and type(p.Watchdog.bindings) == "table" then
        for _, b in pairs(p.Watchdog.bindings) do
            usedFastTable = true
            if type(b) == "table" then addShell(b.shell) end
        end
    end
    if p.Executor and type(p.Executor.executed) == "table" then
        for _, e in pairs(p.Executor.executed) do
            usedFastTable = true
            if type(e) == "table" then addShell(e.shell) end
        end
    end
    if usedFastTable then return out end
    local cache = C.npcScanCache
    if cache ~= nil and now < cache.expiresAtMs then
        for _, shell in ipairs(cache.shells) do addShell(shell) end
        return out
    end
    local shells = {}
    if cell ~= nil and type(cell.getZombieList) == "function" then
        local ok, zombies = pcall(cell.getZombieList, cell)
        if ok and zombies ~= nil and type(zombies.size) == "function" then
            for i = 0, zombies:size() - 1 do
                local actor = zombies:get(i)
                local data = actor ~= nil and type(actor.getModData) == "function" and actor:getModData() or nil
                if data and (data.ProjectALifeOwned or data.ProjectALifeActor or data.ProjectALifeUID) then
                    shells[#shells + 1] = actor
                    addShell(actor)
                end
            end
        end
    end
    C.npcScanCache = { shells = shells, expiresAtMs = now + 400 }
    return out
end

function C.cachedWorldBodies(now, bodyPadding)
    local cache = C.bodyCache
    if cache ~= nil and now < cache.expiresAtMs and cache.bodyPadding == bodyPadding then
        return cache
    end
    local p = ProjectALife
    local R = p and p.DrivingRoute
    local cell = type(getCell) == "function" and getCell() or nil
    local vehicles, pedestrians = {}, {}
    if cell ~= nil and R ~= nil and type(R.dimensions) == "function" and type(cell.getVehicles) == "function" then
        local ok, list = pcall(cell.getVehicles, cell)
        local it = ok and list and type(list.iterator) == "function" and list:iterator() or nil
        while it and it:hasNext() do
            local other = it:next()
            local ox, oy, oz = A.xyz(other)
            if ox ~= nil then
                local okId, oid = pcall(other.getId, other)
                oid = okId and oid or nil
                local otag = (oid and C.known[oid] and C.known[oid].caravanId) or A.vehicleTag(other)
                local w, l = R.dimensions(other, bodyPadding)
                local h = vehicleHeading(other)
                local speed = nil
                if p.DrivingProbe and type(p.DrivingProbe.read) == "function" then
                    speed = p.DrivingProbe.read(other, "getCurrentSpeedKmHour")
                elseif type(other.getCurrentSpeedKmHour) == "function" then
                    local okSpd, val = pcall(other.getCurrentSpeedKmHour, other)
                    if okSpd then speed = val end
                end
                vehicles[#vehicles + 1] = {
                    obj = other, id = oid, caravanId = otag,
                    x = ox, y = oy, z = oz or 0,
                    w = w, l = l, heading = h,
                    radius = math.sqrt(w * w + l * l),
                    moving = speed == nil or math.abs(speed) > 0.5,
                }
            end
        end
    end
    if p ~= nil then
        for _, npc in ipairs(collectALifeNpcs(p, cell, now)) do
            local inCar = nil
            pcall(function() inCar = npc:getVehicle() end)
            if inCar == nil then
                local nx, ny, nz = A.xyz(npc)
                if nx ~= nil then
                    pedestrians[#pedestrians + 1] = { obj = npc, x = nx, y = ny, z = nz or 0, label = "A-Life NPC" }
                end
            end
        end
    end
    for _, pl in ipairs(A.players()) do
        local inCar = nil
        pcall(function() inCar = pl:getVehicle() end)
        if inCar == nil then
            local px, py, pz = A.xyz(pl)
            if px ~= nil then
                pedestrians[#pedestrians + 1] = { obj = pl, x = px, y = py, z = pz or 0, label = "player" }
            end
        end
    end
    cache = { expiresAtMs = now + 150, bodyPadding = bodyPadding, vehicles = vehicles, pedestrians = pedestrians }
    C.bodyCache = cache
    return cache
end

function C.fastScene(v, tuning, id, entry)
    local p = ProjectALife
    local R = p and p.DrivingRoute
    local T = p and p.DrivingTuning
    local now = A.now()
    local vx, vy, vz = A.xyz(v)
    local z = math.floor(vz or 0)
    local shared = C.sharedTiles(now, z)
    local scene = { squares = shared.squares, edges = shared.edges, bodies = {}, z = z, padding = 0, tuning = tuning }
    scene.bodyPadding = (T and type(T.value) == "function" and T.value(scene, "bodyPadding")) or 0.05
    scene.vehicle = v
    scene.halfWidth, scene.halfLength = R.dimensions(v, scene.bodyPadding)
    local caravanId = (entry and entry.caravanId) or A.vehicleTag(v)
        or (A.Spawn and A.Spawn.pending and A.Spawn.pending.caravan and A.Spawn.pending.caravan.id) or nil
    local convoyPositions = {}
    if caravanId ~= nil then
        for otherId, otherEntry in pairs(C.known) do
            if otherId ~= id and otherEntry.caravanId == caravanId then
                local os = C.sessionFor(otherId)
                local ov = (os and os.vehicle) or (type(getVehicleById) == "function" and getVehicleById(otherId)) or nil
                local ox, oy = A.xyz(ov)
                if ox ~= nil then convoyPositions[#convoyPositions + 1] = { x = ox, y = oy } end
            end
        end
    end
    local h = vehicleHeading(v)
    local fx, fy = h and math.cos(h) or nil, h and math.sin(h) or nil
    local world = C.cachedWorldBodies(now, scene.bodyPadding)
    local bodies = scene.bodies
    for _, row in ipairs(world.vehicles) do
        if row.obj ~= v and (id == nil or row.id ~= id) and math.abs(row.z - (vz or 0)) <= 0.5 then
            if not (caravanId ~= nil and row.caravanId == caravanId)
                    and (vx == nil or A.dist(row.x, row.y, vx, vy) <= 72) then
                local sameConvoy = false
                for _, pos in ipairs(convoyPositions) do
                    if A.dist(row.x, row.y, pos.x, pos.y) < 2.0 then sameConvoy = true break end
                end
                if not sameConvoy then
                    bodies[#bodies + 1] = {
                        x = row.x, y = row.y, radius = row.radius, label = "vehicle",
                        moving = row.moving, heading = row.heading, w = row.w, l = row.l,
                        boundRadius = row.heading and row.radius or row.radius * 1.4142135623730951,
                    }
                end
            end
        end
    end
    for _, row in ipairs(world.pedestrians) do
        if row.obj ~= v and math.abs(row.z - (vz or 0)) <= 0.5
                and (vx == nil or A.dist(row.x, row.y, vx, vy) <= 60) then
            local moving = true
            if vx ~= nil and fx ~= nil then
                local dx, dy = row.x - vx, row.y - vy
                local across = math.abs(-dx * fy + dy * fx)
                if across > 1.35 then moving = false end
            end
            bodies[#bodies + 1] = {
                x = row.x, y = row.y, radius = 0.5, label = row.label,
                moving = moving, boundRadius = 0.5 * 1.4142135623730951,
            }
        end
    end
    return scene
end

function C.installHooks()
    if C.hooksInstalled then return end
    local p = ProjectALife
    if type(p) ~= "table" or p.DrivingDemo == nil then return end
    C.hooksInstalled = true
    if type(p.DrivingEscape) == "table" and type(p.DrivingEscape.tick) == "function" then
        A.wrap(p.DrivingEscape, "tick", function(original)
            return function(s, now)
                if s ~= nil and C.isCaravanVehicle(s.vehicle) then
                    s.escapeUntil, s.escapeActive = nil, nil
                    return
                end
                return original(s, now)
            end
        end, "DrivingEscape.tick")
    end
    if type(p.DrivingRoute) == "table" and type(p.DrivingRoute.scene) == "function" then
        A.wrap(p.DrivingRoute, "scene", function(original)
            return function(v, tuning)
                local isCaravan, id, entry = C.isCaravanVehicle(v)
                if not isCaravan then return original(v, tuning) end
                if type(p.DrivingRoute.dimensions) == "function" and type(getCell) == "function" then
                    local ok, fast = pcall(C.fastScene, v, tuning, id, entry)
                    if ok and type(fast) == "table" then return fast end
                end
                local scene = original(v, tuning)
                if type(scene) ~= "table" or type(scene.bodies) ~= "table" then return scene end
                local convoyPositions = {}
                local caravanId = entry and entry.caravanId or A.vehicleTag(v)
                if caravanId ~= nil then
                    for otherId, otherEntry in pairs(C.known) do
                        if otherId ~= id and otherEntry.caravanId == caravanId then
                            local os = C.sessionFor(otherId)
                            local ov = (os and os.vehicle) or (type(getVehicleById) == "function" and getVehicleById(otherId)) or nil
                            local ox, oy = A.xyz(ov)
                            if ox ~= nil then convoyPositions[#convoyPositions + 1] = { x = ox, y = oy } end
                        end
                    end
                end
                local vx, vy = A.xyz(v)
                local h = vehicleHeading(v)
                local fx, fy = h and math.cos(h) or nil, h and math.sin(h) or nil
                local filtered = {}
                for _, b in ipairs(scene.bodies) do
                    local sameConvoy = false
                    if b.label == "vehicle" and #convoyPositions > 0 then
                        for _, pos in ipairs(convoyPositions) do
                            if A.dist(b.x, b.y, pos.x, pos.y) < 2.0 then
                                sameConvoy = true
                                break
                            end
                        end
                    end
                    if not sameConvoy then
                        if (b.label == "player" or b.label == "A-Life NPC") and vx ~= nil and fx ~= nil then
                            local dx, dy = b.x - vx, b.y - vy
                            local across = math.abs(-dx * fy + dy * fx)
                            if across > 1.35 then b.moving = false end
                        end
                        filtered[#filtered + 1] = b
                    end
                end
                scene.bodies = filtered
                return scene
            end
        end, "DrivingRoute.scene")
    end
    if type(p.DrivingControl) == "table" and type(p.DrivingControl.apply) == "function" then
        A.wrap(p.DrivingControl, "apply", function(original)
            return function(s, heading, ax, ay, alpha, impulse)
                if s ~= nil and C.isCaravanVehicle(s.vehicle) then
                    if type(s.vehicle.isPhysicsActive) == "function" and s.vehicle:isPhysicsActive() == false then
                        s.turnTorque = 0
                        return
                    end
                    local accel = math.sqrt((ax or 0) * (ax or 0) + (ay or 0) * (ay or 0))
                    local parkedOrWaiting = (s.phase == "seated" or s.braking or s.obstacleSince ~= nil)
                        and math.abs(s.targetSpeed or 0) < 0.01
                    if parkedOrWaiting then
                        local speed = (p.DrivingDemo and type(p.DrivingDemo.speed) == "function" and p.DrivingDemo.speed(s.vehicle)) or 0
                        if speed < 0.08 then
                            s.turnTorque = 0
                            return
                        end
                    end
                    if accel < 0.015 and math.abs(alpha or 0) < 0.002 then
                        s.turnTorque = 0
                        return
                    end
                    if math.abs(alpha or 0) < 0.002 and type(impulse) == "function" then
                        local count = 0
                        local linearOnly = function(v, x, y, dx, dy, strength)
                            count = count + 1
                            if count == 1 then return impulse(v, x, y, dx, dy, strength) end
                        end
                        return original(s, heading, ax, ay, 0, linearOnly)
                    end
                end
                return original(s, heading, ax, ay, alpha, impulse)
            end
        end, "DrivingControl.apply")
    end
    if type(p.DrivingDemoClient) == "table" and type(p.DrivingDemoClient.drive) == "function" then
        A.wrap(p.DrivingDemoClient, "drive", function(original)
            return function(s)
                if s ~= nil and type(s.last) == "number" and C.isCaravanVehicle(s.vehicle) then
                    local now = A.now()
                    if now - s.last > 200 then
                        s.last = now - 50
                    end
                end
                return original(s)
            end
        end, "DrivingDemoClient.drive")
    end
    if type(p.DrivingRecovery) == "table" and type(p.DrivingRecovery.driveStall) == "function" then
        A.wrap(p.DrivingRecovery, "driveStall", function(original)
            return function(s, n, now)
                if s ~= nil and type(n) == "table" and C.isCaravanVehicle(s.vehicle) and n.obstacle == nil then
                    local t = now or A.now()
                    local elapsed = t - (s.started or t)
                    local speed = (p.DrivingDemo and type(p.DrivingDemo.speed) == "function" and p.DrivingDemo.speed(s.vehicle)) or 0
                    local physicsOff = type(s.vehicle.isPhysicsActive) == "function" and s.vehicle:isPhysicsActive() == false
                    if elapsed < 3500 or speed > 0.2 or physicsOff then
                        n.driveProgress, n.driveStallMs, n.recoveryStop, n.retryProgress = nil, 0, nil, nil
                        return false
                    end
                end
                return original(s, n, now)
            end
        end, "DrivingRecovery.driveStall")
    end
    if type(p.DrivingEntry) == "table" and type(p.DrivingEntry.walked) == "function" then
        A.wrap(p.DrivingEntry, "walked", function(original)
            return function(s)
                local arrived, err = original(s)
                if not arrived and err ~= nil and type(s) == "table" and s.phase == "approach" and C.isCaravanVehicle(s.vehicle) then
                    if type(s.walkAction) == "table" and s.walkAction.status == "cancelled" and (s.walkRetries or 0) < 3 and s.walkTarget ~= nil then
                        s.walkRetries = (s.walkRetries or 0) + 1
                        if p.DrivingDemo and type(p.DrivingDemo.stopActor) == "function" then pcall(p.DrivingDemo.stopActor, s) end
                        pcall(p.DrivingEntry.walk, s, s.walkTarget)
                        return false, nil
                    end
                end
                return arrived, err
            end
        end, "DrivingEntry.walked")
    end
end

function C.tickOne(group, position, now)
    local row = group[position]
    local id, entry, s = row.id, row.entry, row.s
    if s == nil then return end
    if s.exitAt or s.exitRequested or s.detaching then return end
    local vehicle = s.vehicle
    if vehicle == nil then return end
    C.ensureTuning(s)
    A.Physics.prepare(s, entry)
    if entry.halted then
        if s.phase == "driving" and not s.braking then C.stop(s, "caravan halted") end
        if s.phase == "seated" then entry.parkedAt = entry.parkedAt or now end
        entry.stuck = nil
        return
    end
    if s.phase == "driving" then
        entry.parkedAt = nil
        local cruise, full, factor = C.formationSpeed(group, position)
        C.applySpeed(s, cruise, full)
        if factor < 1 then
            s.lastProgressAt = now
            if type(s.navigation) == "table" then
                s.navigation.driveProgress, s.navigation.retryProgress = nil, nil
                s.navigation.blockedSince, s.navigation.progressMark = nil, nil
            end
        end
        if position == 1 and entry.regrouping and now >= (entry.regroupSaidAt or 0) then
            entry.regroupSaidAt = now + 60000
            A.Lines.say(C.driverShell(s), "regroup", { uid = s.uid, cooldownMs = 60000 })
        end
        local tail = s.route and s.route[#s.route] or nil
        local vx, vy = A.xyz(vehicle)
        local tailDist = (tail and vx ~= nil) and A.dist(vx, vy, tail.x, tail.y) or 0
        if not s.braking and not s.appendPending and s.route ~= nil
                and (#s.route == 0 or (#s.route <= C.lowQueue and tailDist <= 38))
                and not C.scoutedThisTick and now >= (entry.nextScoutAt or 0) then
            C.scoutedThisTick = true
            entry.nextScoutAt = now + 600
            local points, info = C.legFor(entry, s)
            if points ~= nil then
                local ok, err = C.extend(s, points)
                if ok then
                    A.metrics.legs = A.metrics.legs + 1
                    A.debug("car", id, "route +" .. #points .. " points toward goal", entry.goalIndex)
                else
                    A.debug("car", id, "route extension refused:", err)
                end
            elseif info == "arrived" and not entry.arrivedSent then
                entry.arrivedSent = true
                C.report("arrived", { vehicleId = id })
            end
        end
        local blockedByPlayer = s.obstacleSince ~= nil and playerVehicleNear(vehicle, 12)
        if blockedByPlayer and now - s.obstacleSince > 6000 and now >= (entry.blockedSaidAt or 0) then
            entry.blockedSaidAt = now + 30000
            A.Lines.say(C.driverShell(s), "blocked", { uid = s.uid })
        end
        C.stuckTick(id, entry, s, now, blockedByPlayer, factor < 1)
        if now >= (entry.passedAt or 0) then
            local player = C.localPlayer()
            local px, py = A.xyz(player)
            local vx, vy = A.xyz(vehicle)
            if px ~= nil and vx ~= nil and A.dist(px, py, vx, vy) <= 10 then
                entry.passedAt = now + 60000
                A.Lines.say(C.driverShell(s), "passing", { uid = s.uid, cooldownMs = 60000 })
            end
        end
        return
    end
    if s.phase == "seated" and not s.drivePending and not s.parkPending and not s.joining and not s.joinPending then
        entry.parkedAt = entry.parkedAt or now
        local owner = C.owner()
        if owner ~= nil and owner.departures ~= nil and owner.departures[id] ~= nil then return end
        -- followers leave a little after the car ahead
        local delay = (entry.threatState == "escape" and 800 or C.restartDelayMs) + (position - 1) * 1200
        if now - entry.parkedAt < delay then return end
        if entry.discardRoute then
            entry.discardRoute = nil
            s.route = {}
        end
        if s.route ~= nil and #s.route > 0 then
            local copy = C.remainingRoute(s)
            if #copy>0 then
                entry.parkedAt = now
                entry.restartCount = (entry.restartCount or 0) + 1
                C.start(id, copy, speedFor(entry))
                return
            end
            s.route = {} -- All queued points already reached; scout a real leg.
        end
        if not C.scoutedThisTick and now >= (entry.nextScoutAt or 0) then
            C.scoutedThisTick = true
            entry.nextScoutAt = now + 1000
            local points, info = C.legFor(entry, s, true)
            if points ~= nil then
                entry.parkedAt = now
                entry.stuck = nil
                local ok, err = C.start(id, points, speedFor(entry))
                if ok then A.metrics.legs = A.metrics.legs + 1 else A.debug("car", id, "start refused:", err) end
            elseif info == "arrived" and not entry.arrivedSent then
                entry.arrivedSent = true
                C.report("arrived", { vehicleId = id })
            end
        end
    end
end

function C.tick()
    if not A.drivingSide() then return end
    C.installHooks()
    local now = A.now()
    if now < C.nextTickMs then return end
    C.nextTickMs = now + C.intervalMs
    C.scoutedThisTick = false
    if A.Physics.sweepSP then A.Physics.sweepSP() end
    if ProjectALife == nil or ProjectALife.DrivingDemoClient == nil then return end
    for _, group in pairs(C.groups()) do
        for position = 1, #group do
            local ok, err = pcall(C.tickOne, group, position, now)
            if not ok then A.fail("convoy tick " .. tostring(group[position].id), err) end
        end
    end
end

-- Caravan vehicles within `radius` tiles of a player: rows { vehicle, id, entry, distance }.
function C.near(player, radius)
    local out = {}
    local px, py = A.xyz(player)
    if px == nil or type(getCell) ~= "function" then return out end
    local ok, err = pcall(function()
        local list = getCell():getVehicles()
        if list == nil or list.iterator == nil then return end
        -- Build 42.21 returns a Java Set here: size()/iterator(), no get(index).
        local iterator = list:iterator()
        while iterator:hasNext() do
            local vehicle = iterator:next()
            local id = vehicle ~= nil and vehicle:getId() or nil
            local entry = id ~= nil and C.known[id] or nil
            if entry ~= nil then
                local vx, vy = A.xyz(vehicle)
                local distance = vx ~= nil and A.dist(px, py, vx, vy) or math.huge
                if distance <= radius then out[#out + 1] = { vehicle = vehicle, id = id, entry = entry, distance = distance } end
            end
        end
    end)
    if not ok then A.fail("convoy near", err) end
    table.sort(out, function(a, b) return a.distance < b.distance end)
    return out
end

return C
