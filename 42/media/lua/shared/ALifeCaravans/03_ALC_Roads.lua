-- A-Life: Caravans - road scouting. A caravan's long route is a chain of A-Life
-- road-graph towns; the car can only follow waypoints on loaded, paved road.
-- scout() walks the loaded road tiles from a point toward a goal (best-first,
-- 4-tile steps, A-Life's own paved/edge checks) and returns a short waypoint
-- chain: bends and one point every ~14 tiles, at most `maxPoints` of them.

require "ALifeCaravans/00_ALC_Core"

local A = ALifeCaravans
local R = { lastError = nil }
A.Roads = R

local function sites()
    return ProjectALife and ProjectALife.VehicleArrivalSites or nil
end

local function tile(value)
    return math.floor(value) + 0.5
end

function R.scene(player)
    local S = sites()
    if S ~= nil and type(S.context) == "function" then
        local ok, scene = pcall(S.context, player)
        if ok and type(scene) == "table" then return scene end
        R.lastError = scene
    end
    local scene = { squares = {}, edges = {}, bodies = {}, z = 0, players = {}, reserved = {} }
    for _, p in ipairs(A.players()) do
        local x, y = A.xyz(p)
        if x ~= nil then scene.players[#scene.players + 1] = { x = x, y = y } end
    end
    return scene
end

local function checkSquareLoaded(cell, ix, iy)
    return cell:getGridSquare(ix, iy, 0) ~= nil
end

function R.isLoaded(x, y)
    if type(getCell) ~= "function" then return true end
    local okCell, cell = pcall(getCell)
    if not okCell or cell == nil or type(cell.getGridSquare) ~= "function" then return true end
    local ok, loaded = pcall(checkSquareLoaded, cell, math.floor(x), math.floor(y))
    return not ok or loaded == true
end

function R.areaLoaded(x, y, radius)
    if R.isLoaded(x, y) then return true end
    local probe = math.min(24, math.max(8, math.floor((tonumber(radius) or 24) * 0.6)))
    return R.isLoaded(x + probe, y) or R.isLoaded(x - probe, y)
        or R.isLoaded(x, y + probe) or R.isLoaded(x, y - probe)
end

function R.isRoad(scene, x, y)
    local S = sites()
    if S ~= nil and type(S.road) == "function" then
        local ok, road = pcall(S.road, scene, x, y)
        if ok then return road == true end
    end
    local roads = ProjectALife and ProjectALife.Road
    if roads == nil or type(roads.isPavedSurface) ~= "function" or type(getCell) ~= "function" then return false end
    local ok, paved = pcall(function()
        local square = getCell():getGridSquare(math.floor(x), math.floor(y), 0)
        return square ~= nil and square:isOutside() and roads.isPavedSurface(square)
    end)
    return ok and paved == true
end

function R.link(scene, a, b)
    local S = sites()
    if S ~= nil and type(S.link) == "function" then
        local ok, linked = pcall(S.link, scene, a, b)
        if ok then return linked == true end
        return false
    end
    for i = 1, 4 do
        if not R.isRoad(scene, a.x + (b.x - a.x) * i / 4, a.y + (b.y - a.y) * i / 4) then return false end
    end
    return true
end

function R.space(scene, x, y, spawn)
    local S = sites()
    if S ~= nil and type(S.space) == "function" then
        local ok, free = pcall(S.space, scene, x, y, spawn)
        if ok then return free == true end
        return false
    end
    return true
end

-- Nearest paved tile to (x, y) within `radius` tiles, or nil.
function R.snapRoad(scene, x, y, radius)
    radius = math.max(0, math.floor(tonumber(radius) or 8))
    local cx, cy = tile(x), tile(y)
    if R.isRoad(scene, cx, cy) then return { x = cx, y = cy } end
    for ring = 1, radius do
        for dx = -ring, ring do
            for _, dy in ipairs({ -ring, ring }) do
                if R.isRoad(scene, cx + dx, cy + dy) then return { x = cx + dx, y = cy + dy } end
            end
        end
        for dy = -ring + 1, ring - 1 do
            for _, dx in ipairs({ -ring, ring }) do
                if R.isRoad(scene, cx + dx, cy + dy) then return { x = cx + dx, y = cy + dy } end
            end
        end
    end
    return nil
end

function R.farFromPlayers(players, x, y, minimum)
    for _, p in ipairs(players or {}) do
        if A.dist(x, y, p.x, p.y) < minimum then return false end
    end
    return true
end

-- A free paved spawn site near (x, y): on road, space for a car, at least
-- `minPlayer` tiles from every player, nearest to (x, y) first.
function R.siteNear(scene, x, y, players, options)
    options = options or {}
    local radius = math.floor(options.radius or 30)
    local minPlayer = options.minPlayer or A.settings.minSpawnDistance
    local cx, cy = tile(x), tile(y)
    if not R.areaLoaded(cx, cy, radius) then
        return nil, "spawn area not loaded near " .. tostring(math.floor(x)) .. "," .. tostring(math.floor(y))
    end
    local candidates = {}
    for dx = -radius, radius, 2 do
        for dy = -radius, radius, 2 do
            local px, py = cx + dx, cy + dy
            local d = dx * dx + dy * dy
            if d <= radius * radius and R.farFromPlayers(players, px, py, minPlayer)
                    and R.isLoaded(px, py) and R.isRoad(scene, px, py) then
                candidates[#candidates + 1] = { x = px, y = py, d = d }
            end
        end
    end
    table.sort(candidates, function(a, b)
        if a.d ~= b.d then return a.d < b.d end
        if a.x ~= b.x then return a.x < b.x end
        return a.y < b.y
    end)
    local checked, maxChecks = 0, math.floor(options.maxSpaceChecks or 64)
    for _, candidate in ipairs(candidates) do
        checked = checked + 1
        if checked > maxChecks then break end
        if R.space(scene, candidate.x, candidate.y, true) then
            return { x = candidate.x, y = candidate.y, z = 0 }
        end
    end
    return nil, "no free road tile near " .. tostring(math.floor(x)) .. "," .. tostring(math.floor(y))
end

-- Compress a chain of 4-tile steps to significant bends plus one point every `spacing` tiles.
-- Avoids 4-tile staircase zig-zags and merges a short final tail stub into the last waypoint.
function R.compress(chain, maxPoints, spacing)
    maxPoints = math.max(1, math.floor(tonumber(maxPoints) or 12))
    spacing = tonumber(spacing) or 14
    local minBendSpacing = math.min(8, spacing * 0.5)
    local out = {}
    local anchor = chain[1]
    for index = 2, #chain do
        local previous, current, following = chain[index - 1], chain[index], chain[index + 1]
        local bend = following ~= nil and ((current.x - previous.x) * (following.y - current.y)
            ~= (current.y - previous.y) * (following.x - current.x))
        local distFromAnchor = A.dist(current.x, current.y, anchor.x, anchor.y)
        local last = following == nil
        if last then
            if #out > 0 and distFromAnchor < math.max(6, spacing * 0.4) then
                out[#out] = { x = current.x, y = current.y }
            else
                out[#out + 1] = { x = current.x, y = current.y }
            end
            break
        elseif (bend and distFromAnchor >= minBendSpacing) or distFromAnchor >= spacing then
            out[#out + 1] = { x = current.x, y = current.y }
            anchor = current
            if #out >= maxPoints then break end
        end
    end
    return out
end

local function reversesRecentStep(node, dx, dy)
    local anc, steps = node, 0
    while anc ~= nil and steps < 4 do
        if anc.dx ~= nil and (dx * anc.dx + dy * anc.dy) < 0 then return true end
        anc = anc.parent
        steps = steps + 1
    end
    return false
end

local function nodeLess(a, b)
    if a.f ~= b.f then return a.f < b.f end
    return (a.seq or 0) < (b.seq or 0)
end

local function heapPush(heap, node)
    local i = #heap + 1
    while i > 1 do
        local parent = math.floor(i / 2)
        if not nodeLess(node, heap[parent]) then break end
        heap[i] = heap[parent]
        i = parent
    end
    heap[i] = node
end

local function heapPop(heap)
    local first = heap[1]
    local last = table.remove(heap)
    if #heap > 0 then
        local i, n = 1, #heap
        while i * 2 <= n do
            local child = i * 2
            if child < n and nodeLess(heap[child + 1], heap[child]) then child = child + 1 end
            if not nodeLess(heap[child], last) then break end
            heap[i] = heap[child]
            i = child
        end
        heap[i] = last
    end
    return first
end

-- Waypoints from `from` toward `goal` over loaded road. Returns points (possibly
-- empty) and info { reached, distance, nodes, length, reason }.
function R.scout(scene, from, goal, options)
    options = options or {}
    local step = math.max(2, math.floor(options.step or 4))
    local budget = math.max(20, math.floor(options.maxNodes or 240))
    local maxMs = tonumber(options.maxMs) or 6
    local startedMs = A.now()
    local maxPoints = options.maxPoints or 12
    local arrive = options.arrive or 8
    local heading = type(options.heading) == "number" and options.heading or nil
    local hx, hy = heading and math.cos(heading) or nil, heading and math.sin(heading) or nil
    local start = R.snapRoad(scene, from.x, from.y, options.snapRadius or 8)
    if start == nil then return {}, { reached = false, reason = "start is not on a loaded road", nodes = 0 } end
    local rootH = A.dist(start.x, start.y, goal.x, goal.y)
    local seq = 1
    local root = { x = start.x, y = start.y, depth = 0, g = 0, h = rootH, f = rootH, seq = seq,
        dx = hx and (hx * step) or nil, dy = hy and (hy * step) or nil }
    local open, seen = { root }, { [root.x .. ":" .. root.y] = 0 }
    local best, anyBest, forwardBest, forwardScore, anyForwardBest, anyForwardScore, expanded =
        root, root, nil, math.huge, nil, math.huge, 0
    local hitUnloaded = false
    local directions = { { step, 0 }, { 0, step }, { -step, 0 }, { 0, -step } }
    while #open > 0 and expanded < budget do
        if expanded > 0 and expanded % 16 == 0 and (A.now() - startedMs) >= maxMs
                and (forwardBest ~= nil or best ~= root or anyBest ~= root) then
            break
        end
        local node = heapPop(open)
        local keyHere = node.x .. ":" .. node.y
        if seen[keyHere] == nil or node.g <= seen[keyHere] + 0.001 then
            expanded = expanded + 1
            if node.h < anyBest.h or (node.h == anyBest.h and node.depth > anyBest.depth) then anyBest = node end
            if (node.backtrackPenalty or 0) == 0 or best == root then
                if node.h < best.h or (node.h == best.h and node.depth > best.depth) then best = node end
            end
            if node.depth >= 3 then
                local score = node.h - node.depth * step * 0.45 + (node.backtrackPenalty or 0)
                if score < forwardScore then
                    forwardScore = score
                    forwardBest = node
                end
                local rawScore = node.h - node.depth * step * 0.45
                if rawScore < anyForwardScore then
                    anyForwardScore = rawScore
                    anyForwardBest = node
                end
            end
            if node.h <= arrive then break end
            if node.depth < (options.maxDepth or 240) then
                for _, d in ipairs(directions) do
                    if not reversesRecentStep(node, d[1], d[2]) then
                        local nx, ny = node.x + d[1], node.y + d[2]
                        local h = A.dist(nx, ny, goal.x, goal.y)
                        if not R.isLoaded(nx, ny) then
                            if h < node.h then hitUnloaded = true end
                        else
                            local turnCost = (node.dx ~= nil and (node.dx ~= d[1] or node.dy ~= d[2])) and 1.5 or 0
                            local backPenalty = node.backtrackPenalty or 0
                            local stepPenalty = 0
                            if hx ~= nil and node.depth <= 2 then
                                local dot = (d[1] * hx + d[2] * hy) / step
                                if dot < -0.25 then
                                    stepPenalty = 24
                                    backPenalty = math.max(backPenalty, 24)
                                elseif node.depth == 0 and dot < 0.2 then
                                    stepPenalty = 4
                                    backPenalty = math.max(backPenalty, 4)
                                end
                            end
                            local g = (node.g or 0) + step + turnCost + stepPenalty
                            local key = nx .. ":" .. ny
                            if seen[key] == nil or g < seen[key] then
                                if R.link(scene, node, { x = nx, y = ny }) then
                                    seen[key] = g
                                    seq = seq + 1
                                    heapPush(open, {
                                        x = nx, y = ny, parent = node, depth = node.depth + 1,
                                        dx = d[1], dy = d[2], g = g, h = h, f = g * 0.35 + h,
                                        backtrackPenalty = backPenalty, seq = seq,
                                    })
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    local chosen = best
    if not hitUnloaded and chosen.h > arrive and ((rootH - chosen.h) < 12 or (chosen.backtrackPenalty or 0) >= 24)
            and forwardBest ~= nil and forwardBest.depth > chosen.depth then
        chosen = forwardBest
    end
    if not hitUnloaded and chosen == root and hx ~= nil then
        if anyBest ~= root then
            chosen = anyBest
            if chosen.h > arrive and (rootH - chosen.h) < 12
                    and anyForwardBest ~= nil and anyForwardBest.depth > chosen.depth then
                chosen = anyForwardBest
            end
        elseif not options.noFallback then
            local fallbackOpts = {}
            for k, v in pairs(options) do fallbackOpts[k] = v end
            fallbackOpts.heading = nil
            fallbackOpts.noFallback = true
            return R.scout(scene, from, goal, fallbackOpts)
        end
    end
    local chain = {}
    local node = chosen
    while node ~= nil do
        table.insert(chain, 1, { x = node.x, y = node.y })
        node = node.parent
    end
    local length = 0
    for index = 2, #chain do length = length + A.dist(chain[index].x, chain[index].y, chain[index - 1].x, chain[index - 1].y) end
    local points = #chain >= 2 and R.compress(chain, maxPoints, options.spacing) or {}
    return points, { reached = chosen.h <= arrive, distance = chosen.h, nodes = expanded, length = length,
        reason = #points == 0 and "no road leads on from here" or nil }
end

-- A second car's start: `gap` tiles behind `site`, away from the first waypoint.
function R.behind(scene, site, firstPoint, gap, players, minPlayer)
    local dx, dy = firstPoint.x - site.x, firstPoint.y - site.y
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 1 then return nil end
    dx, dy = dx / length, dy / length
    for distance = gap, gap + 8, 2 do
        local x, y = tile(site.x - dx * distance), tile(site.y - dy * distance)
        if R.isRoad(scene, x, y) and R.space(scene, x, y, true) and R.farFromPlayers(players, x, y, minPlayer or 0)
                and R.link(scene, { x = x, y = y }, { x = site.x, y = site.y }) then
            return { x = x, y = y, z = 0 }
        end
    end
    return nil
end

return R
