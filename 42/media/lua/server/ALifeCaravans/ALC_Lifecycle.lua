-- Defeat is independent of parking, combat, and driving-session recovery.
-- Never turn absent/dormant replicas into deaths; never delete loot vehicles.
require "ALifeCaravans/00_ALC_Core"
local A = ALifeCaravans
local R = {}
A.Lifecycle = R

function R.allDead(c)
    local registry = ProjectALife and ProjectALife.ActorRegistry
    if not registry or #(c.actorUids or {}) == 0 then return false end
    for _, uid in ipairs(c.actorUids) do
        local ok, actor = pcall(registry.read, uid)
        if not ok or not actor or actor.lifecycle ~= "dead" then return false end
    end
    return true
end

function R.visible(c)
    return c ~= nil and c.state ~= "defeated" and c.state ~= "stranded"
        and not c.defeatedAtMs and not R.allDead(c)
end

-- Rescan tags as saved Java vehicle IDs may be recycled after loading.
local function ownedCars(c)
    local found = {}
    local function add(car)
        if car and A.vehicleTag(car) == c.id then found[car:getId()] = car end
    end
    for _, ids in ipairs({c.vehicleIds or {}, c.abandoned or {}}) do
        for _, id in ipairs(ids) do
            local car = type(getVehicleById) == "function" and getVehicleById(id)
            local _, session = A.Spawn.sessionOf(id)
            add(car)
            -- An unloaded original may still be held by a sleeping binding.
            if not car and session then add(session.vehicle) end
        end
    end
    local cell = type(getCell) == "function" and getCell()
    if cell and type(cell.getVehicles) == "function" then
        local cars = cell:getVehicles()
        if cars and type(cars.iterator) == "function" then
            local it = cars:iterator()
            while it:hasNext() do add(it:next()) end
        end
    end
    return found
end

function R.applyDefeatWear(car, c)
    if not car then return false end
    local ok, applied = pcall(function()
        local data = type(car.getModData) == "function" and car:getModData() or nil
        if type(data) == "table" and data.ALC_DefeatWearApplied == true then return false end
        if type(data) == "table" then data.ALC_DefeatWearApplied = true end
        local maxCond = A.clamp(A.settings and A.settings.trophyVehicleCondition, 10, 100, 40)
        if maxCond >= 100 then return false end
        local scriptName = nil
        if type(car.getScript) == "function" then
            local s = car:getScript()
            if s ~= nil then
                if type(s.getFullName) == "function" then scriptName = s:getFullName() end
                if (scriptName == nil or scriptName == "") and type(s.getName) == "function" then scriptName = s:getName() end
            end
        end
        local armored = A.Vehicles and type(A.Vehicles.isArmoredVehicle) == "function"
            and A.Vehicles.isArmoredVehicle(scriptName) == true
        local cap = armored and math.max(10, math.floor(maxCond * 0.75)) or maxCond
        local floorCond = math.max(8, math.floor(cap * 0.45))
        local span = math.max(1, cap - floorCond + 1)
        local count = type(car.getPartCount) == "function" and car:getPartCount() or 0
        for index = 0, count - 1 do
            local part = car:getPartByIndex(index)
            if part ~= nil and type(part.getCondition) == "function" and type(part.setCondition) == "function" then
                local current = tonumber(part:getCondition()) or 100
                local target = floorCond + A.rand(span)
                local nextCond = math.min(current, target)
                part:setCondition(nextCond)
                local item = type(part.getInventoryItem) == "function" and part:getInventoryItem() or nil
                if item ~= nil and type(item.setCondition) == "function" then
                    item:setCondition(nextCond)
                    if type(part.doInventoryItemStats) == "function" and type(part.getMechanicSkillInstaller) == "function" then
                        pcall(part.doInventoryItemStats, part, item, part:getMechanicSkillInstaller())
                    end
                end
                local id = type(part.getId) == "function" and part:getId() or ""
                if id == "Battery" and item ~= nil and type(item.setUsedDelta) == "function" then
                    local maxDelta = math.max(0.10, math.min(1.0, 0.35 * (cap / 100)))
                    local curDelta = (type(item.getUsedDelta) == "function" and tonumber(item:getUsedDelta())) or 1.0
                    item:setUsedDelta(math.min(curDelta, maxDelta))
                end
                if type(car.transmitPartCondition) == "function" then pcall(car.transmitPartCondition, car, part) end
                if type(car.transmitPartItem) == "function" then pcall(car.transmitPartItem, car, part) end
            end
        end
        local tank = type(car.getPartById) == "function" and car:getPartById("GasTank") or nil
        if tank ~= nil and type(tank.getContainerCapacity) == "function" and type(tank.setContainerContentAmount) == "function" then
            local capacity = tonumber(tank:getContainerCapacity()) or 0
            local currentFuel = (type(tank.getContainerContentAmount) == "function" and tonumber(tank:getContainerContentAmount())) or capacity
            if capacity > 0 then
                local maxFuel = capacity * math.max(0.08, 0.25 * (cap / 100))
                tank:setContainerContentAmount(math.min(currentFuel, maxFuel))
                if type(car.transmitPartModData) == "function" then pcall(car.transmitPartModData, car, tank) end
            end
        end
        if type(car.updatePartStats) == "function" then pcall(car.updatePartStats, car) end
        if type(car.updateBulletStats) == "function" then pcall(car.updateBulletStats, car) end
        return true
    end)
    return ok and applied == true
end

function R.tick(c, now)
    if not A.authority() then return false end
    if c.state ~= "defeated" then
        if not R.allDead(c) then return false end
        c.state, c.defeatedAtMs = "defeated", now
        c.halted, c.haltUntilMs, c.haltReason = nil, nil, nil
        c.recrew, c.escort, c.stock, c.ambush = nil, nil, {}, nil
        if A.SOS then A.SOS.finish(c, false, "lost") end
        for _, car in pairs(ownedCars(c)) do
            R.applyDefeatWear(car, c)
        end
        A.Director.publishDirty = true
        A.Ledger.touch()
        A.log(c.id, "crew defeated; preserving cars and loot")
    end
    if now < (c.cleanupAtMs or 0) then return true end
    c.cleanupAtMs = now + 2000
    local pending = false
    for id, car in pairs(ownedCars(c)) do
        R.applyDefeatWear(car, c)
        -- A player's occupied car remains untouched until they leave it.
        if A.vehicleHasPlayer(car) then pending = true
        elseif A.Spawn.releaseCar(id, c.id) then
            A.tagVehicle(car, nil, nil)
        else pending = true end
    end
    if not pending then
        A.Ledger.remove(c.id)
        A.Director.publishDirty = true
    end
    return true
end

return R
