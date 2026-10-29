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
    local candidates = {}
    local cx, cy = tile(x), tile(y)
    for dx = -radius, radius, 2 do
        for dy = -radius, radius, 2 do
            local px, py = cx + dx, cy + dy
            local d = dx * dx + dy * dy
            if d <= radius * radius and R.farFromPlayers(players, px, py, minPlayer) and R.isRoad(scene, px, py) then
                candidates[#candidates + 1] = { x = px, y = py, d = d }
            end
        end
    end
    table.sort(candidates, function(a, b)
        if a.d ~= b.d then return a.d < b.d end
        if a.x ~= b.x then return a.x < b.x end
        return a.y < b.y
    end)
    local checked = 0
    for _, candidate in ipairs(candidates) do
        checked = checked + 1
        if checked > 160 then break end
        if R.space(scene, candidate.x, candidate.y, true) then
            return { x = candidate.x, y = candidate.y, z = 0 }
        end
    end
    return nil, "no free road tile near " .. tostring(math.floor(x)) .. "," .. tostring(math.floor(y))
end

-- Compress a chain of 4-tile steps to bends plus one point every `spacing` tiles.
function R.compress(chain, maxPoints, spacing)
    maxPoints = math.max(1, math.floor(tonumber(maxPoints) or 12))
    spacing = tonumber(spacing) or 14
    local out = {}
    local anchor = chain[1]
    for index = 2, #chain do
        local previous, current, following = chain[index - 1], chain[index], chain[index + 1]
        local bend = following ~= nil and ((current.x - previous.x) * (following.y - current.y)
            ~= (current.y - previous.y) * (following.x - current.x))
        local last = following == nil
        if last or bend or A.dist(current.x, current.y, anchor.x, anchor.y) >= spacing then
            out[#out + 1] = { x = current.x, y = current.y }
            anchor = current
            if #out >= maxPoints then break end
        end
    end
    return out
end

-- Waypoints from `from` toward `goal` over loaded road. Returns points (possibly
-- empty) and info { reached, distance, nodes, length, reason }.
function R.scout(scene, from, goal, options)
    options = options or {}
    local step = math.max(2, math.floor(options.step or 4))
    local budget = math.max(20, math.floor(options.maxNodes or 600))
    local maxPoints = options.maxPoints or 12
    local arrive = options.arrive or 8
    local start = R.snapRoad(scene, from.x, from.y, options.snapRadius or 8)
    if start == nil then return {}, { reached = false, reason = "start is not on a loaded road", nodes = 0 } end
    local root = { x = start.x, y = start.y, depth = 0, h = A.dist(start.x, start.y, goal.x, goal.y) }
    local open, seen = { root }, { [root.x .. ":" .. root.y] = true }
    local best, expanded = root, 0
    local directions = { { step, 0 }, { 0, step }, { -step, 0 }, { 0, -step } }
    while #open > 0 and expanded < budget do
        local bestIndex = 1
        for index = 2, #open do
            if open[index].h < open[bestIndex].h then bestIndex = index end
        end
        local node = table.remove(open, bestIndex)
        expanded = expanded + 1
        if node.h < best.h or (node.h == best.h and node.depth > best.depth) then best = node end
        if node.h <= arrive then break end
        if node.depth < (options.maxDepth or 240) then
            for _, d in ipairs(directions) do
                local n = { x = node.x + d[1], y = node.y + d[2], parent = node, depth = node.depth + 1 }
                local key = n.x .. ":" .. n.y
                if not seen[key] then
                    seen[key] = true
                    if R.link(scene, node, n) then
                        n.h = A.dist(n.x, n.y, goal.x, goal.y)
                        open[#open + 1] = n
                    end
                end
            end
        end
    end
    local chain = {}
    local node = best
    while node ~= nil do
        table.insert(chain, 1, { x = node.x, y = node.y })
        node = node.parent
    end
    local length = 0
    for index = 2, #chain do length = length + A.dist(chain[index].x, chain[index].y, chain[index - 1].x, chain[index - 1].y) end
    local points = #chain >= 2 and R.compress(chain, maxPoints, options.spacing) or {}
    return points, { reached = best.h <= arrive, distance = best.h, nodes = expanded, length = length,
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
