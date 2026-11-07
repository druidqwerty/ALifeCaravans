-- A-Life: Caravans - physical trunk cargo & roadside field services (server / SP).
-- Populates caravan vehicle trunks with physical items, detects unauthorized trunk
-- looting on non-hostile convoys, and implements interactive roadside services:
--   * assist_repair    - repair/refuel a halted or broken-down caravan car for pay & favor
--   * field_aid        - medical treatment / bandaging from rescue & medical_aid convoys
--   * donate_supplies  - supply relief for refugee / struggling convoys for high favor
--   * vehicle_service  - fuel top-up & engine patch for the player's nearby car
--   * road_intel       - tactical briefing on active convoys, events, and SOS calls

require "ALifeCaravans/00_ALC_Core"
require "ALifeCaravans/01_ALC_Lines"
require "ALifeCaravans/05_ALC_Trade"
require "ALifeCaravans/07_ALC_Market"
require "ALifeCaravans/ALC_Ledger"

local A = ALifeCaravans
local K = { serviceCooldownMs = 120000 }
A.Cargo = K

function K.trunkContainer(car)
    if car == nil or type(car.getPartById) ~= "function" then return nil end
    for _, id in ipairs({ "TruckBed", "TruckBedOpen", "Trunk", "TrailerTrunk" }) do
        local ok, part = pcall(car.getPartById, car, id)
        if ok and part ~= nil and type(part.getItemContainer) == "function" then
            local okC, container = pcall(part.getItemContainer, part)
            if okC and container ~= nil then return container, part end
        end
    end
    return nil
end

function K.countContainerItems(container)
    if container == nil or type(container.getItems) ~= "function" then return 0 end
    local ok, items = pcall(container.getItems, container)
    if ok and items ~= nil and type(items.size) == "function" then
        return items:size()
    end
    return 0
end

-- Populate physical trunk cargo for a spawned caravan car from the caravan's stock.
function K.populateCar(car, caravan, carIndex)
    if not A.settings.caravanCargo or car == nil or type(caravan) ~= "table" then return 0 end
    local container = K.trunkContainer(car)
    if container == nil or type(container.AddItem) ~= "function" then return 0 end
    local stock = caravan.stock or {}
    if #stock == 0 then return 0 end
    local added = 0
    local startIdx = ((tonumber(carIndex) or 1) - 1) * 2 + 1
    for offset = 0, 2 do
        local row = stock[((startIdx + offset - 1) % #stock) + 1]
        if row and type(row.item) == "string" and A.Trade.exists(row.item) then
            local qty = math.max(1, math.min(2, math.ceil((tonumber(row.count) or 1) * 0.5)))
            for _ = 1, qty do
                local ok, item = pcall(container.AddItem, container, row.item)
                if ok and item ~= nil then added = added + 1 end
            end
        end
    end
    pcall(function()
        local data = car:getModData()
        if data then data.ALifeCargoCount = K.countContainerItems(container) end
    end)
    return added
end

-- Detect if a player looted items from a living caravan's trunk without trading.
function K.checkTheft(caravan, cars, players)
    if not A.settings.caravanCargo or type(caravan) ~= "table" or caravan.state ~= "rendered" then return false end
    for _, row in ipairs(cars or {}) do
        local car = row.vehicle
        if car ~= nil then
            local container = K.trunkContainer(car)
            if container ~= nil then
                local current = K.countContainerItems(container)
                local expected = nil
                pcall(function()
                    local data = car:getModData()
                    expected = data and tonumber(data.ALifeCargoCount) or nil
                    if data and expected ~= nil and current > expected then
                        data.ALifeCargoCount = current
                        expected = current
                    end
                end)
                if expected ~= nil and current < expected then
                    pcall(function() car:getModData().ALifeCargoCount = current end)
                    A.metrics.lostCargo = (A.metrics.lostCargo or 0) + (expected - current)
                    local thief = nil
                    local bestD = 8.0
                    for _, pl in ipairs(players or {}) do
                        local d = A.dist(pl.x, pl.y, row.x, row.y)
                        if d <= bestD then thief, bestD = pl.player, d end
                    end
                    if thief ~= nil and A.Interact and type(A.Interact.onAttacked) == "function" then
                        local leader = A.Interact.leaderActor(caravan) or { uid = caravan.actorUids and caravan.actorUids[1] }
                        pcall(A.Interact.onAttacked, thief, leader)
                        return true
                    end
                end
            end
        end
    end
    return false
end

function K.needsRepairOrFuel(caravan)
    if type(caravan) ~= "table" then return false end
    if caravan.haltReason == "roadside_inspection" or caravan.maintenanceVehicleId ~= nil then return true, "breakdown" end
    for _, id in ipairs(caravan.vehicleIds or {}) do
        local car = type(getVehicleById) == "function" and getVehicleById(id) or nil
        if car ~= nil and A.vehicleTag(car) == caravan.id then
            local fuel, engine = A.Spawn.carHealth(car)
            if fuel <= 0.45 or engine == false then return true, "fuel" end
        end
    end
    return false
end

-- Player helps repair or refuel a halted/broken-down caravan car.
function K.assistRepair(caravan, player, vehicleId)
    if not A.settings.fieldServices or caravan.state ~= "rendered" then return false, "unavailable" end
    local I = A.Interact
    if I.stanceFor(caravan, player) == "hostile" then return false, "hostile" end
    local items = A.Trade.inventoryItems(player)
    local fuelCandidate, toolCandidate = nil, nil
    local tools = {
        ["Base.Wrench"] = true, ["Base.LugWrench"] = true, ["Base.Screwdriver"] = true,
        ["Base.Hammer"] = true, ["Base.Crowbar"] = true, ["Base.DuctTape"] = true,
    }
    for _, entry in ipairs(items) do
        if entry.type == "Base.PetrolCan" and not fuelCandidate then fuelCandidate = entry end
        if tools[entry.type] and not toolCandidate then toolCandidate = entry end
    end
    if not fuelCandidate and not toolCandidate then
        I.say(caravan, "repair_need_tools", player, I.vars(caravan, player))
        I.reply(player, "serviceNotice", { key = "repair_need_tools" })
        return false, "missing_tools"
    end
    if fuelCandidate and not toolCandidate then
        local paid = A.Trade.exchange(player, {
            giveRows = { { type = "Base.PetrolCan", count = 1 } },
            takeRows = { { item = "Base.EmptyPetrolCan", count = 1 }, { item = A.Trade.currency, count = 75 } },
        })
        if not paid then return false, "exchange_failed" end
    else
        local paid = A.Trade.exchange(player, {
            giveRows = {},
            takeRows = { { item = A.Trade.currency, count = 60 } },
        })
        if not paid then return false, "exchange_failed" end
    end
    for _, id in ipairs(caravan.vehicleIds or {}) do
        local car = type(getVehicleById) == "function" and getVehicleById(id) or nil
        if car ~= nil and A.vehicleTag(car) == caravan.id then
            pcall(function()
                local tank = car:getPartById("GasTank")
                if tank then tank:setContainerContentAmount(math.max(tank:getContainerContentAmount(), tank:getContainerCapacity() * 0.8)) end
                local engine = car:getPartById("Engine")
                if engine and type(engine.setCondition) == "function" then
                    engine:setCondition(math.max(engine:getCondition() or 50, 75))
                end
            end)
        end
    end
    caravan.maintenanceVehicleId = nil
    local key = A.playerKey(player)
    A.Ledger.addFavor(key, caravan.factionId, 2)
    A.metrics.repairs = (A.metrics.repairs or 0) + 1
    I.say(caravan, "repair_thanks", player, I.vars(caravan, player))
    I.reply(player, "serviceNotice", { key = "repair_done", vars = { favor = "+2" } })
    if caravan.halted and caravan.haltReason == "roadside_inspection" then
        A.Director.resume(caravan)
    end
    A.Director.publishDirty = true
    A.Ledger.touch()
    return true
end

-- Medical field aid from rescue/medical_aid/friendly convoys.
function K.fieldFirstAid(caravan, player, vehicleId)
    if not A.settings.fieldServices or caravan.state ~= "rendered" or not caravan.halted then return false, "not_halted" end
    local I = A.Interact
    local stance = I.stanceFor(caravan, player)
    if stance == "hostile" or caravan.kind == "raid" then return false, "hostile" end
    local key = A.playerKey(player)
    local now = A.now()
    caravan.serviceAt = caravan.serviceAt or {}
    if now < (caravan.serviceAt["aid:" .. key] or 0) then
        I.reply(player, "serviceNotice", { key = "service_cooldown" })
        return false, "cooldown"
    end
    local favor = A.Ledger.favor(key, caravan.factionId)
    local isMedic = caravan.kind == "rescue" or caravan.eventType == "medical_aid"
    local free = stance == "friendly" or favor >= 3 or caravan.eventType == "medical_aid"
    local fee = free and 0 or (isMedic and 20 or 35)
    if fee > 0 then
        local paid = A.Trade.exchange(player, {
            giveRows = { { type = A.Trade.currency, count = fee } },
            takeRows = { { item = "Base.Bandage", count = 2 }, { item = "Base.Pills", count = 1 } },
        })
        if not paid then
            I.say(caravan, "trade_broke", player, I.vars(caravan, player))
            I.reply(player, "serviceNotice", { key = "service_need_cash", vars = { price = fee } })
            return false, "short"
        end
    else
        A.Trade.exchange(player, { giveRows = {}, takeRows = { { item = "Base.Bandage", count = 2 } } })
    end
    pcall(function()
        if type(player.getBodyDamage) == "function" then
            local bd = player:getBodyDamage()
            if bd ~= nil and type(bd.getBodyParts) == "function" then
                local parts = bd:getBodyParts()
                for i = 0, parts:size() - 1 do
                    local bp = parts:get(i)
                    if bp ~= nil then
                        if type(bp.bleeding) == "function" and bp:bleeding() and type(bp.setBandaged) == "function" then
                            bp:setBandaged(true, 80, false, "Base.Bandage")
                        end
                        if type(bp.getAdditionalPain) == "function" and type(bp.setAdditionalPain) == "function" then
                            bp:setAdditionalPain(math.max(0, bp:getAdditionalPain() * 0.4))
                        end
                    end
                end
            end
        end
    end)
    caravan.serviceAt["aid:" .. key] = now + K.serviceCooldownMs
    A.metrics.services = (A.metrics.services or 0) + 1
    I.say(caravan, "aid_done", player, I.vars(caravan, player))
    I.reply(player, "serviceNotice", { key = "aid_done" })
    return true
end

-- Donate supplies to refugees or struggling convoys for Favor + reward.
function K.donateSupplies(caravan, player, vehicleId)
    if not A.settings.fieldServices or caravan.state ~= "rendered" or not caravan.halted then return false, "not_halted" end
    local I = A.Interact
    if I.stanceFor(caravan, player) == "hostile" then return false, "hostile" end
    local key = A.playerKey(player)
    local now = A.now()
    caravan.serviceAt = caravan.serviceAt or {}
    if now < (caravan.serviceAt["donate:" .. key] or 0) then
        I.reply(player, "serviceNotice", { key = "service_cooldown" })
        return false, "cooldown"
    end
    local items = A.Trade.inventoryItems(player)
    local picked = nil
    for _, entry in ipairs(items) do
        local cat = A.Market.categoryOf(entry.type)
        if (cat == "food" or cat == "medical") and entry.type ~= A.Trade.currency then
            picked = entry.type
            break
        end
    end
    if picked == nil then
        I.reply(player, "serviceNotice", { key = "donate_need_supplies" })
        return false, "no_supplies"
    end
    local rewardItem = caravan.eventType == "refugees" and "Base.FirstAidKit" or A.Trade.currency
    local rewardCount = rewardItem == A.Trade.currency and 45 or 1
    local ok = A.Trade.exchange(player, {
        giveRows = { { type = picked, count = 1 } },
        takeRows = { { item = rewardItem, count = rewardCount } },
    })
    if not ok then return false, "exchange_failed" end
    local favorGain = caravan.eventType == "refugees" and 3 or 2
    A.Ledger.addFavor(key, caravan.factionId, favorGain)
    caravan.serviceAt["donate:" .. key] = now + K.serviceCooldownMs
    A.metrics.services = (A.metrics.services or 0) + 1
    I.say(caravan, "give_supplies", player, I.vars(caravan, player))
    I.reply(player, "serviceNotice", { key = "donate_done", vars = { favor = "+" .. tostring(favorGain) } })
    A.Ledger.touch()
    return true
end

-- Roadside mechanic service for the player's own nearby vehicle.
function K.servicePlayerVehicle(caravan, player, vehicleId)
    if not A.settings.fieldServices or caravan.state ~= "rendered" or not caravan.halted then return false, "not_halted" end
    local I = A.Interact
    local stance = I.stanceFor(caravan, player)
    if stance == "hostile" or caravan.kind == "raid" then return false, "hostile" end
    local px, py = A.xyz(player)
    local playerCar = nil
    pcall(function()
        playerCar = player:getVehicle()
        if playerCar ~= nil and A.vehicleTag(playerCar) ~= nil then playerCar = nil end
        if playerCar == nil and type(getCell) == "function" then
            local list = getCell():getVehicles()
            local it = list and list:iterator()
            local bestD = 22
            while it and it:hasNext() do
                local v = it:next()
                if v ~= nil and A.vehicleTag(v) == nil then
                    local vx, vy = A.xyz(v)
                    local d = (vx and px) and A.dist(px, py, vx, vy) or math.huge
                    if d < bestD then playerCar, bestD = v, d end
                end
            end
        end
    end)
    if playerCar == nil then
        I.reply(player, "serviceNotice", { key = "vehicle_service_none" })
        return false, "no_player_car"
    end
    local key = A.playerKey(player)
    local favor = A.Ledger.favor(key, caravan.factionId)
    local fee = favor >= 6 and 0 or 40
    if fee > 0 then
        local paid = A.Trade.exchange(player, {
            giveRows = { { type = A.Trade.currency, count = fee } },
            takeRows = {},
        })
        if not paid then
            I.say(caravan, "trade_broke", player, I.vars(caravan, player))
            I.reply(player, "serviceNotice", { key = "service_need_cash", vars = { price = fee } })
            return false, "short"
        end
    end
    pcall(function()
        local tank = playerCar:getPartById("GasTank")
        if tank then
            local cap = tonumber(tank:getContainerCapacity()) or 40
            local cur = tonumber(tank:getContainerContentAmount()) or 0
            tank:setContainerContentAmount(math.min(cap, cur + math.max(8, cap * 0.3)))
        end
        for _, partId in ipairs({ "Engine", "Battery", "Muffler" }) do
            local part = playerCar:getPartById(partId)
            if part and type(part.getCondition) == "function" and type(part.setCondition) == "function" then
                part:setCondition(math.min(100, (tonumber(part:getCondition()) or 50) + 20))
            end
        end
    end)
    A.metrics.services = (A.metrics.services or 0) + 1
    I.say(caravan, "vehicle_service_done", player, I.vars(caravan, player))
    I.reply(player, "serviceNotice", { key = "vehicle_service_done" })
    return true
end

-- Tactical road intel briefing from convoy/patrol/friendly leaders.
function K.requestIntel(caravan, player, vehicleId)
    if not A.settings.fieldServices or caravan.state ~= "rendered" then return false, "unavailable" end
    local I = A.Interact
    if I.stanceFor(caravan, player) == "hostile" then return false, "hostile" end
    local activeCount, eventCount, sosCount = 0, 0, 0
    for _, c in ipairs(A.Ledger.list()) do
        if A.Lifecycle.visible(c) then
            activeCount = activeCount + 1
            if c.eventType then eventCount = eventCount + 1 end
            if A.SOS and A.SOS.active(c) then sosCount = sosCount + 1 end
        end
    end
    A.metrics.services = (A.metrics.services or 0) + 1
    I.say(caravan, "intel_report", player, {
        count = tostring(activeCount), events = tostring(eventCount), sos = tostring(sosCount),
        dest = tostring(caravan.destName or "?"),
    })
    I.reply(player, "serviceNotice", {
        key = "intel_shared",
        vars = { count = activeCount, events = eventCount, sos = sosCount },
    })
    A.Director.sendState(player)
    return true
end

return K
