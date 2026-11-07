-- A-Life: Caravans - regional town market & special event caravan rules.
-- Pure shared logic used by server economy/director/interactions and client UI.

require "ALifeCaravans/00_ALC_Core"
require "ALifeCaravans/05_ALC_Trade"

local A = ALifeCaravans
local M = {
    categories = { "medical", "food", "ammo", "fuel", "tools" },
    tierMultipliers = { scarce = 1.35, normal = 1.0, abundant = 0.8 },
}
A.Market = M

M.itemCategory = {
    ["Base.Bandage"] = "medical", ["Base.Antibiotics"] = "medical", ["Base.Pills"] = "medical",
    ["Base.PillsAntiDep"] = "medical", ["Base.Disinfectant"] = "medical", ["Base.FirstAidKit"] = "medical",
    ["Base.SutureNeedle"] = "medical", ["Base.Splint"] = "medical",
    ["Base.TinnedBeans"] = "food", ["Base.CannedCornedBeef"] = "food", ["Base.CannedTomato"] = "food",
    ["Base.CannedChili"] = "food", ["Base.CannedBolognese"] = "food", ["Base.CannedSardines"] = "food",
    ["Base.WaterBottleFull"] = "food", ["Base.WaterBottle"] = "food", ["Base.MRE"] = "food",
    ["Base.CannedFruitCocktail"] = "food", ["Base.Coffee"] = "food", ["Base.Sugar"] = "food",
    ["Base.Rice"] = "food", ["Base.Pasta"] = "food", ["Base.Flour"] = "food", ["Base.Whiskey"] = "food",
    ["Base.Wine"] = "food", ["Base.Seeds_PotatoBag"] = "food", ["Base.Seeds_CabbageBag"] = "food",
    ["Base.Bullets9mmBox"] = "ammo", ["Base.Bullets45Box"] = "ammo", ["Base.Bullets38Box"] = "ammo",
    ["Base.Bullets44Box"] = "ammo", ["Base.ShotgunShellsBox"] = "ammo", ["Base.556Box"] = "ammo",
    ["Base.308Box"] = "ammo", ["Base.223Box"] = "ammo", ["Base.Pistol"] = "ammo", ["Base.Shotgun"] = "ammo",
    ["Base.HuntingRifle"] = "ammo", ["Base.Vest_BulletArmy"] = "ammo",
    ["Base.PetrolCan"] = "fuel", ["Base.EmptyPetrolCan"] = "fuel", ["Base.Battery"] = "fuel",
    ["Base.Generator"] = "fuel",
    ["Base.Axe"] = "tools", ["Base.Hammer"] = "tools", ["Base.Nails"] = "tools", ["Base.Rope"] = "tools",
    ["Base.Saw"] = "tools", ["Base.Crowbar"] = "tools", ["Base.Screwdriver"] = "tools",
    ["Base.Wrench"] = "tools", ["Base.DuctTape"] = "tools", ["Base.Torch"] = "tools",
    ["Base.Radio.WalkieTalkie4"] = "tools", ["Base.Machete"] = "tools", ["Base.HuntingKnife"] = "tools",
}

M.events = {
    trade_fair = {
        kind = "trade", class = "trade", maxStock = 12, sellFactor = 0.92, buyFactor = 1.15,
        haltBonusSeconds = 90, service = "vehicle_service",
        stock = {
            { "Base.Generator", 1, 1 }, { "Base.Axe", 1, 2 }, { "Base.Saw", 1, 2 }, { "Base.Crowbar", 1, 2 },
            { "Base.Wrench", 1, 2 }, { "Base.PetrolCan", 2, 3 }, { "Base.FirstAidKit", 1, 2 },
            { "Base.Antibiotics", 1, 2 }, { "Base.Seeds_PotatoBag", 2, 3 }, { "Base.Seeds_CabbageBag", 2, 3 },
            { "Base.Bullets9mmBox", 2, 3 }, { "Base.ShotgunShellsBox", 1, 3 }, { "Base.MRE", 2, 4 },
            { "Base.Radio.WalkieTalkie4", 1, 2 }, { "Base.Battery", 2, 4 }, { "Base.Coffee", 2, 3 },
        },
    },
    medical_aid = {
        kind = "rescue", class = "rescue", maxStock = 10, sellFactor = 0.85, buyFactor = 1.10,
        haltBonusSeconds = 60, service = "field_aid",
        stock = {
            { "Base.FirstAidKit", 2, 3 }, { "Base.Bandage", 4, 8 }, { "Base.Antibiotics", 2, 4 },
            { "Base.Disinfectant", 2, 4 }, { "Base.SutureNeedle", 2, 3 }, { "Base.Splint", 2, 3 },
            { "Base.Pills", 3, 5 }, { "Base.PillsAntiDep", 2, 3 }, { "Base.WaterBottleFull", 3, 5 },
        },
    },
    supply_drop = {
        kind = "convoy", class = "military", maxStock = 10, sellFactor = 1.0, buyFactor = 1.10,
        escortBonus = 120, service = "road_intel",
        stock = {
            { "Base.556Box", 2, 4 }, { "Base.308Box", 2, 3 }, { "Base.Bullets9mmBox", 2, 4 },
            { "Base.ShotgunShellsBox", 2, 3 }, { "Base.MRE", 4, 6 }, { "Base.FirstAidKit", 1, 2 },
            { "Base.Vest_BulletArmy", 1, 2 }, { "Base.Radio.WalkieTalkie4", 1, 2 }, { "Base.PetrolCan", 2, 3 },
        },
    },
    refugees = {
        kind = "trade", class = "civilian", maxStock = 6, sellFactor = 0.95, buyFactor = 1.25,
        shortageCategory = "food", service = "donate_supplies",
        stock = {
            { "Base.Sheet", 2, 4 }, { "Base.Soap2", 1, 3 }, { "Base.Lighter", 1, 2 },
            { "Base.Cigarettes", 2, 4 }, { "Base.HuntingKnife", 1, 1 }, { "Base.BaseballBat", 1, 1 },
            { "Base.Whiskey", 1, 2 }, { "Base.WaterBottle", 2, 4 },
        },
    },
    scavenger_haul = {
        kind = "trade", class = "raider", maxStock = 10, sellFactor = 0.95, buyFactor = 1.18,
        service = "vehicle_service",
        stock = {
            { "Base.PetrolCan", 2, 4 }, { "Base.Battery", 2, 4 }, { "Base.Wrench", 1, 2 },
            { "Base.Screwdriver", 1, 2 }, { "Base.Crowbar", 1, 2 }, { "Base.DuctTape", 2, 4 },
            { "Base.Rope", 2, 3 }, { "Base.Nails", 2, 4 }, { "Base.Machete", 1, 1 },
            { "Base.Pistol", 1, 1 }, { "Base.Shotgun", 1, 1 }, { "Base.Torch", 1, 2 },
        },
    },
}

function M.categoryOf(fullType)
    if type(fullType) ~= "string" then return nil end
    return M.itemCategory[fullType]
end

function M.tierForSupply(amount)
    amount = tonumber(amount) or 10
    if amount <= 5 then return "scarce" end
    if amount >= 16 then return "abundant" end
    return "normal"
end

function M.eventSpec(eventType)
    if type(eventType) ~= "string" then return nil end
    return M.events[eventType]
end

function M.itemMultiplier(fullType, market, eventType, isBuy)
    if fullType == A.Trade.currency then return 1.0 end
    local mult = 1.0
    if A.settings.economyEnabled ~= false and type(market) == "table" and type(market.tiers) == "table" then
        local cat = M.categoryOf(fullType)
        local tier = cat and market.tiers[cat] or "normal"
        if isBuy then
            -- Caravans bound for a town shortage pay +35% more for scarce goods.
            if tier == "scarce" then mult = mult * 1.35
            elseif tier == "abundant" then mult = mult * 0.85 end
        else
            -- Caravans carrying abundant regional goods sell them at a 15% discount.
            if tier == "abundant" then mult = mult * 0.85 end
        end
    end
    local ev = M.eventSpec(eventType)
    if ev ~= nil then
        if isBuy then
            mult = mult * (ev.buyFactor or 1.0)
            if ev.shortageCategory and M.categoryOf(fullType) == ev.shortageCategory then
                mult = mult * 1.25
            end
        else
            mult = mult * (ev.sellFactor or 1.0)
        end
    end
    return mult
end

-- Build stock for an event caravan or regional shipment.
function M.stockForCaravan(kind, eventType, roll)
    roll = roll or A.randFloat
    local ev = M.eventSpec(eventType)
    if ev == nil or type(ev.stock) ~= "table" then
        return A.Trade.stockFor(kind, roll)
    end
    local pool = ev.stock
    local maxRows = ev.maxStock or A.Trade.maxStock
    local wanted = math.min(#pool, math.max(5, math.min(maxRows, 6 + math.floor(roll() * 4))))
    local rows, chosen = {}, {}
    local guard = 0
    while #rows < wanted and guard < 80 do
        guard = guard + 1
        local entry = pool[math.floor(roll() * #pool) + 1]
        if entry ~= nil and not chosen[entry[1]] then
            chosen[entry[1]] = true
            if A.Trade.exists(entry[1]) then
                local count = entry[2] + math.floor(roll() * (entry[3] - entry[2] + 1))
                rows[#rows + 1] = {
                    item = entry[1], name = A.Trade.name(entry[1]),
                    value = A.Trade.valueOf(entry[1]),
                    count = math.max(1, math.min(A.Trade.maxCount * 2, count)),
                }
            end
        end
    end
    if #rows == 0 then return A.Trade.stockFor(kind, roll) end
    return rows
end

return M
