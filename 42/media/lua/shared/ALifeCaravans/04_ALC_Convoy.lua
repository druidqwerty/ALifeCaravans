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
local C = { known = {}, nextTickMs = 0, intervalMs = 600, goalReach = 22, lowQueue = 2, restartDelayMs = 3000,
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
        if previous ~= nil and previous.caravanId == entry.caravanId then
            if previous.trip == entry.trip then
                entry.goalIndex = math.max(entry.goalIndex or 1, previous.goalIndex or 1)
                entry.arrivedSent = previous.arrivedSent
            end
            entry.parkedAt = previous.parkedAt
            entry.blockedSaidAt = previous.blockedSaidAt
            entry.passedAt = previous.passedAt
            entry.nextScoutAt = previous.nextScoutAt
            entry.stuck = previous.stuck
            entry.regroupSaidAt = previous.regroupSaidAt
            entry.discardRoute = previous.discardRoute
            entry.restartCount = previous.restartCount
        end
        fresh[id] = entry
    end
    C.known = fresh
    if A.Physics.sweepSP then A.Physics.sweepSP() end
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

-- The next goal for a car: the first route goal farther than goalReach from (x, y).
function C.goalFor(entry, x, y)
    local goals = entry.goals or {}
    local index = entry.goalIndex or 1
    while index <= #goals and A.dist(x, y, goals[index].x, goals[index].y) <= C.goalReach do index = index + 1 end
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
    local scene = A.Roads.scene(C.localPlayer())
    local points, info = A.Roads.scout(scene, from, goal, { maxPoints = 10 })
    if #points == 0 then return nil, info.reason or "no road" end
    local out = {}
    local lastX, lastY = from.x, from.y
    for _, p in ipairs(points) do
        if A.dist(p.x, p.y, lastX, lastY) >= 1.5 then
            out[#out + 1] = { x = p.x, y = p.y }
            lastX, lastY = p.x, p.y
        end
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
    local ok, err = pcall(client.startDrive, id, points, speedKmh)
    if not ok then return false, err end
    return true
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
    if st == nil or A.dist(x, y, st.x, st.y) >= C.stuck.moveTiles or s.braking or s.terrainWaiting or blockedByPlayer or waitingOnConvoy then
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

function C.tickOne(group, position, now)
    local row = group[position]
    local id, entry, s = row.id, row.entry, row.s
    if s == nil then return end
    if s.exitAt or s.exitRequested or s.detaching then return end
    local vehicle = s.vehicle
    if vehicle == nil then return end
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
        if position == 1 and entry.regrouping and now >= (entry.regroupSaidAt or 0) then
            entry.regroupSaidAt = now + 60000
            A.Lines.say(C.driverShell(s), "regroup", { uid = s.uid, cooldownMs = 60000 })
        end
        if not s.braking and not s.appendPending and s.route ~= nil and #s.route <= C.lowQueue
                and now >= (entry.nextScoutAt or 0) then
            entry.nextScoutAt = now + 1500
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
        local delay = C.restartDelayMs + (position - 1) * 1500
        if now - entry.parkedAt < delay then return end
        if entry.discardRoute then
            entry.discardRoute = nil
            s.route = {}
        end
        if s.route ~= nil and #s.route > 0 then
            entry.parkedAt = now
            local copy = {}
            for _, p in ipairs(s.route) do copy[#copy + 1] = { x = p.x, y = p.y } end
            entry.restartCount = (entry.restartCount or 0) + 1
            C.start(id, copy, speedFor(entry))
            return
        end
        if now >= (entry.nextScoutAt or 0) then
            entry.nextScoutAt = now + 2000
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
    local now = A.now()
    if now < C.nextTickMs then return end
    C.nextTickMs = now + C.intervalMs
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
