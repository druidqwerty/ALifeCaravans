-- A-Life: Caravans v0.8.2 - Caravan Radio Dispatch, Supply Drops & Market Intel (shared).
-- Integrates 101.6 MHz Caravan & Trade Net with Project A-Life 1.5.3 RadioReserved,
-- inspects WalkieTalkies / HamRadios / VehicleRadios, checks writing utensils for
-- WorldMapSymbols, and defines the 5 roadside Supply Drop packages.

require "ALifeCaravans/00_ALC_Core"
require "ALifeCaravans/05_ALC_Trade"

local A = ALifeCaravans
local R = {
    CHANNEL_UUID = "ALC-TRAD-1016",
    CHANNEL_NAME = "Caravan & Trade Net",
}
A.Radio = R

R.WRITING_TYPES = {
    ["Base.Pen"] = true, ["Base.Pencil"] = true, ["Base.RedPen"] = true, ["Base.BluePen"] = true,
    ["Base.GreenPen"] = true, ["Base.Crayons"] = true, ["Base.PencilSpiffo"] = true, ["Base.PenMultiColor"] = true,
    ["Pen"] = true, ["Pencil"] = true, ["RedPen"] = true, ["BluePen"] = true, ["GreenPen"] = true, ["Crayons"] = true,
}

R.PACKAGES = {
    {
        id = "pkg_medical",
        cost = 80,
        items = {
            { "Base.FirstAidKit", 1 },
            { "Base.Antibiotics", 1 },
            { "Base.Bandage", 4 },
            { "Base.Disinfectant", 1 },
            { "Base.Pills", 2 },
        },
    },
    {
        id = "pkg_ammo",
        cost = 110,
        items = {
            { "Base.Bullets9mmBox", 2 },
            { "Base.ShotgunShellsBox", 2 },
            { "Base.556Box", 1 },
        },
    },
    {
        id = "pkg_fuel",
        cost = 85,
        items = {
            { "Base.PetrolCan", 2 },
            { "Base.Wrench", 1 },
            { "Base.DuctTape", 2 },
        },
    },
    {
        id = "pkg_tools",
        cost = 90,
        items = {
            { "Base.Crowbar", 1 },
            { "Base.Hammer", 1 },
            { "Base.Saw", 1 },
            { "Base.Screwdriver", 1 },
            { "Base.Nails", 2 },
        },
    },
    {
        id = "pkg_rations",
        cost = 65,
        items = {
            { "Base.WaterRationCan", 2 },
            { "Base.CannedChili", 2 },
            { "Base.TinnedBeans", 2 },
            { "Base.CannedCornedBeef", 2 },
            { "Base.BeefJerky", 2 },
            { "Base.WaterBottle", 2 },
        },
    },
}

-- Only cash and safe expendable barter commodities can be spent automatically
-- when ordering a radio supply drop (NEVER weapons, tools, radios, keys, bags, or clothing).
R.SAFE_BARTER_CATEGORIES = {
    Food = true, Water = true, FirstAid = true, Medical = true, Material = true, Cooking = true,
}

R.SAFE_BARTER_TYPES = {
    ["Base.TinnedBeans"] = true, ["Base.CannedCornedBeef"] = true, ["Base.CannedTomato"] = true,
    ["Base.CannedChili"] = true, ["Base.CannedBolognese"] = true, ["Base.CannedSardines"] = true,
    ["Base.CannedFruitCocktail"] = true, ["Base.WaterRationCan"] = true, ["Base.BeefJerky"] = true,
    ["Base.WaterBottle"] = true, ["Base.Bandage"] = true, ["Base.Antibiotics"] = true,
    ["Base.Pills"] = true, ["Base.PillsAntiDep"] = true, ["Base.Disinfectant"] = true,
    ["Base.SutureNeedle"] = true, ["Base.Splint"] = true,
    ["Base.CigarettePack"] = true, ["Base.CigaretteSingle"] = true, ["Base.CigaretteCarton"] = true,
    ["Base.Cigarettes"] = true, ["Base.Whiskey"] = true, ["Base.Wine"] = true,
    ["Base.Coffee2"] = true, ["Base.Sugar"] = true, ["Base.Rice"] = true, ["Base.Pasta"] = true,
    ["Base.Flour2"] = true, ["Base.DuctTape"] = true, ["Base.Rope"] = true, ["Base.Nails"] = true,
    ["Base.NailsBox"] = true, ["Base.Sheet"] = true, ["Base.Soap2"] = true,
}

local function safeCall(obj, method, ...)
    if obj == nil then return nil end
    local fn = obj[method]
    if type(fn) ~= "function" then return nil end
    local ok, res = pcall(fn, obj, ...)
    if ok then return res end
    return nil
end

-- Resolve Caravan channel frequency (default 101600 Hz = 101.6 MHz), avoiding any
-- frequency reserved by Project A-Life 1.5+ (ProjectALife.RadioReserved).
function R.frequency()
    local target = A.clamp(A.settings and A.settings.radioFreqKhz, 88000, 108000, 101600)
    target = math.floor(target / 200) * 200
    local reserved = {}
    local p = ProjectALife
    if p and type(p.RadioReserved) == "table" and type(p.RadioReserved.entries) == "table" then
        for _, row in ipairs(p.RadioReserved.entries) do
            if tonumber(row.frequency) then reserved[tonumber(row.frequency)] = true end
            for _, alt in ipairs(row.alternates or {}) do
                if tonumber(alt) then reserved[tonumber(alt)] = true end
            end
        end
    end
    if p and type(p.RadioFreq) == "table" and type(p.RadioFreq.assigned) == "function" then
        for _, key in ipairs({ "knox", "field" }) do
            local ok, val = pcall(p.RadioFreq.assigned, key)
            if ok and tonumber(val) then reserved[tonumber(val)] = true end
        end
    end
    local steps = 0
    while reserved[target] and steps < 50 do
        target = target + 200
        if target > 107800 then target = 88400 end
        steps = steps + 1
    end
    return target
end

function R.freqMhz(khz)
    local val = tonumber(khz) or R.frequency()
    return string.format("%.1f MHz", val / 1000)
end

function R.packageById(pkgId)
    for _, pkg in ipairs(R.PACKAGES) do
        if pkg.id == pkgId then return pkg end
    end
    return nil
end

local function inspectDevice(device, sourceKind)
    if device == nil then return nil end
    local dd = safeCall(device, "getDeviceData")
    if dd == nil then return nil end
    local turnedOn = safeCall(dd, "getIsTurnedOn") == true
    local power = tonumber(safeCall(dd, "getPower")) or 0
    local isBattery = safeCall(dd, "getIsBatteryPowered")
    local hasPower
    if isBattery == true then
        hasPower = power > 0.001
    elseif isBattery == false then
        local canGrid = safeCall(dd, "canBePoweredHere")
        hasPower = (canGrid ~= false) or power > 0.001
    else
        hasPower = power > 0.001
    end
    local channel = tonumber(safeCall(dd, "getChannel")) or R.frequency()
    local deviceName = tostring(safeCall(dd, "getDeviceName") or safeCall(device, "getName") or "Radio")
    -- Vanilla PZ automatically turns off unequipped inventory radios to save battery;
    -- carrying a powered walkie-talkie in inventory/hands counts as active when using the radio UI.
    local active = (turnedOn or sourceKind == "inventory" or sourceKind == "hand") and hasPower
    return {
        device = device,
        deviceData = dd,
        sourceKind = sourceKind,
        name = deviceName,
        turnedOn = turnedOn,
        hasPower = hasPower,
        active = active,
        channel = channel,
    }
end

function R.scanPlayerRadios(player)
    local out = {
        hasRadio = false,
        hasPowered = false,
        tunedChannel = nil,
        best = nil,
        devices = {},
    }
    if player == nil then return out end
    local seen = {}
    local function consider(dev, kind)
        if dev == nil or seen[dev] then return end
        seen[dev] = true
        local info = inspectDevice(dev, kind)
        if info == nil then return end
        out.hasRadio = true
        out.devices[#out.devices + 1] = info
        if info.active or not A.settings.requirePoweredRadio then
            out.hasPowered = true
        end
        if out.best == nil or (info.active and not out.best.active) then
            out.best = info
        end
    end

    consider(safeCall(player, "getPrimaryHandItem"), "hand")
    consider(safeCall(player, "getSecondaryHandItem"), "hand")

    local inv = safeCall(player, "getInventory")
    local items = inv and safeCall(inv, "getItems") or nil
    if items ~= nil and type(items.size) == "function" then
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            if item ~= nil and ((type(instanceof) == "function" and instanceof(item, "Radio")) or type(item.getDeviceData) == "function") then
                consider(item, "inventory")
            end
        end
    end

    local vehicle = safeCall(player, "getVehicle")
    if vehicle ~= nil then
        local part = safeCall(vehicle, "getPartById", "Radio")
        if part ~= nil then consider(part, "vehicle") end
    end

    local px, py, pz = A.xyz(player)
    local cell = type(getCell) == "function" and getCell() or nil
    if px ~= nil and cell ~= nil and type(cell.getGridSquare) == "function" then
        local bx, by, bz = math.floor(px), math.floor(py), math.floor(pz or 0)
        for dx = -3, 3 do
            for dy = -3, 3 do
                local sq = cell:getGridSquare(bx + dx, by + dy, bz)
                local objs = sq and safeCall(sq, "getObjects") or nil
                if objs ~= nil and type(objs.size) == "function" then
                    for i = 0, objs:size() - 1 do
                        local obj = objs:get(i)
                        if obj ~= nil and ((type(instanceof) == "function" and instanceof(obj, "IsoWaveSignal")) or type(obj.getDeviceData) == "function") then
                            consider(obj, "world")
                        end
                    end
                end
            end
        end
    end

    if out.best ~= nil then out.tunedChannel = out.best.channel end
    if not A.settings.requirePoweredRadio then out.hasPowered = true end
    return out
end

function R.canUseRadio(player)
    if not A.settings.requirePoweredRadio then return true, "ok" end
    local scan = R.scanPlayerRadios(player)
    if not scan.hasRadio then return false, "no_radio" end
    if not scan.hasPowered then return false, "radio_off" end
    return true, "ok", scan
end

function R.tunePlayerRadio(player, freqKhz)
    freqKhz = tonumber(freqKhz) or R.frequency()
    local scan = R.scanPlayerRadios(player)
    local target = scan.best
    if target == nil or target.deviceData == nil then return false, "no_radio" end
    local dd = target.deviceData
    pcall(function()
        if type(dd.setTurnedOnRaw) == "function" then dd:setTurnedOnRaw(true) end
        if not dd:getIsTurnedOn() then dd:setIsTurnedOn(true) end
        dd:setChannel(freqKhz)
    end)
    return true, freqKhz, target.name
end

function R.canWriteOnMap(player)
    if player == nil then return false end
    local inv = safeCall(player, "getInventory")
    if inv == nil then return false end
    local hasWriteTag = false
    pcall(function()
        if ItemTag and ItemTag.WRITE and type(inv.containsTagRecurse) == "function" then
            hasWriteTag = inv:containsTagRecurse(ItemTag.WRITE) == true
        end
    end)
    if hasWriteTag then return true end
    if type(inv.containsTypeRecurse) == "function" then
        for ft in pairs(R.WRITING_TYPES) do
            local ok, found = pcall(inv.containsTypeRecurse, inv, ft)
            if ok and found == true then return true end
        end
    end
    local items = safeCall(inv, "getItems")
    if items ~= nil and type(items.size) == "function" then
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            local ft = safeCall(item, "getFullType") or ""
            local st = safeCall(item, "getType") or ""
            if R.WRITING_TYPES[ft] or R.WRITING_TYPES[st] then return true end
        end
    end
    return false
end

local function isItemClass(item, className)
    if item == nil or type(instanceof) ~= "function" then return false end
    local ok, hit = pcall(instanceof, item, className)
    return ok and hit == true
end

local function isProtectedItem(player, item)
    if item == nil then return true end
    if A.Trade and type(A.Trade.isProtectedItem) == "function" and A.Trade.isProtectedItem(player, item) then
        return true
    end
    if safeCall(item, "isFavorite") == true then return true end
    if safeCall(item, "isEquipped") == true then return true end
    if player ~= nil then
        if safeCall(player, "isEquipped", item) == true then return true end
        if safeCall(player, "isHandItem", item) == true then return true end
        if safeCall(player, "getPrimaryHandItem") == item or safeCall(player, "getSecondaryHandItem") == item then
            return true
        end
        if safeCall(player, "isAttachedItem", item) == true then return true end
    end
    local attachedSlot = tonumber(safeCall(item, "getAttachedSlot"))
    if attachedSlot ~= nil and attachedSlot >= 0 then return true end
    -- Never automatically spend containers, keys/keyrings, radios, weapons, clothing, or writing utensils.
    if safeCall(item, "isKeyRing") == true then return true end
    if safeCall(item, "getInventory") ~= nil then return true end
    if safeCall(item, "getDeviceData") ~= nil then return true end
    if (tonumber(safeCall(item, "getCurrentAmmoCount")) or 0) > 0 or safeCall(item, "isRoundChambered") == true then
        return true
    end
    if isItemClass(item, "Key") or isItemClass(item, "KeyRing") or isItemClass(item, "Radio")
            or isItemClass(item, "HandWeapon") or isItemClass(item, "Clothing") or isItemClass(item, "InventoryContainer") then
        return true
    end
    local ft = tostring(safeCall(item, "getFullType") or "")
    local st = tostring(safeCall(item, "getType") or "")
    if R.WRITING_TYPES[ft] or R.WRITING_TYPES[st] then return true end
    if string.find(ft, "KeyRing", 1, true) or string.find(ft, "WalkieTalkie", 1, true)
            or string.find(ft, "HamRadio", 1, true) then
        return true
    end
    return false
end

local function isAutoSpendEligible(item, ft)
    if ft == "Base.Money" or ft == "Base.MoneyBundle" then return true end
    if R.SAFE_BARTER_TYPES[ft] == true then return true end
    local dcat = tostring(safeCall(item, "getDisplayCategory") or "")
    if R.SAFE_BARTER_CATEGORIES[dcat] == true then return true end
    return false
end

function R.isProtectedForDrop(player, item)
    return isProtectedItem(player, item)
end

function R.countPlayerCredit(player)
    local inv = safeCall(player, "getInventory")
    local items = inv and safeCall(inv, "getItems") or nil
    if items == nil or type(items.size) ~= "function" then return 0, {} end
    local total = 0
    local usable = {}
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if not isProtectedItem(player, item) then
            local ft = tostring(safeCall(item, "getFullType") or "")
            if isAutoSpendEligible(item, ft) then
                local val
                if ft == "Base.Money" then val = 10
                elseif ft == "Base.MoneyBundle" then val = 1000
                else val = A.Trade and A.Trade.valueOf(ft) or 0 end
                if val > 0 then
                    total = total + val
                    usable[#usable + 1] = { item = item, fullType = ft, value = val }
                end
            end
        end
    end
    table.sort(usable, function(a, b)
        local am = (a.fullType == "Base.Money" or a.fullType == "Base.MoneyBundle") and 0 or 1
        local bm = (b.fullType == "Base.Money" or b.fullType == "Base.MoneyBundle") and 0 or 1
        if am ~= bm then return am < bm end
        if a.value ~= b.value then return a.value < b.value end
        return tostring(a.fullType) < tostring(b.fullType)
    end)
    return total, usable
end

function R.spendPlayerCredit(player, requiredCredit)
    requiredCredit = math.max(0, math.floor(tonumber(requiredCredit) or 0))
    if requiredCredit <= 0 then return true, 0 end
    local total, usable = R.countPlayerCredit(player)
    if total < requiredCredit then return false, "insufficient_credit" end
    local inv = safeCall(player, "getInventory")
    if inv == nil then return false, "no_inventory" end
    local paid = 0
    local removed = {}
    local ok, err = pcall(function()
        for _, entry in ipairs(usable) do
            if paid >= requiredCredit then break end
            inv:Remove(entry.item)
            removed[#removed + 1] = entry
            paid = paid + entry.value
        end
    end)
    if not ok then
        for _, entry in ipairs(removed) do
            pcall(function() inv:AddItem(entry.item) end)
        end
        A.fail("radio spend credit rolled back", err)
        return false, "spend_failed"
    end
    if type(sendRemoveItemFromContainer) == "function" and A.side() == "server" then
        for _, entry in ipairs(removed) do
            pcall(sendRemoveItemFromContainer, inv, entry.item)
        end
    end
    return true, paid
end

return R
