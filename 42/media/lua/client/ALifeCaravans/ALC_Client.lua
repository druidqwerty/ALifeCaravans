-- A-Life: Caravans - client side. The right-click menu on a caravan car, the
-- barter window, display-only exchange receipts (inventory belongs to the
-- world owner and uses vanilla replication), gifts,
-- server notices, headlight-flash hails, map markers and the per-player options
-- (Options > Mods). Which cars are caravans comes from the world owner: directly
-- in single player, by the "state" command in multiplayer.

require "ALifeCaravans/00_ALC_Core"
require "ALifeCaravans/01_ALC_Lines"
require "ALifeCaravans/04_ALC_Convoy"
require "ALifeCaravans/05_ALC_Trade"
require "ALifeCaravans/ALC_Map"
require "ISUI/ISCollapsableWindow"
require "ISUI/ISScrollingListBox"
require "ISUI/ISButton"
require "ALifeCaravans/ALC_ContactWindow"
require "ALifeCaravans/ALC_Details"

local A = ALifeCaravans
local Cl = { options = { menu = true, notices = true }, requestedAtMs = 0, stock = {}, done = {}, flashes = {}, window = nil }
A.Client = Cl
local L = A.Lines
local T = A.Trade

local function player0(playerNum)
    if type(getSpecificPlayer) == "function" then
        local ok, player = pcall(getSpecificPlayer, tonumber(playerNum) or 0)
        if ok and player ~= nil then return player end
    end
    if (tonumber(playerNum) or 0) ~= 0 then return nil end
    return A.players()[1]
end

function Cl.send(command, args, playerNum)
    local player = player0(playerNum)
    if player == nil then return end
    if type(isClient) == "function" and isClient() then
        pcall(sendClientCommand, player, A.MODULE, command, args)
    elseif A.Interact ~= nil and type(A.Interact.command) == "function" then
        local ok, err = pcall(A.Interact.command, player, command, args)
        if not ok then A.fail("local command " .. tostring(command), err) end
    end
end

function Cl.notice(text, playerNum)
    if not Cl.options.notices or type(text) ~= "string" or text == "" then return end
    local player = player0(playerNum)
    if player == nil then return end
    pcall(function()
        if HaloTextHelper ~= nil and type(HaloTextHelper.addText) == "function" then
            -- B42.21 exposes (IsoPlayer,String), not (IsoPlayer,String,ColorRGB).
            HaloTextHelper.addText(player, text)
        else
            player:Say(text)
        end
    end)
end

-- Compatibility name, now a receipt only. Replayed or old dealOk packets
-- cannot mint inventory items or pay a transaction twice.
function Cl.performDeal(args)
    if type(args) ~= "table" then return end
    local txId = tostring(args.txId or "")
    if txId == "" or Cl.done[txId] then return end
    Cl.done[txId] = true
    if args.toll == true then
        Cl.notice(L.ui("toll_paid", "Toll paid: {price}", { price = args.credit }), args.playerNum)
    else
        local bought, paid = {}, {}
        for _, row in ipairs(args.take or {}) do bought[#bought + 1] = tostring(row.count) .. "x " .. tostring(row.name or row.item) end
        for _, row in ipairs(args.give or {}) do paid[#paid + 1] = tostring(row.count) .. "x " .. tostring(row.name or row.type) end
        Cl.notice(L.ui("dealt", "Traded {paid} for {bought}", { paid = table.concat(paid, ", "),
            bought = #bought > 0 and table.concat(bought, ", ") or "-" }), args.playerNum)
    end
    if Cl.window ~= nil then Cl.window:refresh() end
end

function Cl.receiveGift(args)
    if type(args) ~= "table" or args.delivered ~= true or type(args.item) ~= "string" then return end
    Cl.notice(L.ui("received", "Received {item}", { item = tostring(args.count or 1) .. "x " .. tostring(args.name or args.item) }), args.playerNum)
end

require("ALifeCaravans/ALC_TradeWindow")(Cl, player0)

function Cl.openTrade(vehicleId, playerNum)
    if ALCTradeWindow == nil then return false end
    if Cl.window ~= nil then Cl.window:onClose() end
    local ok, err = pcall(function()
        local width = math.min(900,getCore():getScreenWidth()-40)
        local height = math.min(640,getCore():getScreenHeight()-60)
        local x = math.floor((getCore():getScreenWidth() - width) / 2)
        local y = math.floor((getCore():getScreenHeight() - height) / 2)
        local window = ALCTradeWindow:new(x, y, width, height)
        window.vehicleId = vehicleId
        window.playerNum = tonumber(playerNum) or 0
        local view = Cl.stock[vehicleId]
        window:setTitle(L.ui("trade_title", "Caravan trade: {leader} ({callsign})", { leader = view and view.leader or "?", callsign = view and view.callsign or "" }))
        window:initialise()
        window:addToUIManager()
        window:setVisible(true)
        Cl.window = window
        window:setResizable(true)
        if JoypadState and JoypadState.players and JoypadState.players[window.playerNum + 1] and type(setJoypadFocus) == "function" then
            setJoypadFocus(window.playerNum, window)
        end
    end)
    if not ok then A.fail("trade window", err) return false end
    return true
end

function Cl.invalidateTrade(known)
    for id in pairs(Cl.stock) do
        if not known[id] then Cl.stock[id] = nil end
    end
    if Cl.window and not known[Cl.window.vehicleId] then Cl.window:onClose() end
    if Cl.contact and not known[Cl.contact.vehicleId] then Cl.contact:close() end
end

function Cl.setMarkers(markers)
    A.Map.setMarkers(markers)
end

function Cl.receive(module, command, args)
    if module ~= A.MODULE then return end
    if command == "state" then
        A.Convoy.setKnown(type(args) == "table" and args.known or {})
        A.Map.setMarkers(type(args) == "table" and args.markers or {})
    elseif command == "stock" then
        if type(args) == "table" and args.vehicleId ~= nil and A.Convoy.entry(args.vehicleId) then
            Cl.stock[args.vehicleId] = args
            if Cl.window ~= nil and Cl.window.vehicleId == args.vehicleId and Cl.window.playerNum == (args.playerNum or 0) then
                Cl.window:refresh()
            else Cl.openTrade(args.vehicleId, args.playerNum) end
        end
    elseif command == "cargoView" or command == "caravanStatus" then
        A.Details.receive(command,args)
    elseif command == "dealReceipt" then
        Cl.performDeal(args)
    elseif command == "dealRefused" then
        Cl.notice(L.ui("refused", "No deal ({reason})", { reason = type(args) == "table" and args.reason or "?" }))
    elseif command == "gift" then
        Cl.receiveGift(args)
    elseif command == "riders" then
        local client = ProjectALife and ProjectALife.DrivingDemoClient
        if client ~= nil and type(args) == "table" then
            client.allowRiders = client.allowRiders or {}
            client.allowRiders[args.vehicleId] = args.enabled == true
        end
    elseif command == "sosNotice" then
        if type(args) == "table" and type(args.key) == "string" then
            local vars = type(args.vars) == "table" and args.vars or {}
            if vars.reasonKey ~= nil then vars.reason = L.ui("sos_reason_" .. tostring(vars.reasonKey), tostring(vars.reasonKey)) end
            Cl.notice(L.ui("sos_" .. args.key, args.key, vars))
        end
    elseif command == "notice" then
        Cl.notice(type(args) == "table" and args.text or nil)
    end
end

local function option(context, label, callback, ...)
    return context:addOption(label, nil, callback, ...)
end

function Cl.fill(playerNum, context, worldobjects, test)
    if not Cl.options.menu then return end
    local player = player0(playerNum)
    if player == nil or player:isDead() then return end
    local rows = A.Convoy.near(player, 18)
    if #rows == 0 then return end
    if test == true then
        if ISWorldObjectContextMenu and type(ISWorldObjectContextMenu.setTest) == "function" then
            return ISWorldObjectContextMenu.setTest()
        end
        return
    end
    if type(context) ~= "table" or type(context.addOption) ~= "function" or type(context.getNew) ~= "function"
        or type(context.addSubMenu) ~= "function" then return end
    local row = rows[1]
    local entry, id = row.entry, row.id
    local kind = L.ui("kind_" .. tostring(entry.kind), tostring(entry.kind))
    local name = tostring(entry.name or "?")
    if entry.callsign then name = name .. " " .. tostring(entry.callsign) end
    local root = context:addOption(L.ui("menu", "[A-LIFE] Caravan: {name} ({kind})", { name = name, kind = kind }))
    local submenu = context:getNew(context)
    context:addSubMenu(root, submenu)
    local function send(command) return function() Cl.send(command, { vehicleId = id }, playerNum) end end
    option(submenu,L.ui("open_contact","Open convoy panel"),function() A.Style.openContact(id,playerNum) end)
    if A.settings.sosContracts and entry.sosState ~= nil then
        if entry.sosState == "open" and not entry.hostile then
            option(submenu, L.ui("sos_accept", "SOS: cover the convoy's escape"), send("distress_help"))
        elseif entry.sosOwner == A.playerKey(player) then
            option(submenu, L.ui("sos_status", "SOS: rescue progress"), send("sos_status"))
        end
    end
    if not entry.halted then
        option(submenu, L.ui("hail", "Flag them down"), send("hail"))
    end
    option(submenu, L.ui("news", "Ask for news"), send("news"))
    if entry.halted then
        if entry.trade and not entry.hostile then option(submenu, L.ui("trade", "Trade"), send("trade")) end
        if A.settings.allowRiders and not entry.hostile then option(submenu, L.ui("ride", "Ask for a ride to {dest}", { dest = entry.dest }), send("ride")) end
        if A.settings.escortContracts and not entry.hostile and entry.escort == nil then
            option(submenu, L.ui("escort", "Offer an escort to {dest}", { dest = entry.dest }), send("escort"))
        end
        option(submenu, L.ui("wait", "Ask them to wait"), send("wait"))
        option(submenu, L.ui("farewell", "Let them go"), send("farewell"))
        if entry.kind == "raid" then option(submenu, L.ui("toll", "Pay the toll"), send("toll")) end
    elseif A.settings.escortContracts and not entry.hostile and entry.escort == nil then
        option(submenu, L.ui("escort", "Offer an escort to {dest}", { dest = entry.dest }), send("escort"))
    end
    option(submenu, L.ui("threaten", "Threaten them"), send("threaten"))
end

-- Headlights flashed three times within four seconds near a caravan: a hail.
function Cl.flashTick(now)
    local player = player0()
    if player == nil or not A.settings.hornHails then return end
    local vehicle
    pcall(function() vehicle = player:getVehicle() end)
    if vehicle == nil then Cl.flashState = nil Cl.flashes = {} return end
    local on
    pcall(function() on = vehicle:getHeadlightsOn() end)
    if on == nil then return end
    if Cl.flashState ~= nil and Cl.flashState ~= on then
        Cl.flashes[#Cl.flashes + 1] = now
    end
    Cl.flashState = on
    for index = #Cl.flashes, 1, -1 do
        if now - Cl.flashes[index] > 4000 then table.remove(Cl.flashes, index) end
    end
    if #Cl.flashes >= 3 then
        Cl.flashes = {}
        local rows = A.Convoy.near(player, 30)
        if #rows > 0 then Cl.send("hail", { vehicleId = rows[1].id, horn = true }) end
    end
end

function Cl.tick()
    local now = A.now()
    pcall(Cl.flashTick, now)
    if type(isClient) ~= "function" or not isClient() then return end
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
        local worldMap = options:addTickBox("worldMap", "UI_ALC_Opt_WorldMap", true, "UI_ALC_Opt_WorldMap_tt")
        local minimap = options:addTickBox("minimap", "UI_ALC_Opt_Minimap", true, "UI_ALC_Opt_Minimap_tt")
        local labels = options:addTickBox("labels", "UI_ALC_Opt_Labels", true, "UI_ALC_Opt_Labels_tt")
        options.apply = function()
            Cl.options.menu = menu:getValue() ~= false
            Cl.options.notices = notices:getValue() ~= false
            A.Map.options.worldMap = worldMap:getValue() ~= false
            A.Map.options.minimap = minimap:getValue() ~= false
            A.Map.options.labels = labels:getValue() ~= false
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
        if Events.OnGameStart then Events.OnGameStart.Add(function() pcall(A.Map.install) end) end
    end
end

return Cl
