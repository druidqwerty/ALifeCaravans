-- A-Life: Caravans - regional town supply & demand economy (server / SP).
-- Tracks 5 survival categories across RoadGraph towns, routes supply shipments
-- toward shortages, exposes destination market snapshots for dynamic barter
-- pricing, and settles remaining cargo into town reserves upon real arrival.

require "ALifeCaravans/00_ALC_Core"
require "ALifeCaravans/05_ALC_Trade"
require "ALifeCaravans/07_ALC_Market"
require "ALifeCaravans/ALC_Ledger"

local A = ALifeCaravans
local E = { maxSupply = 24, defaultSupply = 10 }
A.Economy = E

local REPRESENTATIVE_ITEMS = {
    medical = "Base.Bandage",
    food = "Base.TinnedBeans",
    ammo = "Base.Bullets9mmBox",
    fuel = "Base.PetrolCan",
    tools = "Base.Wrench",
}

local function currentCycle()
    local day, hour = 1, 12
    if A.Director and type(A.Director.clock) == "function" then
        day, hour = A.Director.clock()
    end
    local totalHours = math.max(0, (tonumber(day) or 1) - 1) * 24 + (tonumber(hour) or 12)
    return math.floor(totalHours / 6)
end

function E.store()
    local root = A.Ledger.open()
    if type(root.economy) ~= "table" or root.economy.version ~= 1 then
        root.economy = { version = 1, towns = {}, settled = {}, settledOrder = {} }
    end
    root.economy.towns = root.economy.towns or {}
    root.economy.settled = root.economy.settled or {}
    root.economy.settledOrder = root.economy.settledOrder or {}
    return root.economy
end

function E.ensureTown(nodeId)
    if nodeId == nil then return nil end
    local key = tostring(nodeId)
    local eco = E.store()
    local town = eco.towns[key]
    local cats = A.Market.categories
    local cycle = currentCycle()
    if type(town) ~= "table" or type(town.supplies) ~= "table" then
        local h = A.hash("alc-town:" .. key)
        local produces = cats[(h % #cats) + 1]
        local consumes = cats[((h + 2) % #cats) + 1]
        local supplies = {}
        for i, cat in ipairs(cats) do
            local seedVal = 7 + ((h + i * 17) % 10)
            if cat == produces then seedVal = 18 end
            if cat == consumes then seedVal = 3 end
            supplies[cat] = A.clamp(seedVal, 0, E.maxSupply, E.defaultSupply)
        end
        town = { id = key, produces = produces, consumes = consumes, supplies = supplies, cycle = cycle }
        eco.towns[key] = town
        return town
    end
    local delta = math.max(0, math.min(4, cycle - (tonumber(town.cycle) or cycle)))
    if delta > 0 then
        town.cycle = cycle
        for _ = 1, delta do
            if town.produces and town.supplies[town.produces] ~= nil then
                town.supplies[town.produces] = math.min(E.maxSupply, town.supplies[town.produces] + 2)
            end
            if town.consumes and town.supplies[town.consumes] ~= nil then
                town.supplies[town.consumes] = math.max(0, town.supplies[town.consumes] - 1)
            end
        end
    end
    return town
end

function E.marketFor(G, nodeId)
    if nodeId == nil then return nil end
    local town = E.ensureTown(nodeId)
    if town == nil then return nil end
    local tiers = {}
    local shortage, shortageAmt = nil, math.huge
    local surplus, surplusAmt = nil, -1
    for _, cat in ipairs(A.Market.categories) do
        local amt = tonumber(town.supplies[cat]) or E.defaultSupply
        local tier = A.Market.tierForSupply(amt)
        tiers[cat] = tier
        if tier == "scarce" and amt < shortageAmt then
            shortage, shortageAmt = cat, amt
        end
        if tier == "abundant" and amt > surplusAmt then
            surplus, surplusAmt = cat, amt
        end
    end
    local townName = (A.Director and G and type(A.Director.nodeName) == "function") and A.Director.nodeName(G, nodeId) or tostring(nodeId)
    return {
        townId = tostring(nodeId),
        townName = townName,
        shortage = shortage,
        surplus = surplus,
        tiers = tiers,
        supplies = A.copy(town.supplies),
    }
end

-- Score a route by whether its destination has a shortage the origin can supply.
function E.scoreRoute(G, route)
    if type(route) ~= "table" or #route < 2 then return 0 end
    local fromTown = E.ensureTown(route[1])
    local destTown = E.ensureTown(route[#route])
    if not fromTown or not destTown then return 0 end
    local score = 0
    for _, cat in ipairs(A.Market.categories) do
        local dAmt = tonumber(destTown.supplies[cat]) or 10
        local sAmt = tonumber(fromTown.supplies[cat]) or 10
        if dAmt <= 5 then
            score = score + (6 - dAmt) * 3
            if sAmt >= 12 then score = score + 8 end
        end
    end
    return score
end

-- Attach destination market snapshot and inject shipment cargo for a caravan trip.
function E.prepareTrip(G, caravan)
    if type(caravan) ~= "table" then return end
    local route = caravan.route or {}
    local destId = route[#route]
    if destId == nil or not A.settings.economyEnabled then
        caravan.market = nil
        return
    end
    local market = E.marketFor(G, destId)
    caravan.market = market
    if caravan.hostile or caravan.kind == "raid" or market == nil or market.shortage == nil then return end
    local fromId = route[1]
    local fromTown = fromId and E.ensureTown(fromId) or nil
    local item = REPRESENTATIVE_ITEMS[market.shortage]
    if item == nil or not A.Trade.exists(item) then return end
    local withdraw = 3
    if fromTown and (tonumber(fromTown.supplies[market.shortage]) or 0) >= 6 then
        withdraw = math.min(4, math.floor(fromTown.supplies[market.shortage] / 3))
        fromTown.supplies[market.shortage] = math.max(0, fromTown.supplies[market.shortage] - withdraw)
    end
    caravan.stock = caravan.stock or {}
    local merged = false
    for _, row in ipairs(caravan.stock) do
        if row.item == item then
            row.count = math.min(A.Trade.maxCount * 2, row.count + withdraw)
            merged = true
            break
        end
    end
    if not merged and #caravan.stock < 12 then
        caravan.stock[#caravan.stock + 1] = {
            item = item, name = A.Trade.name(item), value = A.Trade.valueOf(item), count = withdraw,
        }
    end
end

-- Settle delivered caravan stock into the destination town's reserves (idempotent per caravan+trip).
function E.settleArrival(G, caravan)
    if type(caravan) ~= "table" or not A.settings.economyEnabled or caravan.hostile or caravan.kind == "raid" then return false end
    local route = caravan.route or {}
    local destId = route[#route]
    if destId == nil then return false end
    local eco = E.store()
    local receiptKey = tostring(caravan.id or "?") .. ":" .. tostring(caravan.trip or 1)
    if eco.settled[receiptKey] then return false end
    eco.settled[receiptKey] = true
    eco.settledOrder[#eco.settledOrder + 1] = receiptKey
    while #eco.settledOrder > 120 do
        local oldKey = table.remove(eco.settledOrder, 1)
        if oldKey then eco.settled[oldKey] = nil end
    end
    local town = E.ensureTown(destId)
    if town == nil then return false end
    local delivered = 0
    for _, row in ipairs(caravan.stock or {}) do
        local cat = A.Market.categoryOf(row.item)
        local count = tonumber(row.count) or 0
        if cat and count > 0 and town.supplies[cat] ~= nil then
            local add = math.min(6, math.ceil(count * 0.5))
            town.supplies[cat] = math.min(E.maxSupply, town.supplies[cat] + add)
            delivered = delivered + add
        end
    end
    if delivered > 0 then
        A.metrics.deliveries = (A.metrics.deliveries or 0) + 1
        A.Ledger.touch()
    end
    return delivered > 0, delivered
end

return E
