-- A-Life: Caravans - client side. The right-click menu on a caravan car, the
-- barter window, the exchange itself (the player's inventory belongs to the
-- client; the server quotes, reserves and commits per transaction id), gifts,
-- server notices, headlight-flash hails, map markers and the per-player options
-- (Options > Mods). Which cars are caravans comes from the world owner: directly
-- in single player, by the "state" command in multiplayer.

require "ALifeCaravans/00_ALC_Core"
require "ALifeCaravans/01_ALC_Lines"
require "ALifeCaravans/04_ALC_Convoy"
require "ALifeCaravans/05_ALC_Trade"
require "ALifeCaravans/ALC_Map"

local A = ALifeCaravans
local Cl = { options = { menu = true, notices = true }, requestedAtMs = 0, stock = {}, done = {}, flashes = {}, window = nil }
A.Client = Cl
local L = A.Lines
local T = A.Trade

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

local function addSome(inventory, fullType, count)
    local added = 0
    for _ = 1, count do
        local ok = pcall(function() inventory:AddItem(fullType) end)
        if ok then added = added + 1 end
    end
    return added
end

-- Execute a reserved deal exactly once: check every offered item, remove the
-- offered items, add the bought ones, acknowledge with the transaction id.
function Cl.performDeal(args)
    local player = player0()
    if player == nil or type(args) ~= "table" then return end
    local txId = tostring(args.txId or "")
    if Cl.done[txId] then return end
    Cl.done[txId] = true
    local inventory = player:getInventory()
    local ok = true
    for _, row in ipairs(args.give or {}) do
        if countOf(inventory, row.type) < (tonumber(row.count) or 0) then ok = false end
    end
    if ok then
        for _, row in ipairs(args.give or {}) do
            if not removeSome(inventory, row.type, tonumber(row.count) or 0) then ok = false end
        end
    end
    if ok then
        for _, row in ipairs(args.take or {}) do addSome(inventory, row.item, tonumber(row.count) or 0) end
    end
    local reply = args.toll == true and "tollDone" or "dealDone"
    Cl.send(reply, { vehicleId = args.vehicleId, txId = txId, ok = ok })
    if ok then
        if args.toll == true then
            Cl.notice(L.ui("toll_paid", "Toll paid: {price}", { price = args.credit }))
        else
            local bought = {}
            for _, row in ipairs(args.take or {}) do bought[#bought + 1] = tostring(row.count) .. "x " .. tostring(row.name or row.item) end
            local paid = {}
            for _, row in ipairs(args.give or {}) do paid[#paid + 1] = tostring(row.count) .. "x " .. tostring(row.name or row.type) end
            Cl.notice(L.ui("dealt", "Traded {paid} for {bought}", { paid = table.concat(paid, ", "), bought = #bought > 0 and table.concat(bought, ", ") or "-" }))
        end
    else
        Cl.notice(L.ui("broke", "Not enough to pay ({price} needed)", { price = args.cost or 0 }))
    end
    if Cl.window ~= nil then Cl.window:refresh() end
end

function Cl.receiveGift(args)
    local player = player0()
    if player == nil or type(args) ~= "table" or type(args.item) ~= "string" then return end
    local added = addSome(player:getInventory(), args.item, tonumber(args.count) or 1)
    if added > 0 then Cl.notice(L.ui("received", "Received {item}", { item = tostring(added) .. "x " .. tostring(args.name or args.item) })) end
end

-- ------------------------------------------------------------- trade window
local function tradableInventory(player)
    local rows, seen = {}, {}
    pcall(function()
        local items = player:getInventory():getItems()
        for index = 0, items:size() - 1 do
            local item = items:get(index)
            local fullType = item:getFullType()
            if not seen[fullType] and item:getContainer() == player:getInventory() then
                seen[fullType] = true
                rows[#rows + 1] = { type = fullType, name = item:getDisplayName(), count = countOf(player:getInventory(), fullType) }
            end
        end
    end)
    table.sort(rows, function(a, b) return a.name < b.name end)
    return rows
end

ALCTradeWindow = ALCTradeWindow or (type(ISCollapsableWindow) == "table" and ISCollapsableWindow:derive("ALCTradeWindow") or nil)

if ALCTradeWindow ~= nil then
    function ALCTradeWindow:initialise()
        ISCollapsableWindow.initialise(self)
    end

    function ALCTradeWindow:createChildren()
        ISCollapsableWindow.createChildren(self)
        local top = 24
        local half = math.floor((self.width - 30) / 2)
        self.theyLabel = L.ui("they_sell", "They sell (price)")
        self.youLabel = L.ui("you_offer", "You offer (they pay)")
        self.sellList = ISScrollingListBox:new(10, top + 20, half, self.height - top - 110)
        self.sellList:initialise()
        self.sellList:instantiate()
        self.sellList.itemheight = 22
        self.sellList.font = UIFont.Small
        self.sellList.doDrawItem = function(list, y, item, alt) return self:drawRow(list, y, item, alt) end
        self.sellList.onMouseDown = function(list, x, y) return self:clickRow(list, x, y, "take") end
        self:addChild(self.sellList)
        self.giveList = ISScrollingListBox:new(20 + half, top + 20, half, self.height - top - 110)
        self.giveList:initialise()
        self.giveList:instantiate()
        self.giveList.itemheight = 22
        self.giveList.font = UIFont.Small
        self.giveList.doDrawItem = function(list, y, item, alt) return self:drawRow(list, y, item, alt) end
        self.giveList.onMouseDown = function(list, x, y) return self:clickRow(list, x, y, "give") end
        self:addChild(self.giveList)
        self.tradeButton = ISButton:new(10, self.height - 34, 110, 24, L.ui("trade_button", "Trade"), self, ALCTradeWindow.onTrade)
        self.tradeButton:initialise()
        self:addChild(self.tradeButton)
        self.clearButton = ISButton:new(130, self.height - 34, 110, 24, L.ui("clear_button", "Clear"), self, ALCTradeWindow.onClear)
        self.clearButton:initialise()
        self:addChild(self.clearButton)
        self.closeButton = ISButton:new(self.width - 120, self.height - 34, 110, 24, L.ui("close_button", "Close"), self, ALCTradeWindow.onClose)
        self.closeButton:initialise()
        self:addChild(self.closeButton)
        self:refresh()
    end

    function ALCTradeWindow:drawRow(list, y, item, alt)
        local row = item.item
        local selected = tonumber(row.selected) or 0
        if selected > 0 then list:drawRect(0, y, list:getWidth(), list.itemheight - 1, 0.35, 0.3, 0.6, 0.3) end
        list:drawRectBorder(0, y, list:getWidth(), list.itemheight - 1, 0.25, 1, 1, 1)
        local text = tostring(row.name) .. "  x" .. tostring(row.count) .. "  (" .. tostring(row.price) .. ")"
        if selected > 0 then text = text .. "   -> " .. tostring(selected) end
        list:drawText(text, 6, y + 4, 1, 1, 1, 0.95, list.font)
        return y + list.itemheight
    end

    function ALCTradeWindow:clickRow(list, x, y, side)
        local index = list:rowAt(x, y)
        if index < 1 or index > #list.items then return true end
        local row = list.items[index].item
        local selected = (tonumber(row.selected) or 0) + 1
        if selected > row.count then selected = 0 end
        row.selected = selected
        self:updateSummary()
        return true
    end

    function ALCTradeWindow:selection()
        local take, give = {}, {}
        for _, item in ipairs(self.sellList.items) do
            local row = item.item
            if (tonumber(row.selected) or 0) > 0 then take[row.index] = row.selected end
        end
        for _, item in ipairs(self.giveList.items) do
            local row = item.item
            if (tonumber(row.selected) or 0) > 0 then give[#give + 1] = { type = row.type, count = row.selected } end
        end
        return take, give
    end

    function ALCTradeWindow:updateSummary()
        local take, give = self:selection()
        local stock = {}
        for _, item in ipairs(self.sellList.items) do stock[item.item.index] = { item = item.item.item, name = item.item.name, value = item.item.value, count = item.item.count } end
        local quote = T.quote(stock, self.kind, self.favor, take, give)
        self.quote = quote
    end

    function ALCTradeWindow:refresh()
        local view = Cl.stock[self.vehicleId]
        self.sellList:clear()
        self.giveList:clear()
        if view == nil then return end
        self.kind, self.favor = view.kind, view.favor
        for _, row in ipairs(view.rows or {}) do
            self.sellList:addItem(row.name, { index = row.index, item = row.item, name = row.name, count = row.count, price = row.price,
                value = row.price / (T.rateFor(view.kind).sell * T.favorFactor(view.favor)), selected = 0 })
        end
        local player = player0()
        for _, row in ipairs(tradableInventory(player)) do
            local price = T.buyPrice(row.type, view.kind)
            if price > 0 then
                self.giveList:addItem(row.name, { type = row.type, name = row.name, count = row.count, price = price, selected = 0 })
            end
        end
        self:updateSummary()
    end

    function ALCTradeWindow:prerender()
        ISCollapsableWindow.prerender(self)
        self:drawText(self.theyLabel, 10, 26, 1, 1, 1, 1, UIFont.Small)
        self:drawText(self.youLabel, 20 + math.floor((self.width - 30) / 2), 26, 1, 1, 1, 1, UIFont.Small)
        local quote = self.quote
        if quote ~= nil then
            local line = L.ui("summary", "Cost {cost}  /  your goods {credit}  /  balance {balance}",
                { cost = quote.cost or 0, credit = quote.credit or 0, balance = quote.balance or 0 })
            local color = quote.ok and { 0.6, 1, 0.6 } or { 1, 0.7, 0.6 }
            self:drawText(line, 10, self.height - 60, color[1], color[2], color[3], 1, UIFont.Small)
        end
    end

    function ALCTradeWindow:onTrade()
        local take, give = self:selection()
        if A.isEmpty(take) and #give == 0 then return end
        Cl.send("deal", { vehicleId = self.vehicleId, take = take, give = give })
    end

    function ALCTradeWindow:onClear()
        self:refresh()
    end

    function ALCTradeWindow:onClose()
        self:setVisible(false)
        self:removeFromUIManager()
        if Cl.window == self then Cl.window = nil end
    end
end

function Cl.openTrade(vehicleId)
    if ALCTradeWindow == nil then return false end
    if Cl.window ~= nil then Cl.window:onClose() end
    local ok, err = pcall(function()
        local width, height = 620, 400
        local x = math.floor((getCore():getScreenWidth() - width) / 2)
        local y = math.floor((getCore():getScreenHeight() - height) / 2)
        local window = ALCTradeWindow:new(x, y, width, height)
        window.vehicleId = vehicleId
        local view = Cl.stock[vehicleId]
        window:setTitle(L.ui("trade_title", "Caravan trade: {leader} ({callsign})", { leader = view and view.leader or "?", callsign = view and view.callsign or "" }))
        window:initialise()
        window:addToUIManager()
        window:setVisible(true)
        Cl.window = window
    end)
    if not ok then A.fail("trade window", err) return false end
    return true
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
        if type(args) == "table" and args.vehicleId ~= nil then
            Cl.stock[args.vehicleId] = args
            if Cl.window ~= nil and Cl.window.vehicleId == args.vehicleId then Cl.window:refresh() else Cl.openTrade(args.vehicleId) end
        end
    elseif command == "dealOk" then
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
    local root = context:addOption(L.ui("menu", "[A-LIFE] Caravan: {name} ({kind})", { name = entry.callsign and (entry.name .. " " .. entry.callsign) or entry.name, kind = kind }))
    local submenu = context:getNew(context)
    context:addSubMenu(root, submenu)
    local function send(command) return function() Cl.send(command, { vehicleId = id }) end end
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
    if vehicle == nil then Cl.flashState = nil return end
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
