-- A-Life: Caravans - generic vehicle choice. No vanilla script names are
-- hard-coded as requirements: cars come from the game's own vehicle zone
-- distributions (VehicleZoneDistribution, which vehicle mods extend), then from
-- name patterns over every loaded vehicle script, then from whatever drivable
-- script exists. A script is usable when it is loaded, has a driver seat and at
-- least one passenger seat, four or more wheels, and is not a wreck or trailer.

require "ALifeCaravans/00_ALC_Core"

local A = ALifeCaravans
local V = { scanned = nil, scannedAtMs = -1 }
A.Vehicles = V

V.badPatterns = { "Burnt", "Smashed", "Trailer", "Wreck", "Destroyed", "Crashed", "Rusty", "Junk", "Broken" }

-- Faction class -> preferred zone keys (in order) and name patterns.
V.classes = {
    military = {
        zones = { "military", "army", "militarybase", "fortredstone" },
        patterns = { "M998", "M923", "M35", "Humvee", "Hummer", "Military", "Army", "APC", "Jeep", "MilTruck", "Truck_Army" },
        fallback = { "Base.PickUpTruck_Camo", "Base.OffRoad", "Base.PickUpVan" },
    },
    police = {
        zones = { "police", "prison", "ranger" },
        patterns = { "Police", "Sheriff", "Ranger", "Prison", "Patrol", "Interceptor", "Cruiser" },
        fallback = { "Base.CarLightsPolice", "Base.PickUpVanLightsPolice", "Base.CarNormal" },
    },
    rescue = {
        zones = { "ambulance", "fire" },
        patterns = { "Ambulance", "Fire", "Rescue", "Medical", "EMS", "Paramedic" },
        fallback = { "Base.Ambulance", "Base.PickUpVanLightsFire", "Base.Van" },
    },
    trade = {
        zones = { "delivery", "trades", "business", "postal", "farm", "transit", "knoxdisti" },
        patterns = { "StepVan", "Van", "Truck", "PickUp", "Wagon", "Delivery", "Cargo", "Box", "Lorry" },
        fallback = { "Base.StepVan", "Base.PickUpTruck", "Base.VanSeats", "Base.CarStationWagon" },
    },
    raider = {
        zones = { "bad", "junkyard", "struggling", "trailerpark" },
        patterns = { "PickUp", "OffRoad", "Van", "Muscle", "Pickup", "Truck", "4x4" },
        fallback = { "Base.PickUpTruck", "Base.OffRoad", "Base.PickUpVan", "Base.CarNormal" },
    },
    civilian = {
        zones = { "good", "medium", "middleClass", "parkingstall", "professional" },
        patterns = { "Car", "Wagon", "Van", "Sedan", "Modern" },
        fallback = { "Base.CarStationWagon", "Base.CarNormal", "Base.VanSeats", "Base.PickUpVan" },
    },
}

local function nameOf(script)
    local ok, name = pcall(function() return script:getFullName() end)
    if ok and type(name) == "string" and name ~= "" then return name end
    ok, name = pcall(function() return script:getName() end)
    if ok and type(name) == "string" and name ~= "" then return name end
    return nil
end

local function numberOf(script, method, default)
    local ok, value = pcall(function() return script[method](script) end)
    if ok and type(value) == "number" then return value end
    return default
end

local function badName(name)
    for _, pattern in ipairs(V.badPatterns) do
        if string.find(name, pattern, 1, true) then return true end
    end
    return false
end

-- Rows { name, seats, mass, wheels } of every usable vehicle script.
function V.scan(force)
    if V.scanned ~= nil and not force then return V.scanned end
    local rows, byName = {}, {}
    local ok, err = pcall(function()
        if type(getScriptManager) ~= "function" then return end
        local manager = getScriptManager()
        if manager == nil or type(manager.getAllVehicleScripts) ~= "function" then return end
        local list = manager:getAllVehicleScripts()
        if list == nil then return end
        for index = 0, list:size() - 1 do
            local script = list:get(index)
            local name = script ~= nil and nameOf(script) or nil
            if name ~= nil and not badName(name) then
                local seats = numberOf(script, "getPassengerCount", 0)
                local wheels = numberOf(script, "getWheelCount", 0)
                local mass = numberOf(script, "getMass", 0)
                if seats >= 2 and wheels >= 4 then
                    local row = { name = name, seats = seats, mass = mass, wheels = wheels }
                    rows[#rows + 1] = row
                    byName[name] = row
                end
            end
        end
    end)
    if not ok then A.fail("vehicle scan", err) end
    V.scanned = { rows = rows, byName = byName }
    V.scannedAtMs = A.now()
    return V.scanned
end

function V.row(name)
    local scan = V.scan()
    return scan.byName[name]
end

function V.valid(name)
    if type(name) ~= "string" then return false end
    if V.row(name) ~= nil then return true end
    local ok, script = pcall(function() return getScriptManager():getVehicle(name) end)
    return ok and script ~= nil
end

function V.seats(name)
    local row = V.row(name)
    if row ~= nil then return row.seats end
    local ok, count = pcall(function() return getScriptManager():getVehicle(name):getPassengerCount() end)
    if ok and type(count) == "number" then return count end
    return 2
end

-- Weighted rows from the game's zone distributions (vehicle mods add theirs there).
function V.fromZones(zones)
    local out = {}
    local table_ = type(VehicleZoneDistribution) == "table" and VehicleZoneDistribution or nil
    if table_ == nil then return out end
    for _, zone in ipairs(zones or {}) do
        local entry = table_[zone]
        local vehicles = type(entry) == "table" and type(entry.vehicles) == "table" and entry.vehicles or nil
        if vehicles ~= nil then
            for name, spec in pairs(vehicles) do
                if type(name) == "string" and V.valid(name) then
                    local weight = type(spec) == "table" and tonumber(spec.spawnChance) or 1
                    if weight > 0 then out[#out + 1] = { name = name, weight = weight } end
                end
            end
        end
    end
    return out
end

function V.fromPatterns(patterns)
    local out = {}
    for _, row in ipairs(V.scan().rows) do
        for _, pattern in ipairs(patterns or {}) do
            if string.find(row.name, pattern, 1, true) then
                out[#out + 1] = { name = row.name, weight = 1 }
                break
            end
        end
    end
    return out
end

local function weighted(rows, fraction)
    local total = 0
    for _, row in ipairs(rows) do total = total + row.weight end
    if total <= 0 then return nil end
    local needle = math.max(0, math.min(0.999999, tonumber(fraction) or A.randFloat())) * total
    for _, row in ipairs(rows) do
        needle = needle - row.weight
        if needle < 0 then return row.name end
    end
    return rows[#rows].name
end

-- Faction -> vehicle class, from A-Life's bloc of the faction and its support doctrine.
function V.classFor(faction)
    local bloc
    local rules = ProjectALife and ProjectALife.FactionSpawnRules
    if rules ~= nil and type(rules.blocOf) == "function" then
        local ok, value = pcall(rules.blocOf, faction)
        if ok and value ~= nil then bloc = tostring(value) end
    end
    if bloc == nil and type(faction) == "table" and type(faction.relations) == "table" then
        bloc = faction.relations.bloc
    end
    bloc = bloc and string.lower(tostring(bloc)) or ""
    if bloc == "military" or bloc == "elite" or bloc == "army" then return "military" end
    if bloc == "law" or bloc == "police" then return "police" end
    if bloc == "rescue" or bloc == "medical" or bloc == "fire" then return "rescue" end
    if bloc == "crime" or bloc == "gang" or bloc == "raider" or bloc == "club" or bloc == "prison" then return "raider" end
    local hint = type(faction) == "table" and type(faction.support) == "table" and faction.support.vehicle or nil
    hint = hint and string.lower(tostring(hint)) or ""
    if hint == "workvan" or hint == "truck" or hint == "pickup" then return "trade" end
    if bloc == "trade" or bloc == "work" or bloc == "labor" or bloc == "industry" or bloc == "commune" then return "trade" end
    return "civilian"
end

-- A usable vehicle script for a class; never nil while any drivable script exists.
function V.pick(class, fraction)
    local spec = V.classes[class] or V.classes.civilian
    local name = weighted(V.fromZones(spec.zones), fraction)
    if name == nil then name = weighted(V.fromPatterns(spec.patterns), fraction) end
    if name == nil then
        for _, candidate in ipairs(spec.fallback) do
            if V.valid(candidate) then name = candidate break end
        end
    end
    if name == nil then
        local support = ProjectALife and ProjectALife.Support
        local aliases = support and support.settings and support.settings.vehicleAliases or nil
        if type(aliases) == "table" then
            for _, candidate in pairs(aliases) do
                if V.valid(candidate) then name = candidate break end
            end
        end
    end
    if name == nil then
        local rows = V.scan().rows
        if #rows > 0 then name = rows[A.rand(#rows) + 1].name end
    end
    return name
end

-- Scripts for a caravan: up to four cars (two A-Life arrival units). A military
-- or police convoy fills the maximum; others take enough cars for the crew.
function V.convoy(class, crewCount, maxVehicles)
    local scripts = {}
    local seatsTotal = 0
    local limit = math.max(1, math.min(4, math.floor(tonumber(maxVehicles) or 2)))
    local fill = class == "military" or class == "police"
    for index = 1, limit do
        if index > 1 and not fill and seatsTotal >= crewCount then break end
        local name = V.pick(class, A.randFloat())
        if name == nil then break end
        scripts[#scripts + 1] = name
        seatsTotal = seatsTotal + V.seats(name)
    end
    return scripts, seatsTotal
end

return V
