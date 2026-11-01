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

function R.tick(c, now)
    if not A.authority() then return false end
    if c.state ~= "defeated" then
        if not R.allDead(c) then return false end
        c.state, c.defeatedAtMs = "defeated", now
        c.halted, c.haltUntilMs, c.haltReason = nil, nil, nil
        c.recrew, c.escort, c.stock, c.ambush = nil, nil, {}, nil
        if A.SOS then A.SOS.finish(c, false, "lost") end
        A.Director.publishDirty = true
        A.Ledger.touch()
        A.log(c.id, "crew defeated; preserving cars and loot")
    end
    if now < (c.cleanupAtMs or 0) then return true end
    c.cleanupAtMs = now + 2000
    local pending = false
    for id, car in pairs(ownedCars(c)) do
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
