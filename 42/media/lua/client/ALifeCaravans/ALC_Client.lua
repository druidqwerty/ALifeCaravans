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
require "ALifeCaravans/07_ALC_Market"
require "ALifeCaravans/08_ALC_Ballistics"
require "ALifeCaravans/09_ALC_Radio"
require "ALifeCaravans/ALC_Map"
require "ISUI/ISCollapsableWindow"
require "ISUI/ISScrollingListBox"
require "ISUI/ISButton"
require "ALifeCaravans/ALC_ContactWindow"
require "ALifeCaravans/ALC_RadioWindow"
require "ALifeCaravans/ALC_Details"

local A = ALifeCaravans
local Cl = {
    options = { menu = true, notices = true, radioKey = (type(Keyboard) == "table" and Keyboard.KEY_F9) or 67 },
    requestedAtMs = 0, stock = {}, done = {}, flashes = {}, window = nil, radioWindow = nil,
    radioLog = {}, dispatches = {}, markets = {},
}
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

function Cl.setRadioState(radioLog, dispatches, markets)
    if type(radioLog) == "table" then Cl.radioLog = radioLog end
    if type(dispatches) == "table" then Cl.dispatches = dispatches end
    if type(markets) == "table" then Cl.markets = markets end
    if Cl.radioWindow ~= nil then Cl.radioWindow:refresh() end
end

function Cl.receive(module, command, args)
    if module ~= A.MODULE then return end
    if command == "state" then
        A.Convoy.setKnown(type(args) == "table" and args.known or {})
        A.Map.setMarkers(type(args) == "table" and args.markers or {})
        if type(args) == "table" then
            Cl.setRadioState(args.radioLog, args.dispatches, args.markets)
        end
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
    elseif command == "serviceNotice" then
        if type(args) == "table" and type(args.key) == "string" then
            Cl.notice(L.ui("service_" .. args.key, args.key, type(args.vars) == "table" and args.vars or {}), args.playerNum)
        end
    elseif command == "radioEvent" then
        if type(args) == "table" then
            local p = player0(args.playerNum)
            if args.entry then
                local canRx = not A.Radio or A.Radio.canUseRadio(p)
                if canRx then
                    Cl.notice("[" .. (A.Radio and A.Radio.freqMhz(args.entry.freq) or "101.6 MHz") .. "] " .. tostring(args.entry.text or ""), args.playerNum)
                    A.Map.autoMarkEntry(args.entry, p)
                end
            elseif args.kind == "drop_claimed" then
                Cl.notice(L.ui("rnotice_drop_claimed", "Claimed supply drop from {callsign}!", args), args.playerNum)
            end
            if Cl.radioWindow ~= nil then Cl.radioWindow:refresh() end
        end
    elseif command == "notice" then
        Cl.notice(type(args) == "table" and args.text or nil)
    end
end

local function option(context, label, callback, ...)
    return context:addOption(label, nil, callback, ...)
end

function Cl.fillInventoryMenu(playerNum, context, items)
    if not Cl.options.menu or type(context) ~= "table" or type(context.addOption) ~= "function" then return end
    local foundRadio = false
    for _, v in ipairs(items or {}) do
        local item = type(v) == "table" and v.items and v.items[1] or v
        if item ~= nil and ((type(instanceof) == "function" and instanceof(item, "Radio")) or type(item.getDeviceData) == "function") then
            foundRadio = true
            break
        end
    end
    if not foundRadio then return end
    option(context, L.ui("menu_open_radio", "[A-LIFE] Caravan Radio & Dispatch (101.6 MHz)"), function()
        if A.Style and type(A.Style.openRadioWindow) == "function" then
            A.Style.openRadioWindow(playerNum, "airwaves")
        end
    end)
end

function Cl.onKeyPressed(key)
    local bind = tonumber(Cl.options.radioKey) or 67
    if key == bind then
        local p = player0(0)
        if p ~= nil and not p:isDead() and A.Style and type(A.Style.openRadioWindow) == "function" then
            A.Style.openRadioWindow(0, nil)
        end
    end
end

function Cl.fill(playerNum, context, worldobjects, test)
    if not Cl.options.menu then return end
    local player = player0(playerNum)
    if player == nil or player:isDead() then return end
    local rows = A.Convoy.near(player, 18)
    local nearDrop = nil
    local px, py = A.xyz(player)
    if px ~= nil then
        for _, d in ipairs(Cl.dispatches or {}) do
            if d.state == "ready" and d.x and A.dist(px, py, d.x, d.y) <= 25 then
                nearDrop = d
                break
            end
        end
    end
    if #rows == 0 and nearDrop ~= nil and test ~= true and type(context) == "table" and type(context.addOption) == "function" then
        option(context, L.ui("rbtn_claim_drop", "Claim Supply Drop") .. " [" .. tostring(nearDrop.callsign or "") .. "]", function()
            Cl.send("radio_claim_drop", { id = nearDrop.id }, playerNum)
        end)
        return
    end
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
    option(submenu,L.ui("menu_open_radio","[A-LIFE] Caravan Radio & Dispatch (101.6 MHz)"),function()
        if A.Style and type(A.Style.openRadioWindow) == "function" then A.Style.openRadioWindow(playerNum, "airwaves") end
    end)
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
        if A.settings.fieldServices and not entry.hostile then
            if entry.needsRepair then
                option(submenu, L.ui("panel_repair", "Help repair / refuel"), send("assist_repair"))
            end
            if entry.kind == "rescue" or entry.eventType == "medical_aid" then
                option(submenu, L.ui("panel_aid", "Request field first aid"), send("field_aid"))
            end
            if entry.eventType == "refugees" then
                option(submenu, L.ui("panel_donate", "Donate relief supplies"), send("donate_supplies"))
            end
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
        local defaultKey = (type(Keyboard) == "table" and Keyboard.KEY_F9) or 67
        local radioKey = options.addKeyBind and options:addKeyBind("radioKey", "UI_ALC_Opt_RadioKey", defaultKey, "UI_ALC_Opt_RadioKey_tt") or nil
        options.apply = function()
            Cl.options.menu = menu:getValue() ~= false
            Cl.options.notices = notices:getValue() ~= false
            A.Map.options.worldMap = worldMap:getValue() ~= false
            A.Map.options.minimap = minimap:getValue() ~= false
            A.Map.options.labels = labels:getValue() ~= false
            if radioKey and type(radioKey.getValue) == "function" then
                Cl.options.radioKey = tonumber(radioKey:getValue()) or defaultKey
            end
        end
        options:apply()
    end)
    if not ok then A.fail("mod options", err) end
end

function Cl.onWeaponAttack(attacker, weapon)
    if attacker == nil or A.Ballistics == nil or type(A.Ballistics.findAimedCaravanVehicle) ~= "function" then return end
    local localPl = player0()
    if localPl ~= nil and attacker ~= localPl then return end
    local vehicleId, damage, isRanged = A.Ballistics.findAimedCaravanVehicle(attacker, weapon)
    if vehicleId ~= nil then
        Cl.send("vehicleShot", { vehicleId = vehicleId, damage = damage, ranged = isRanged }, attacker.getPlayerNum and attacker:getPlayerNum() or 0)
    end
end

if not A.clientRegistered then
    A.clientRegistered = true
    Cl.installOptions()
    A.log("v" .. A.VERSION .. " client loaded")
    if type(Events) == "table" then
        if Events.OnFillInventoryObjectContextMenu then Events.OnFillInventoryObjectContextMenu.Add(Cl.fillInventoryMenu) end
        if Events.OnFillWorldObjectContextMenu then Events.OnFillWorldObjectContextMenu.Add(Cl.fill) end
        if Events.OnServerCommand then Events.OnServerCommand.Add(Cl.receive) end
        if Events.OnKeyPressed then Events.OnKeyPressed.Add(function(k) pcall(Cl.onKeyPressed, k) end) end
        if Events.OnTick then Events.OnTick.Add(function() pcall(Cl.tick) end) end
        if Events.OnGameStart then Events.OnGameStart.Add(function() pcall(A.Map.install) end) end
        if Events.OnWeaponSwingHitPoint then
            Events.OnWeaponSwingHitPoint.Add(function(attacker, weapon) pcall(Cl.onWeaponAttack, attacker, weapon) end)
        elseif Events.OnWeaponSwing then
            Events.OnWeaponSwing.Add(function(attacker, weapon) pcall(Cl.onWeaponAttack, attacker, weapon) end)
        end
    end
end

return Cl
