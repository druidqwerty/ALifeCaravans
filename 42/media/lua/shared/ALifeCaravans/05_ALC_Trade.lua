-- A-Life: Caravans - barter. Pure rules shared by the server (authority: stock,
-- favor, transaction validation) and the client (the trade window shows the
-- same quote). A caravan's stock comes from its kind (military: ammo, medical,
-- rations; traders: wide; rescue: medical; patrol: a little of everything;
-- raiders: stolen goods at a markup) and refreshes every trip. Players pay with
-- cash or any goods the caravan values; favor earned by fair trades and escorts
-- lowers prices, threats and attacks raise them.

require "ALifeCaravans/00_ALC_Core"

local A = ALifeCaravans
local T = { currency = "Base.Money", maxStock = 8, maxCount = 6 }
A.Trade = T

-- Explicit values (cash units) for the goods caravans carry and common barter.
T.values = {
    ["Base.Money"] = 1, ["Base.Cigarettes"] = 12, ["Base.TinnedBeans"] = 15, ["Base.CannedCornedBeef"] = 18,
    ["Base.CannedTomato"] = 12, ["Base.CannedChili"] = 15, ["Base.CannedBolognese"] = 15, ["Base.CannedSardines"] = 14,
    ["Base.WaterBottleFull"] = 8, ["Base.WaterBottle"] = 3, ["Base.Bandage"] = 10, ["Base.Antibiotics"] = 60,
    ["Base.Pills"] = 20, ["Base.PillsAntiDep"] = 25, ["Base.Disinfectant"] = 25, ["Base.FirstAidKit"] = 80,
    ["Base.SutureNeedle"] = 30, ["Base.Splint"] = 15, ["Base.PetrolCan"] = 45, ["Base.EmptyPetrolCan"] = 8,
    ["Base.Bullets9mmBox"] = 50, ["Base.Bullets45Box"] = 50, ["Base.Bullets38Box"] = 45, ["Base.Bullets44Box"] = 55,
    ["Base.ShotgunShellsBox"] = 55, ["Base.556Box"] = 70, ["Base.308Box"] = 70, ["Base.223Box"] = 65,
    ["Base.Axe"] = 70, ["Base.Hammer"] = 25, ["Base.Nails"] = 10, ["Base.Rope"] = 20, ["Base.Saw"] = 30,
    ["Base.Crowbar"] = 45, ["Base.Screwdriver"] = 15, ["Base.Wrench"] = 20, ["Base.DuctTape"] = 15,
    ["Base.Seeds_PotatoBag"] = 18, ["Base.Seeds_CabbageBag"] = 15, ["Base.MRE"] = 20, ["Base.CannedFruitCocktail"] = 12,
    ["Base.Battery"] = 12, ["Base.Torch"] = 25, ["Base.Radio.WalkieTalkie4"] = 90, ["Base.Generator"] = 250,
    ["Base.Vest_BulletArmy"] = 150, ["Base.Hat_Army"] = 25, ["Base.Whiskey"] = 30, ["Base.Wine"] = 18,
    ["Base.Coffee"] = 20, ["Base.Sugar"] = 10, ["Base.Rice"] = 12, ["Base.Pasta"] = 10, ["Base.Flour"] = 10,
    ["Base.Pistol"] = 120, ["Base.Shotgun"] = 160, ["Base.HuntingRifle"] = 180, ["Base.BaseballBat"] = 30,
    ["Base.Machete"] = 80, ["Base.HuntingKnife"] = 35, ["Base.Sheet"] = 5, ["Base.Soap2"] = 6, ["Base.Lighter"] = 8,
}

-- Fallback values by the game's display/type category.
T.categoryValues = {
    Ammo = 25, Weapon = 60, Food = 10, FirstAid = 20, Medical = 20, Tool = 25, Fuel = 45, Material = 8,
    Clothing = 10, Literature = 5, Electronics = 20, Container = 30, Bag = 30, Junk = 2, Household = 6,
    Camping = 20, Cooking = 8, Furniture = 10, Gardening = 12, Instrument = 40, Entertainment = 5,
    Communications = 60, Light = 15, Accessory = 10, Memento = 3, Sport = 8,
}
T.untradable = { Key = true, Corpse = true, Animal = true, Fishing = false }

-- Goods per caravan kind: { item, count range }. Missing items are skipped.
T.stock = {
    trade = {
        { "Base.TinnedBeans", 2, 4 }, { "Base.CannedCornedBeef", 1, 3 }, { "Base.CannedTomato", 1, 3 }, { "Base.CannedChili", 1, 2 },
        { "Base.WaterBottleFull", 2, 4 }, { "Base.Bandage", 2, 4 }, { "Base.Antibiotics", 1, 1 }, { "Base.Pills", 1, 2 },
        { "Base.PetrolCan", 1, 2 }, { "Base.Bullets9mmBox", 1, 2 }, { "Base.ShotgunShellsBox", 1, 1 }, { "Base.Cigarettes", 2, 4 },
        { "Base.Axe", 1, 1 }, { "Base.Hammer", 1, 1 }, { "Base.Nails", 1, 2 }, { "Base.Rope", 1, 2 }, { "Base.Saw", 1, 1 },
        { "Base.Seeds_PotatoBag", 1, 1 }, { "Base.Coffee", 1, 1 }, { "Base.Rice", 1, 2 }, { "Base.Battery", 1, 3 },
        { "Base.Torch", 1, 1 }, { "Base.Whiskey", 1, 1 }, { "Base.DuctTape", 1, 1 },
    },
    convoy = {
        { "Base.556Box", 1, 2 }, { "Base.Bullets9mmBox", 1, 2 }, { "Base.308Box", 1, 1 }, { "Base.FirstAidKit", 1, 1 },
        { "Base.Bandage", 2, 4 }, { "Base.MRE", 2, 4 }, { "Base.WaterBottleFull", 2, 3 }, { "Base.PetrolCan", 1, 1 },
        { "Base.Hat_Army", 1, 1 }, { "Base.Radio.WalkieTalkie4", 1, 1 }, { "Base.Antibiotics", 1, 1 },
    },
    patrol = {
        { "Base.Bullets9mmBox", 1, 2 }, { "Base.ShotgunShellsBox", 1, 1 }, { "Base.Bandage", 1, 2 }, { "Base.WaterBottleFull", 1, 2 },
        { "Base.Cigarettes", 1, 2 }, { "Base.Coffee", 1, 1 }, { "Base.Torch", 1, 1 }, { "Base.Battery", 1, 2 },
    },
    rescue = {
        { "Base.Bandage", 3, 6 }, { "Base.FirstAidKit", 1, 1 }, { "Base.Pills", 1, 3 }, { "Base.Antibiotics", 1, 2 },
        { "Base.WaterBottleFull", 2, 3 }, { "Base.Disinfectant", 1, 2 }, { "Base.SutureNeedle", 1, 1 }, { "Base.Splint", 1, 2 },
        { "Base.PillsAntiDep", 1, 1 },
    },
    raid = {
        { "Base.Cigarettes", 2, 4 }, { "Base.Whiskey", 1, 2 }, { "Base.Pistol", 1, 1 }, { "Base.Bullets9mmBox", 1, 2 },
        { "Base.Machete", 1, 1 }, { "Base.PetrolCan", 1, 1 }, { "Base.Generator", 1, 1 }, { "Base.Vest_BulletArmy", 1, 1 },
        { "Base.CannedCornedBeef", 1, 2 }, { "Base.Crowbar", 1, 1 },
    },
}

-- Raiders sell dear and pay little; everyone else trades at value, paying 75 % for your goods.
T.rates = {
    trade = { sell = 1.0, buy = 0.75 }, convoy = { sell = 1.1, buy = 0.7 }, patrol = { sell = 1.0, buy = 0.7 },
    rescue = { sell = 0.9, buy = 0.75 }, raid = { sell = 1.5, buy = 0.5 },
}

local function script(fullType)
    local ok, item = pcall(function()
        local manager = getScriptManager()
        if type(manager.getItem) == "function" then return manager:getItem(fullType) end
        if type(manager.FindItem) == "function" then return manager:FindItem(fullType) end
        return nil
    end)
    if ok then return item end
    return nil
end

function T.exists(fullType)
    if type(fullType) ~= "string" or fullType == "" then return false end
    if type(getScriptManager) ~= "function" then return true end
    return script(fullType) ~= nil
end

function T.name(fullType)
    local ok, name = pcall(function() return getItemNameFromFullType(fullType) end)
    if ok and type(name) == "string" and name ~= "" then return name end
    return (string.gsub(tostring(fullType), "^Base%.", ""))
end

local function read(object, method)
    if object == nil then return nil end
    -- Java item subclasses do not share every getter. Kahlua logs a missing
    -- method exception even when pcall catches it, once per inventory item.
    local getter = object[method]
    if type(getter) ~= "function" then return nil end
    local ok, value = pcall(getter, object)
    if ok then return value end
    return nil
end

-- Cash value of one item of a type (explicit table, then the game's category).
function T.valueOf(fullType)
    local explicit = T.values[fullType]
    if explicit ~= nil then return explicit end
    local item = script(fullType)
    if item == nil then return 0 end
    local category = read(item, "getDisplayCategory")
    local typeName = read(item, "getTypeString")
    if category ~= nil and T.untradable[tostring(category)] then return 0 end
    local base = T.categoryValues[tostring(category)] or T.categoryValues[tostring(typeName)] or 6
    local weight = tonumber(read(item, "getActualWeight")) or 1
    return math.max(1, math.floor(base * (0.75 + math.min(2, weight) * 0.25) + 0.5))
end

function T.tradable(fullType)
    return T.valueOf(fullType) > 0
end

-- Stock for a caravan kind: rows { item, name, value, count }.
function T.stockFor(kind, roll)
    roll = roll or A.randFloat
    local pool = T.stock[kind] or T.stock.trade
    local rows, chosen = {}, {}
    local wanted = math.min(#pool, 4 + math.floor(roll() * 4))
    local guard = 0
    while #rows < wanted and guard < 60 do
        guard = guard + 1
        local entry = pool[math.floor(roll() * #pool) + 1]
        if entry ~= nil and not chosen[entry[1]] then
            chosen[entry[1]] = true
            if T.exists(entry[1]) then
                local count = entry[2] + math.floor(roll() * (entry[3] - entry[2] + 1))
                rows[#rows + 1] = { item = entry[1], name = T.name(entry[1]), value = T.valueOf(entry[1]), count = math.max(1, math.min(T.maxCount, count)) }
            end
        end
    end
    return rows
end

-- Favor (-10..10) -> price multiplier: fair trades and escorts earn discounts, threats cost.
function T.favorFactor(favor)
    favor = tonumber(favor) or 0
    if favor < 0 then return 1 + math.min(0.5, -favor * 0.1) end
    return 1 - math.min(0.2, favor * 0.02)
end

function T.rateFor(kind)
    return T.rates[kind] or T.rates.trade
end

function T.sellPrice(row, kind, favor)
    return math.max(1, math.floor(row.value * T.rateFor(kind).sell * T.favorFactor(favor) + 0.5))
end

function T.buyPrice(fullType, kind)
    return math.floor(T.valueOf(fullType) * T.rateFor(kind).buy + 0.5)
end

-- Quote a deal: take = { [stockIndex] = count }, give = { { type = ..., count = n }, ... }.
-- Returns { ok, reason, cost, credit, balance, takeRows, giveRows }.
function T.quote(stock, kind, favor, take, give)
    if type(stock) ~= "table" or (take ~= nil and type(take) ~= "table") or (give ~= nil and type(give) ~= "table") then
        return { ok = false, reason = "bad_request" }
    end
    local out = { cost = 0, credit = 0, takeRows = {}, giveRows = {} }
    local taken, offered, entries = {}, {}, 0
    for rawIndex, rawCount in pairs(take or {}) do
        entries = entries + 1
        local index, count = tonumber(rawIndex), tonumber(rawCount)
        if entries > T.maxStock or index == nil or index ~= index or index % 1 ~= 0 or count == nil or count ~= count
            or count % 1 ~= 0 or count <= 0 or count > 999 or taken[index] then return { ok = false, reason = "bad_take" } end
        taken[index] = true
        local row = stock[index]
        if row == nil then return { ok = false, reason = "bad_take" } end
        if count > row.count then return { ok = false, reason = "out_of_stock" } end
        local price = T.sellPrice(row, kind, favor)
        out.cost = out.cost + price * count
        out.takeRows[#out.takeRows + 1] = { index = tonumber(index), item = row.item, name = row.name, count = count, price = price }
    end
    entries = 0
    for index, offer in pairs(give or {}) do
        entries = entries + 1
        if entries > 64 or type(index) ~= "number" or index % 1 ~= 0 or index < 1 or type(offer) ~= "table" then
            return { ok = false, reason = "bad_give" }
        end
        local count = tonumber(offer.count)
        if type(offer.type) ~= "string" or #offer.type > 128 or count == nil or count ~= count or count % 1 ~= 0
            or count <= 0 or count > 999 or not T.exists(offer.type) then return { ok = false, reason = "bad_give" } end
        local price = T.buyPrice(offer.type, kind)
        if price <= 0 then return { ok = false, reason = "unwanted:" .. offer.type } end
        out.credit = out.credit + price * count
        local previous = offered[offer.type]
        if previous ~= nil then
            previous.count = previous.count + count
            if previous.count > 999 then return { ok = false, reason = "bad_give" } end
        else
            local row = { type = offer.type, name = T.name(offer.type), count = count, price = price }
            offered[offer.type] = row
            out.giveRows[#out.giveRows + 1] = row
        end
    end
    out.balance = out.credit - out.cost
    if #out.takeRows == 0 and #out.giveRows == 0 then return { ok = false, reason = "empty" } end
    out.ok = out.balance >= 0
    if not out.ok then out.reason = "short" end
    return out
end

-- Apply an accepted deal to the stock (server): removes taken goods, adds given
-- goods the caravan can resell (merged by type, at most maxStock rows).
function T.commit(stock, quote)
    for _, row in ipairs(quote.takeRows or {}) do
        local entry = stock[row.index]
        if entry ~= nil then entry.count = math.max(0, entry.count - row.count) end
    end
    for _, row in ipairs(quote.giveRows or {}) do
        if row.type ~= T.currency then
            local merged = false
            for _, entry in ipairs(stock) do
                if entry.item == row.type then
                    entry.count = math.min(T.maxCount * 2, entry.count + row.count)
                    merged = true
                    break
                end
            end
            if not merged and #stock < T.maxStock then
                stock[#stock + 1] = { item = row.type, name = T.name(row.type), value = T.valueOf(row.type), count = math.min(T.maxCount, row.count) }
            end
        end
    end
    for index = #stock, 1, -1 do
        if stock[index].count <= 0 then table.remove(stock, index) end
    end
end

-- The same eligible items populate the UI and satisfy server payment. Never
-- sell equipped/favourite items or a bag with its contents still inside it.
function T.inventoryItems(player)
    local result, visited = {}, {}
    local function scan(container, depth)
        if container == nil or visited[container] or depth > 16 then return end
        visited[container] = true
        local items = container:getItems()
        for index = 0, items:size() - 1 do
            local item = items:get(index)
            local child = read(item, "getInventory")
            local favorite = read(item, "isFavorite") == true
            local equipped = false
            if type(player.isEquipped) == "function" then equipped = player:isEquipped(item) == true end
            local empty = child == nil or child:getItems():size() == 0
            local loaded = (tonumber(read(item, "getCurrentAmmoCount")) or 0) > 0 or read(item, "isRoundChambered") == true
            if not favorite and not equipped and empty and not loaded then
                result[#result + 1] = { item = item, container = container, type = item:getFullType() }
            end
            if not favorite then scan(child, depth + 1) end
        end
    end
    local ok = pcall(function() scan(player:getInventory(), 0) end)
    if not ok then return {} end
    return result
end

-- Vanilla B42 server ClientCommands uses these replication calls immediately
-- after inventory mutations. Clients never create their own purchased goods.
local function replicate(method, container, item)
    if A.side() ~= "server" then return end
    local fn = sendRemoveItemFromContainer
    if method == "add" then fn = sendAddItemToContainer end
    if type(fn) == "function" then
        local ok, err = pcall(fn, container, item)
        if not ok then A.fail("inventory " .. method, err) end
    end
end

-- Select actual item objects before changing anything. If output creation or
-- payment removal fails, restore the same objects (condition/content intact).
function T.exchange(player, quote)
    if not A.authority() or player == nil or type(quote) ~= "table" then return false, "bad_request" end
    local inventory = player:getInventory()
    local available, chosen, used = T.inventoryItems(player), {}, {}
    for _, row in ipairs(quote.giveRows or {}) do
        local remaining = row.count
        for _, candidate in ipairs(available) do
            if remaining > 0 and not used[candidate.item] and candidate.type == row.type then
                chosen[#chosen + 1] = candidate
                used[candidate.item] = true
                remaining = remaining - 1
            end
        end
        if remaining > 0 then return false, "short" end
    end
    local added, removed, attempted = {}, {}, {}
    local function contains(container, item)
        local items = container:getItems()
        for index = 0, items:size() - 1 do if items:get(index) == item then return true end end
        return false
    end
    local ok, err = pcall(function()
        for _, row in ipairs(quote.takeRows or {}) do
            for _ = 1, row.count do
                local item = inventory:AddItem(row.item)
                if item == nil then error("unavailable_item") end
                added[#added + 1] = item
            end
        end
        for _, candidate in ipairs(chosen) do
            attempted[#attempted + 1] = candidate
            candidate.container:Remove(candidate.item)
            if contains(candidate.container, candidate.item) then error("payment_failed") end
            removed[#removed + 1] = candidate
        end
    end)
    if not ok then
        for _, item in ipairs(added) do pcall(function() inventory:Remove(item) end) end
        for _, candidate in ipairs(attempted) do
            pcall(function() if not contains(candidate.container, candidate.item) then candidate.container:AddItem(candidate.item) end end)
        end
        A.fail("inventory exchange rolled back", err)
        return false, "inventory_failed"
    end
    for _, candidate in ipairs(removed) do replicate("remove", candidate.container, candidate.item) end
    for _, item in ipairs(added) do replicate("add", inventory, item) end
    return true
end

return T
