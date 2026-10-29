-- A-Life: Caravans - shared core. One global table, ALifeCaravans.
-- Nothing here touches Project A-Life at load time; everything is installed at
-- OnGameStart / OnServerStarted (server/ALifeCaravans/ALC_Boot.lua).
-- Global settings live in the host's Sandbox options, page "A-Life: Caravans"
-- (SandboxVars.ALifeCaravans); per-player ones in Options > Mods.

ALifeCaravans = ALifeCaravans or {}
local A = ALifeCaravans

A.MOD_ID = "ALifeCaravans"
A.VERSION = "0.1.0"
A.TAG = "[ALC]"
A.MODULE = "ALifeCaravans"        -- client<->server command module name
A.MODDATA_ID = "ALifeCaravanId"   -- vehicle ModData key (authoritative side only)

-- Defaults = the Sandbox defaults in 42/media/sandbox-options.txt.
A.defaults = {
    enabled = true,
    maxCaravans = 3,
    foundIntervalMinutes = 8,     -- real minutes between new caravans
    cruiseKmh = 35,               -- convoy cruising speed
    crewMin = 3,
    crewMax = 5,
    maxVehicles = 2,              -- A-Life arrivals support at most two cars per crew
    renderRadius = 100,           -- a caravan this close to a player drives for real
    releaseRadius = 170,          -- this far from every player it goes back to the ledger
    minSpawnDistance = 45,        -- never materialise closer than this to a player
    offlineSpeedPercent = 25,     -- ledger travel speed as % of the cruise speed (stops, detours)
    tripsPerCaravan = 2,          -- town-to-town trips before the caravan is retired
    haltSeconds = 120,            -- how long a flagged-down caravan waits
    hornHails = true,
    allowHostile = true,          -- raider/gang caravans (toll, ambush)
    allowRiders = true,           -- players may hitch a ride
    tradeEnabled = true,
    debug = false,
}
A.settings = A.settings or {}
for key, value in pairs(A.defaults) do A.settings[key] = value end

A.metrics = {
    founded = 0, rendered = 0, renderRefused = 0, released = 0, retired = 0, legs = 0, halts = 0,
    hails = 0, trades = 0, rides = 0, tolls = 0, fights = 0, flights = 0, lines = 0, errors = 0,
}

function A.now()
    if type(getTimestampMs) == "function" then return getTimestampMs() end
    return math.floor(os.time() * 1000)
end

function A.log(...)
    local parts = { A.TAG }
    for index = 1, select("#", ...) do parts[#parts + 1] = tostring(select(index, ...)) end
    print(table.concat(parts, " "))
end

function A.debug(...)
    if A.settings.debug then A.log(...) end
end

function A.fail(where, err)
    A.metrics.errors = A.metrics.errors + 1
    A.log(where, "failed:", err)
end

function A.rand(n)
    n = math.max(1, math.floor(tonumber(n) or 1))
    if type(ZombRand) == "function" then return ZombRand(n) end
    return math.random(0, n - 1)
end

function A.randFloat()
    if type(ZombRandFloat) == "function" then return ZombRandFloat(0, 1) end
    return A.rand(1000000) / 1000000
end

function A.pick(list)
    if type(list) ~= "table" or #list == 0 then return nil end
    return list[A.rand(#list) + 1]
end

function A.side()
    local server = type(isServer) == "function" and isServer() == true
    local client = type(isClient) == "function" and isClient() == true
    if server then return "server" end
    if client then return "client" end
    return "singleplayer"
end

-- The side that owns the world: single player, or the server. Server Lua also
-- runs on a multiplayer client, where this is false.
function A.authority()
    return A.side() ~= "client"
end

-- The side that drives NPC cars: single player, or a multiplayer client.
function A.drivingSide()
    return A.side() ~= "server"
end

function A.xyz(body)
    if body == nil or type(body.getX) ~= "function" then return nil end
    local ok, x, y, z = pcall(function() return body:getX(), body:getY(), body:getZ() end)
    if not ok or type(x) ~= "number" or type(y) ~= "number" then return nil end
    return x, y, type(z) == "number" and z or 0
end

function A.dist(x1, y1, x2, y2)
    local dx, dy = (x1 or 0) - (x2 or 0), (y1 or 0) - (y2 or 0)
    return math.sqrt(dx * dx + dy * dy)
end

function A.copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, item in pairs(value) do out[key] = A.copy(item) end
    return out
end

function A.clamp(value, low, high, default)
    value = tonumber(value)
    if value == nil or value ~= value then return default end
    return math.max(low, math.min(high, value))
end

-- Replace tbl[name] with factory(original). False when there is nothing to wrap.
A.wrapped = A.wrapped or {}
function A.wrap(tbl, name, factory, label)
    label = label or name
    if type(tbl) ~= "table" or type(tbl[name]) ~= "function" then
        A.log("hook skipped:", label)
        return false
    end
    if A.wrapped[label] ~= nil then return true end
    local original = tbl[name]
    tbl[name] = factory(original)
    A.wrapped[label] = original
    return true
end

-- Sandbox options (host page) -> A.settings. Polled by the boot file: B42 has
-- no Lua event for a sandbox change, so admins can edit them in a running game.
function A.refreshSettings()
    local sandbox = type(SandboxVars) == "table" and SandboxVars.ALifeCaravans or nil
    local s = A.settings
    local d = A.defaults
    if type(sandbox) ~= "table" then
        for key, value in pairs(d) do s[key] = value end
        return false
    end
    s.enabled = sandbox.Enabled ~= false
    s.maxCaravans = A.clamp(sandbox.MaxCaravans, 1, 8, d.maxCaravans)
    s.foundIntervalMinutes = A.clamp(sandbox.FoundIntervalMinutes, 1, 60, d.foundIntervalMinutes)
    s.cruiseKmh = A.clamp(sandbox.CruiseKmh, 10, 70, d.cruiseKmh)
    s.crewMin = A.clamp(sandbox.CrewMin, 2, 8, d.crewMin)
    s.crewMax = math.max(s.crewMin, A.clamp(sandbox.CrewMax, 2, 8, d.crewMax))
    s.maxVehicles = A.clamp(sandbox.MaxVehicles, 1, 2, d.maxVehicles)
    s.renderRadius = A.clamp(sandbox.RenderRadius, 60, 200, d.renderRadius)
    s.releaseRadius = math.max(s.renderRadius + 30, A.clamp(sandbox.ReleaseRadius, 90, 300, d.releaseRadius))
    s.minSpawnDistance = A.clamp(sandbox.MinSpawnDistance, 25, 90, d.minSpawnDistance)
    s.offlineSpeedPercent = A.clamp(sandbox.OfflineSpeedPercent, 5, 100, d.offlineSpeedPercent)
    s.tripsPerCaravan = A.clamp(sandbox.TripsPerCaravan, 1, 10, d.tripsPerCaravan)
    s.haltSeconds = A.clamp(sandbox.HaltSeconds, 30, 600, d.haltSeconds)
    s.hornHails = sandbox.HornHails ~= false
    s.allowHostile = sandbox.AllowHostile ~= false
    s.allowRiders = sandbox.AllowRiders ~= false
    s.tradeEnabled = sandbox.TradeEnabled ~= false
    s.debug = sandbox.Debug == true
    return true
end

-- Vehicle tag (authoritative side; vehicle ModData does not reach MP clients).
function A.tagVehicle(vehicle, caravanId, index)
    local ok = pcall(function()
        local data = vehicle:getModData()
        data[A.MODDATA_ID] = caravanId
        data.ALifeCaravanIndex = index
    end)
    return ok
end

function A.vehicleTag(vehicle)
    if vehicle == nil or type(vehicle.getModData) ~= "function" then return nil end
    local ok, id, index = pcall(function()
        local data = vehicle:getModData()
        return data[A.MODDATA_ID], data.ALifeCaravanIndex
    end)
    if ok and type(id) == "string" then return id, index end
    return nil
end

function A.players()
    local out = {}
    local ok = pcall(function()
        if type(getOnlinePlayers) == "function" and (A.side() ~= "singleplayer") then
            local list = getOnlinePlayers()
            for index = 0, list:size() - 1 do out[#out + 1] = list:get(index) end
        end
    end)
    if (not ok or #out == 0) and type(getSpecificPlayer) == "function" then
        for index = 0, 3 do
            local ok2, player = pcall(getSpecificPlayer, index)
            if ok2 and player ~= nil then out[#out + 1] = player end
        end
    end
    if #out == 0 and type(getPlayer) == "function" then
        local ok3, player = pcall(getPlayer)
        if ok3 and player ~= nil then out[#out + 1] = player end
    end
    return out
end

function A.playerKey(player)
    local speech = ProjectALife and ProjectALife.Speech
    if speech ~= nil and type(speech.playerKey) == "function" then
        local ok, key = pcall(speech.playerKey, player)
        if ok and key ~= nil then return tostring(key) end
    end
    local ok, name = pcall(function() return player:getUsername() end)
    if ok and name ~= nil then return tostring(name) end
    return "sp:0"
end

function A.counters()
    local m = A.metrics
    return "founded=" .. m.founded .. " rendered=" .. m.rendered .. " refused=" .. m.renderRefused
        .. " released=" .. m.released .. " retired=" .. m.retired .. " legs=" .. m.legs .. " halts=" .. m.halts
        .. " hails=" .. m.hails .. " trades=" .. m.trades .. " rides=" .. m.rides .. " tolls=" .. m.tolls
        .. " fights=" .. m.fights .. " flights=" .. m.flights .. " lines=" .. m.lines .. " errors=" .. m.errors
end

-- Console helper: ALifeCaravans.status()
function A.status()
    A.log("v" .. A.VERSION, "side=" .. A.side(), "enabled=" .. tostring(A.settings.enabled))
    A.log(A.counters())
    for label in pairs(A.wrapped) do A.log("wrapped", label) end
    if A.Director ~= nil and type(A.Director.describe) == "function" then
        for _, line in ipairs(A.Director.describe()) do A.log(line) end
    end
end

return A
