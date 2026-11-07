-- A-Life: Caravans - ballistic and weapon hit handling for seated caravan crews.
-- Seated IsoZombie-backed NPCs require crash-damage exemption (setGodMod) while
-- inside a vehicle so vanilla BaseVehicle.addRandomDamageFromCrash does not NPE
-- on null BodyDamage. This module restores realistic firearm/melee damage against
-- seated NPCs through vehicle windows/doors and triggers caravan combat reactions.

require "ALifeCaravans/00_ALC_Core"
require "ALifeCaravans/06_ALC_Physics"

local A = ALifeCaravans
local B = { lastShotAtMs = {} }
A.Ballistics = B

local function P() return ProjectALife end

local function getHealth(npc)
    local p = P()
    if p and p.ShellSimulation and type(p.ShellSimulation.trueHealth) == "function" then
        local ok, h = pcall(p.ShellSimulation.trueHealth, npc)
        if ok and type(h) == "number" then return h end
    end
    if type(npc.getHealth) == "function" then
        local ok, h = pcall(npc.getHealth, npc)
        if ok and type(h) == "number" then return h end
    end
    return 1.0
end

local function setHealth(npc, value)
    local p = P()
    if p and p.ShellSimulation and type(p.ShellSimulation.setHealth) == "function" then
        pcall(p.ShellSimulation.setHealth, npc, value)
    end
    if type(npc.setHealth) == "function" then
        pcall(npc.setHealth, npc, value)
    end
end

-- Check and damage the passenger door/window for `seat`. Returns penetration factor (0..1).
function B.penetrateSeat(car, seat, rawDamage)
    local factor = 0.85
    pcall(function()
        if type(car.getPassengerDoor) ~= "function" then return end
        local part = car:getPassengerDoor(seat)
        if part == nil then return end
        local door = type(part.getDoor) == "function" and part:getDoor() or nil
        if door ~= nil and type(door.isOpen) == "function" and door:isOpen() then
            factor = 1.0
            return
        end
        local win = type(part.findWindow) == "function" and part:findWindow() or nil
        if win ~= nil then
            local destroyed = type(win.isDestroyed) == "function" and win:isDestroyed() or false
            if not destroyed then
                local cond = type(win.getCondition) == "function" and win:getCondition() or 100
                if cond > 0 then
                    local nextCond = math.max(0, cond - math.floor(35 + rawDamage * 25))
                    if type(win.setCondition) == "function" then win:setCondition(nextCond) end
                    factor = 0.45
                    return
                end
            end
            factor = 0.9
            return
        end
        local cond = type(part.getCondition) == "function" and part:getCondition() or 100
        if cond > 0 and type(part.setCondition) == "function" then
            part:setCondition(math.max(0, cond - math.floor(15 + rawDamage * 15)))
            factor = 0.55
        end
    end)
    return factor
end

-- Find seated caravan crew in `car`, ordered by closeness to player.
function B.seatedTargets(caravan, car, px, py)
    local targets = {}
    local p = P()
    local registry = p and p.ActorRegistry
    local owned = {}
    for _, uid in ipairs(caravan.actorUids or {}) do owned[uid] = true end
    pcall(function()
        local seats = type(car.getMaxPassengers) == "function" and car:getMaxPassengers() or 0
        for seat = 0, math.max(0, seats - 1) do
            local body = car:getCharacter(seat)
            if body ~= nil and not instanceof(body, "IsoPlayer") and not body:isDead() then
                local data = type(body.getModData) == "function" and body:getModData() or nil
                local uid = data and data.ProjectALifeUID or nil
                if uid == nil or owned[uid] then
                    local actor = (uid and registry and type(registry.read) == "function") and registry.read(uid) or { uid = uid or caravan.actorUids[1] }
                    local bx, by = A.xyz(body)
                    local d = (bx and px) and A.dist(px, py, bx, by) or (seat + 1)
                    targets[#targets + 1] = { body = body, seat = seat, uid = uid, actor = actor, dist = d }
                end
            end
        end
    end)
    table.sort(targets, function(a, b) return a.dist < b.dist end)
    return targets
end

function B.onShot(player, args)
    if not A.authority() or player == nil or type(args) ~= "table" or player:isDead() then return false, "invalid" end
    local key = A.playerKey(player)
    local now = A.now()
    if now < (B.lastShotAtMs[key] or 0) + 90 then return false, "cooldown" end
    B.lastShotAtMs[key] = now
    local vehicleId = tonumber(args.vehicleId)
    if vehicleId == nil then return false, "no_vehicle_id" end
    local caravan = A.Ledger and A.Ledger.byVehicle(vehicleId) or nil
    local car = type(getVehicleById) == "function" and getVehicleById(vehicleId) or nil
    if caravan == nil or car == nil or A.vehicleTag(car) ~= caravan.id then return false, "no_caravan_car" end
    local px, py = A.xyz(player)
    local cx, cy = A.xyz(car)
    if px == nil or cx == nil or A.dist(px, py, cx, cy) > 48 then return false, "out_of_range" end
    local targets = B.seatedTargets(caravan, car, px, py)
    if #targets == 0 then
        local leader = A.Interact and A.Interact.leaderActor(caravan) or nil
        if leader and A.Interact and type(A.Interact.onAttacked) == "function" then
            pcall(A.Interact.onAttacked, player, leader)
        end
        return false, "no_seated_crew"
    end
    local target = targets[1]
    local body, seat, actor = target.body, target.seat, target.actor
    local rawDamage = A.clamp(args.damage, 0.2, 4.0, 1.0)
    local penetration = B.penetrateSeat(car, seat, rawDamage)
    local effDamage = math.max(0.18, math.min(1.5, rawDamage * 0.55 * penetration))
    -- Temporarily lift crash guard to apply ballistic damage, then restore if still seated & alive.
    if type(body.setGodMod) == "function" then pcall(body.setGodMod, body, false, true) end
    local health = getHealth(body)
    local remaining = math.max(0, health - effDamage)
    setHealth(body, remaining)
    A.metrics.shots = (A.metrics.shots or 0) + 1
    local p = P()
    local rep = p and p.Reputation
    if remaining <= 0 then
        pcall(function()
            if type(car.exitRSync) == "function" and body:getVehicle() == car then
                car:exitRSync(body)
            end
            if type(car.clearPassenger) == "function" and seat ~= nil and seat >= 0 then
                if type(car.getCharacter) ~= "function" or car:getCharacter(seat) == body then
                    car:clearPassenger(seat)
                end
            end
            if type(body.setVehicle) == "function" and body:getVehicle() == car then
                body:setVehicle(nil)
            end
        end)
        if type(body.Kill) == "function" then
            if not pcall(body.Kill, body, player) then pcall(body.Kill, body, nil) end
        end
        if rep and actor and type(rep.onPlayerKilledActor) == "function" then
            pcall(rep.onPlayerKilledActor, player, actor)
        end
        if A.Interact and actor and type(A.Interact.onAttacked) == "function" then
            pcall(A.Interact.onAttacked, player, actor)
        end
        A.log(caravan.id, "seated crew", tostring(target.uid), "killed in car", vehicleId, "by", key)
        return true, "killed", remaining
    else
        A.Physics.syncBodyCrashGuard(body, car, true)
        if rep and actor and type(rep.onPlayerDamagedActor) == "function" then
            pcall(rep.onPlayerDamagedActor, player, actor)
        end
        if A.Interact and actor and type(A.Interact.onAttacked) == "function" then
            pcall(A.Interact.onAttacked, player, actor)
        end
        return true, "damaged", remaining
    end
end

-- Client/SP aim detector: checks if a player's attack aims at a caravan car.
function B.findAimedCaravanVehicle(player, weapon)
    if player == nil or A.Convoy == nil then return nil end
    local px, py = A.xyz(player)
    if px == nil then return nil end
    local maxRange = 28
    local isRanged = true
    local rawDamage = 1.0
    pcall(function()
        if weapon ~= nil then
            if type(weapon.isRanged) == "function" then isRanged = weapon:isRanged() == true end
            if type(weapon.getMaxRange) == "function" then maxRange = math.max(2.5, math.min(45, tonumber(weapon:getMaxRange()) or 28)) end
            if type(weapon.getMaxDamage) == "function" then rawDamage = tonumber(weapon:getMaxDamage()) or 1.0 end
        end
    end)
    if not isRanged then maxRange = math.min(maxRange, 3.8) end
    local fx, fy = nil, nil
    pcall(function()
        if type(player.getForwardDirection) == "function" then
            local dir = player:getForwardDirection()
            if dir ~= nil and type(dir.getX) == "function" then
                fx, fy = dir:getX(), dir:getY()
            end
        end
        if (fx == nil or (fx == 0 and fy == 0)) and type(player.getDirectionAngle) == "function" then
            local rad = math.rad(player:getDirectionAngle())
            fx, fy = math.cos(rad), math.sin(rad)
        end
    end)
    local rows = A.Convoy.near(player, maxRange)
    for _, row in ipairs(rows) do
        local vx, vy = A.xyz(row.vehicle)
        if vx ~= nil then
            local dx, dy = vx - px, vy - py
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist <= 3.2 then
                return row.id, rawDamage, isRanged
            elseif fx ~= nil and dist <= maxRange and dist > 0.01 then
                local along = dx * fx + dy * fy
                local across = math.abs(-dx * fy + dy * fx)
                if along > 0 and across <= math.max(2.4, dist * 0.24) then
                    return row.id, rawDamage, isRanged
                end
            end
        end
    end
    return nil
end

return B
