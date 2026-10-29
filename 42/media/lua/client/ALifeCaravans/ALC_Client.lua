-- A-Life: Caravans - client side. The right-click menu on a caravan car, the
-- trade list, the money exchange (the player's own inventory is the client's),
-- server notices, and the per-player options (Options > Mods). Which cars are
-- caravans comes from the world owner: directly in single player, by the
-- "state" command in multiplayer.

require "ALifeCaravans/00_ALC_Core"
require "ALifeCaravans/01_ALC_Lines"
require "ALifeCaravans/04_ALC_Convoy"

local A = ALifeCaravans
local Cl = { offers = {}, options = { menu = true, notices = true }, requestedAtMs = 0 }
A.Client = Cl
local L = A.Lines

local function player0()
    if type(getSpecificPlayer) == "function" then
        local ok, player = pcall(getSpecificPlayer, 0)
        if ok and player ~= nil then return player end
    end
    return A.players()[1]
end

function Cl.send(command, args)
    local player = player0()
    if player == nil then return end
    if type(isClient) == "function" and isClient() then
        pcall(sendClientCommand, player, A.MODULE, command, args)
    elseif A.Interact ~= nil and type(A.Interact.command) == "function" then
        local ok, err = pcall(A.Interact.command, player, command, args)
        if not ok then A.fail("local command " .. tostring(command), err) end
    end
end

function Cl.notice(text)
    if not Cl.options.notices or type(text) ~= "string" or text == "" then return end
    local player = player0()
    pcall(function()
        if HaloTextHelper ~= nil and type(HaloTextHelper.addText) == "function" then
            HaloTextHelper.addText(player, text, HaloTextHelper.getColorGreen())
        else
            player:Say(text)
        end
    end)
end

local function countOf(inventory, fullType)
    local ok, count = pcall(function() return inventory:getCountTypeRecurse(fullType) end)
    if ok and type(count) == "number" then return count end
    return 0
end

local function removeSome(inventory, fullType, count)
    for _ = 1, count do
        local ok = pcall(function()
            local item = inventory:getFirstTypeRecurse(fullType)
            if item == nil then error("missing") end
            local container = item:getContainer() or inventory
            container:Remove(item)
        end)
        if not ok then return false end
    end
    return true
end

-- The exchange itself happens here: the player's inventory belongs to the client.
function Cl.performTrade(args)
    local player = player0()
    if player == nil or type(args) ~= "table" then return end
    local inventory = player:getInventory()
    local price = math.max(0, math.floor(tonumber(args.price) or 0))
    local currency = tostring(args.currency or "Base.Money")
    local done = false
    if price == 0 or countOf(inventory, currency) >= price then
        if price == 0 or removeSome(inventory, currency, price) then
            if type(args.item) == "string" and args.item ~= "" then
                local ok = pcall(function() inventory:AddItem(args.item) end)
                done = ok
            else
                done = true
            end
        end
    end
    local reply = args.toll == true and "tollDone" or "tradeDone"
    Cl.send(reply, { vehicleId = args.vehicleId, index = args.index, ok = done })
    if done then
        if args.toll == true then
            Cl.notice(L.ui("toll_paid", "Toll paid: {price}", { price = price }))
        elseif price > 0 then
            Cl.notice(L.ui("bought", "Bought {item} for {price}", { item = args.name or args.item, price = price }))
        else
            Cl.notice(L.ui("received", "Received {item}", { item = args.name or args.item }))
        end
    else
        Cl.notice(L.ui("broke", "Not enough money ({price} needed)", { price = price }))
    end
end

function Cl.buy(vehicleId, index)
    Cl.send("buy", { vehicleId = vehicleId, index = index })
end

function Cl.showOffers(args)
    if type(args) ~= "table" or type(args.offers) ~= "table" then return end
    Cl.offers[args.vehicleId] = args
    local player = player0()
    if player == nil or type(ISContextMenu) ~= "table" or type(ISContextMenu.get) ~= "function" then return end
    local ok, err = pcall(function()
        local playerNum = player:getPlayerNum()
        local x, y = 0, 0
        if type(getMouseX) == "function" then x, y = getMouseX(), getMouseY() end
        local context = ISContextMenu.get(playerNum, x, y)
        context:addOption(L.ui("offers_title", "Caravan goods (cash: {currency})", { currency = "Money" }))
        for _, offer in ipairs(args.offers) do
            local label = L.ui("offer", "{item} - {price} (x{stock})", { item = offer.name, price = offer.price, stock = offer.stock })
            context:addOption(label, args.vehicleId, Cl.buy, offer.index)
        end
    end)
    if not ok then A.fail("offers menu", err) end
end

function Cl.receive(module, command, args)
    if module ~= A.MODULE then return end
    if command == "state" then
        A.Convoy.setKnown(type(args) == "table" and args.known or {})
    elseif command == "offers" then
        Cl.showOffers(args)
    elseif command == "tradeOk" then
        Cl.performTrade(args)
    elseif command == "riders" then
        local client = ProjectALife and ProjectALife.DrivingDemoClient
        if client ~= nil and type(args) == "table" then
            client.allowRiders = client.allowRiders or {}
            client.allowRiders[args.vehicleId] = args.enabled == true
        end
    elseif command == "notice" then
        Cl.notice(type(args) == "table" and args.text or nil)
    end
end

local function option(context, label, callback, ...)
    return context:addOption(label, nil, callback, ...)
end

function Cl.fill(playerNum, context, worldobjects, test)
    if test == true or not Cl.options.menu or type(context) ~= "table" or type(context.addOption) ~= "function" then return end
    local player = getSpecificPlayer(playerNum)
    if player == nil or player:isDead() then return end
    local rows = A.Convoy.near(player, 18)
    if #rows == 0 then return end
    local row = rows[1]
    local entry, id = row.entry, row.id
    local kind = L.ui("kind_" .. tostring(entry.kind), tostring(entry.kind))
    local root = context:addOption(L.ui("menu", "[A-LIFE] Caravan: {name} ({kind})", { name = entry.name, kind = kind }))
    local submenu = context:getNew(context)
    context:addSubMenu(root, submenu)
    local function send(command) return function() Cl.send(command, { vehicleId = id }) end end
    if not entry.halted then
        option(submenu, L.ui("hail", "Flag them down"), send("hail"))
    end
    option(submenu, L.ui("news", "Ask for news"), send("news"))
    if entry.halted then
        if entry.trade and not entry.hostile then option(submenu, L.ui("trade", "Trade"), send("offers")) end
        if A.settings.allowRiders and not entry.hostile then option(submenu, L.ui("ride", "Ask for a ride to {dest}", { dest = entry.dest }), send("ride")) end
        option(submenu, L.ui("wait", "Ask them to wait"), send("wait"))
        option(submenu, L.ui("farewell", "Let them go"), send("farewell"))
        if entry.kind == "raid" then option(submenu, L.ui("toll", "Pay the toll"), send("toll")) end
    end
    option(submenu, L.ui("threaten", "Threaten them"), send("threaten"))
end

function Cl.tick()
    if type(isClient) ~= "function" or not isClient() then return end
    local now = A.now()
    if now < Cl.requestedAtMs then return end
    Cl.requestedAtMs = now + 30000
    Cl.send("stateRequest", {})
end

function Cl.installOptions()
    if type(PZAPI) ~= "table" or PZAPI.ModOptions == nil or Cl.optionsInstalled then return end
    Cl.optionsInstalled = true
    local ok, err = pcall(function()
        local options = PZAPI.ModOptions:create("ALifeCaravans", "A-Life: Caravans")
        options:addDescription("UI_ALC_Options_Info")
        local menu = options:addTickBox("menu", "UI_ALC_Opt_Menu", true, "UI_ALC_Opt_Menu_tt")
        local notices = options:addTickBox("notices", "UI_ALC_Opt_Notices", true, "UI_ALC_Opt_Notices_tt")
        options.apply = function()
            Cl.options.menu = menu:getValue() ~= false
            Cl.options.notices = notices:getValue() ~= false
        end
        options:apply()
    end)
    if not ok then A.fail("mod options", err) end
end

if not A.clientRegistered then
    A.clientRegistered = true
    Cl.installOptions()
    if type(Events) == "table" then
        if Events.OnFillWorldObjectContextMenu then Events.OnFillWorldObjectContextMenu.Add(Cl.fill) end
        if Events.OnServerCommand then Events.OnServerCommand.Add(Cl.receive) end
        if Events.OnTick then Events.OnTick.Add(function() pcall(Cl.tick) end) end
    end
end

return Cl
