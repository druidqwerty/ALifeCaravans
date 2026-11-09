-- A-Life: Caravans v0.8.0 - Caravan Radio Dispatch, Supply Drops & Market Intel (shared).
-- Integrates 101.6 MHz Caravan & Trade Net with Project A-Life 1.5.1 RadioReserved,
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
            { "Base.MRE", 3 },
            { "Base.TinnedBeans", 2 },
            { "Base.CannedCornedBeef", 2 },
            { "Base.WaterBottleFull", 2 },
        },
    },
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
    local hasPower = power > 0.001 or isBattery == false or sourceKind == "vehicle" or sourceKind == "world" or sourceKind == "inventory" or sourceKind == "hand"
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

local function isProtectedItem(player, item)
    if item == nil then return true end
    if safeCall(item, "isFavorite") == true then return true end
    if player ~= nil and safeCall(player, "isEquipped", item) == true then return true end
    if player ~= nil and safeCall(player, "isHandItem", item) == true then return true end
    return false
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
            local ft = safeCall(item, "getFullType") or ""
            local val = ft == "Base.Money" and 10 or (A.Trade and A.Trade.valueOf(ft) or 0)
            if val > 0 then
                total = total + val
                usable[#usable + 1] = { item = item, fullType = ft, value = val }
            end
        end
    end
    table.sort(usable, function(a, b)
        local am = a.fullType == "Base.Money" and 0 or 1
        local bm = b.fullType == "Base.Money" and 0 or 1
        if am ~= bm then return am < bm end
        return a.value < b.value
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
    for _, entry in ipairs(usable) do
        if paid >= requiredCredit then break end
        paid = paid + entry.value
        pcall(function()
            inv:Remove(entry.item)
            if type(sendRemoveItemFromContainer) == "function" and A.side() == "server" then
                sendRemoveItemFromContainer(inv, entry.item)
            end
        end)
    end
    return true, paid
end

return R
