-- A-Life: Caravans - the driving side. A caravan car is an A-Life driving
-- session (ProjectALife.DrivingDemoClient in single player and on the
-- multiplayer client that A-Life hands the car to). This module keeps those
-- sessions moving along the caravan's long route: when the queued waypoints run
-- low it scouts the next stretch of loaded road toward the next goal and appends
-- it; when the car parked at the end of a stretch it starts the next one; when
-- the caravan is halted it stops the car. Which cars are caravans comes from
-- C.known (filled by the director directly in single player, by a server
-- command in multiplayer).

require "ALifeCaravans/00_ALC_Core"
require "ALifeCaravans/01_ALC_Lines"
require "ALifeCaravans/03_ALC_Roads"

local A = ALifeCaravans
local C = { known = {}, nextTickMs = 0, intervalMs = 700, goalReach = 22, lowQueue = 2, restartDelayMs = 3000 }
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

-- Replace the known table (server broadcast / director update).
function C.setKnown(entries)
    local fresh = {}
    for id, entry in pairs(entries or {}) do
        local previous = C.known[id]
        if previous ~= nil then
            entry.parkedAt = previous.parkedAt
            entry.goalIndex = math.max(entry.goalIndex or 1, previous.goalIndex or 1)
            entry.blockedSaidAt = previous.blockedSaidAt
            entry.passedAt = previous.passedAt
            entry.arrivedSent = previous.arrivedSent
        end
        fresh[id] = entry
    end
    C.known = fresh
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

-- Scout the next waypoints for a session from its current queue tail.
function C.legFor(entry, s)
    local vehicle = s.vehicle
    local x, y = A.xyz(vehicle)
    if x == nil then return nil, "no vehicle position" end
    local tail = s.route and s.route[#s.route] or nil
    local from = tail and { x = tail.x, y = tail.y } or { x = x, y = y }
    local goal = C.goalFor(entry, from.x, from.y)
    if goal == nil then return nil, "arrived" end
    local scene = A.Roads.scene(C.localPlayer())
    local points, info = A.Roads.scout(scene, from, goal, { maxPoints = 10 })
    if #points == 0 then return nil, info.reason or "no road" end
    -- Drop points already queued or behind the tail.
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

function C.stop(s)
    local client = C.client()
    local fleet = ProjectALife.DrivingFleet
    if client == nil or fleet == nil or type(client.stop) ~= "function" then return false end
    local ok = fleet.focus(client, s, client.stop)
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

function C.tickOne(id, entry, now)
    local s, sleeping = C.sessionFor(id)
    if s == nil or sleeping then return end
    if s.exitAt or s.exitRequested or s.detaching then return end
    local vehicle = s.vehicle
    if vehicle == nil then return end
    if entry.halted then
        if s.phase == "driving" and not s.braking then C.stop(s) end
        if s.phase == "seated" then entry.parkedAt = entry.parkedAt or now end
        return
    end
    if s.phase == "driving" then
        entry.parkedAt = nil
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
        -- A driver stuck behind something for a while says so.
        if s.obstacleSince ~= nil and now - s.obstacleSince > 6000 and now >= (entry.blockedSaidAt or 0) then
            entry.blockedSaidAt = now + 30000
            A.Lines.say(C.driverShell(s), "blocked", { uid = s.uid })
        end
        -- Flavour for a player watching the convoy pass.
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
        if now - entry.parkedAt < C.restartDelayMs then return end
        if (s.route ~= nil and #s.route > 0) then
            -- Parked with a queue left (an obstacle or a halt ended): drive on.
            entry.parkedAt = now
            local copy = {}
            for _, p in ipairs(s.route) do copy[#copy + 1] = { x = p.x, y = p.y } end
            C.start(id, copy, speedFor(entry))
            return
        end
        if now >= (entry.nextScoutAt or 0) then
            entry.nextScoutAt = now + 2000
            local points, info = C.legFor(entry, s)
            if points ~= nil then
                entry.parkedAt = now
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
    if ProjectALife == nil or ProjectALife.DrivingDemoClient == nil then return end
    for id, entry in pairs(C.known) do
        local ok, err = pcall(C.tickOne, id, entry, now)
        if not ok then A.fail("convoy tick " .. tostring(id), err) end
    end
end

-- Caravan vehicles within `radius` tiles of a player: rows { vehicle, id, entry, distance }.
function C.near(player, radius)
    local out = {}
    local px, py = A.xyz(player)
    if px == nil or type(getCell) ~= "function" then return out end
    local ok, err = pcall(function()
        local list = getCell():getVehicles()
        if list == nil then return end
        for index = 0, list:size() - 1 do
            local vehicle = list:get(index)
            local id = vehicle ~= nil and vehicle:getId() or nil
            local entry = id ~= nil and C.known[id] or nil
            if entry == nil and id ~= nil then
                local tag = A.vehicleTag(vehicle)
                if tag ~= nil and A.Director ~= nil then entry = C.known[id] end
            end
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
