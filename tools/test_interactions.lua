-- Isolated interaction regression suite; run after test_alc.lua's game stubs.
local A = ALifeCaravans
local T, I, Cl = A.Trade, A.Interact, A.Client
local failed, passed = 0, 0
local function check(name, condition)
    if condition then passed = passed + 1 else failed = failed + 1 print("FAIL interaction: " .. name) end
end
local oldServer, oldClient = isServer, isClient
local oldAdd, oldRemove, oldSpecific = sendAddItemToContainer, sendRemoveItemFromContainer, getSpecificPlayer
local oldByVehicle, oldFavor, oldAddFavor = A.Ledger.byVehicle, A.Ledger.favor, A.Ledger.addFavor
local oldSay, oldReply, oldStance = I.say, I.reply, I.stanceFor
local oldResume, oldVars, oldTouch = A.Director.resume, A.Director.vars, A.Ledger.touch
local oldSettings, oldMetrics = A.settings, A.metrics
local settings, metrics = {}, {}
for key, value in pairs(oldSettings) do settings[key] = value end
for key, value in pairs(oldMetrics) do metrics[key] = value end
A.settings, A.metrics = settings, metrics
A.settings.tradeEnabled, A.settings.playerCanFormCaravan = true, true
local synced, replies, favor = {}, {}, 0
function isServer() return true end
function isClient() return false end
function sendAddItemToContainer(container, item) synced[#synced + 1] = { "add", item } end
function sendRemoveItemFromContainer(container, item) synced[#synced + 1] = { "remove", item } end
local function inventory()
    local inv = { items = {} }
    function inv:getItems()
        return { size = function() return #self.items end, get = function(_, index) return self.items[index + 1] end }
    end
    function inv:AddItem(value)
        if value == self.failType then return nil end
        local item = value
        if type(value) == "string" then
            item = { fullType = value }
            function item:getFullType() return self.fullType end
            function item:getContainer() return self.container end
            function item:isFavorite() return self.favorite == true end
            function item:getInventory() return self.inside end
        end
        item.container = self
        self.items[#self.items + 1] = item
        return item
    end
    function inv:Remove(item)
        if self.refuseRemove == item then return end
        for index, candidate in ipairs(self.items) do
            if candidate == item then table.remove(self.items, index) item.container = nil return end
        end
    end
    function inv:count(fullType)
        local count = 0
        for _, item in ipairs(self.items) do if item.fullType == fullType then count = count + 1 end end
        return count
    end
    return inv
end
local function player(index)
    local p = { inventory = inventory(), index = index or 0, x = 10, y = 10, z = 0 }
    function p:getInventory() return self.inventory end
    function p:getPlayerNum() return self.index end
    function p:getUsername() return "audit" .. tostring(self.index) end
    function p:getX() return self.x end
    function p:getY() return self.y end
    function p:getZ() return self.z end
    function p:isDead() return self.dead == true end
    function p:isEquipped(item) return self.equipped == item end
    return p
end
local p = player(0)
-- Generic InventoryItem and script Item omit subclass-only Java methods.
-- A caught missing-method call still pollutes the real Kahlua error log.
local sparsePlayer = player(9)
sparsePlayer.inventory:AddItem({ getFullType = function() return "Base.Money" end })
local realPcall, oldScripts, caught = pcall, getScriptManager, 0
pcall = function(fn, ...)
    local ok, a, b, c = realPcall(fn, ...)
    if not ok then caught = caught + 1 end
    return ok, a, b, c
end
getScriptManager = function()
    return { getItem = function() return { getDisplayCategory = function() return "Food" end } end }
end
local sparseItems, sparseValue = T.inventoryItems(sparsePlayer), T.valueOf("Audit.SparseItem")
pcall, getScriptManager = realPcall, oldScripts
check("optional Java getters do not throw caught errors", caught == 0 and #sparseItems == 1 and sparseValue > 0)
function getSpecificPlayer(index) if index == 0 then return p end end
local c = { id = "audit", kind = "trade", class = "civilian", factionId = "audit", vehicleIds = { 777 }, actorUids = { "a", "b", "c" },
    x = 10, y = 10, state = "rendered", halted = true, stock = {} }
A.Ledger.byVehicle = function(id) if id == 777 then return c end end
A.Ledger.favor = function() return favor end
A.Ledger.addFavor = function(_, _, n) favor = favor + n end
A.Ledger.touch = function() end
A.Director.resume = function(caravan) caravan.halted = nil end
A.Director.vars = function() return {} end
I.say = function() end
I.stanceFor = function() return "neutral" end
I.reply = function(who, command, args) replies[#replies + 1] = { who = who, command = command, args = args } end
local stock = { { item = "Base.Bandage", name = "Bandage", value = 10, count = 3 } }
check("non-table request rejected", not T.quote(stock, "trade", 0, "bad", {}).ok)
check("invalid offer rejected", not T.quote(stock, "trade", 0, {}, { 17 }).ok)
check("NaN rejected", not T.quote(stock, "trade", 0, { [1] = 0/0 }, {}).ok)
check("infinity rejected", not T.quote(stock, "trade", 0, { [1] = math.huge }, {}).ok)
check("fraction rejected", not T.quote(stock, "trade", 0, { [1] = 1.5 }, {}).ok)
check("aliased index rejected", not T.quote(stock, "trade", 0, { [1] = 1, ["1"] = 1 }, {}).ok)
local q = T.quote(stock, "trade", 0, { [1] = 1 }, { { type = "Base.Money", count = 5 }, { type = "Base.Money", count = 5 } })
check("duplicate offers aggregated", q.ok and #q.giveRows == 1 and q.giveRows[1].count == 10)
for _ = 1, 5 do p.inventory:AddItem("Base.Money") end
check("aggregate payment validated before mutation", not T.exchange(p, q) and p.inventory:count("Base.Money") == 5 and p.inventory:count("Base.Bandage") == 0)
for _ = 1, 5 do p.inventory:AddItem("Base.Money") end
p.inventory.failType = "Base.Bandage"
check("missing output preserves money", not T.exchange(p, q) and p.inventory:count("Base.Money") == 10 and #synced == 0)
p.inventory.failType = nil
p.inventory.refuseRemove = p.inventory.items[2]
local original = p.inventory.items[1]
check("partial removal rolls back", not T.exchange(p, q) and p.inventory:count("Base.Money") == 10 and p.inventory:count("Base.Bandage") == 0 and original.container == p.inventory and #synced == 0)
p.inventory.refuseRemove = nil
check("server exchanges exact inventory", T.exchange(p, q) and p.inventory:count("Base.Money") == 0 and p.inventory:count("Base.Bandage") == 1)
check("vanilla server replication", #synced == 11 and synced[1][1] == "remove" and synced[11][1] == "add")
local bag = p.inventory:AddItem("Base.Bag")
bag.inside = inventory()
bag.inside:AddItem("Base.Money")
local favorite = p.inventory:AddItem("Base.Hammer") favorite.favorite = true
local equipped = p.inventory:AddItem("Base.Axe") p.equipped = equipped
local loadedGun = p.inventory:AddItem("Base.Pistol")
function loadedGun:getCurrentAmmoCount() return 7 end
local eligible = {}
for _, row in ipairs(T.inventoryItems(p)) do eligible[row.type] = true end
check("nested currency available", eligible["Base.Money"] == true)
check("full bag protected", eligible["Base.Bag"] == nil)
check("favorite protected", eligible["Base.Hammer"] == nil)
check("equipped protected", eligible["Base.Axe"] == nil)
check("loaded firearm protected", eligible["Base.Pistol"] == nil)
function isServer() return false end
function isClient() return true end
check("client cannot exchange inventory", not T.exchange(p, { giveRows = {}, takeRows = { { item = "Base.Money", count = 1 } } }))
function isServer() return true end
function isClient() return false end
p.inventory = inventory()
for _ = 1, 40 do p.inventory:AddItem("Base.Money") end
c.stock = { { item = "Base.Bandage", name = "Bandage", value = 10, count = 3 } }
I.command(p, "deal", { vehicleId = 777, revision = 0, take = { [1] = 1 }, give = { { type = "Base.Money", count = 10 } } })
check("server deal commits", c.stock[1].count == 2 and p.inventory:count("Base.Money") == 30 and p.inventory:count("Base.Bandage") == 1)
check("stock refresh identifies car", replies[#replies].command == "stock" and replies[#replies].args.vehicleId == 777)
I.command(p, "deal", { vehicleId = 777, revision = 0, take = { [1] = 1 }, give = { { type = "Base.Money", count = 10 } } })
check("stale/double click rejected", c.stock[1].count == 2 and p.inventory:count("Base.Money") == 30)
local beforeFavor = favor
I.command(p, "give_supplies", { vehicleId = 777, give = { { type = "Base.Antibiotics", count = 50 } } })
check("fake supplies do not mint stock/favor", #c.stock == 1 and favor == beforeFavor)
I.command(p, "give_supplies", { vehicleId = 777, give = { { type = "Base.Bandage", count = 1 } } })
check("supplies actually consumed", p.inventory:count("Base.Bandage") == 0 and c.stock[1].count == 3)
c.toll = { audit0 = A.now() + 10000 }
I.command(p, "toll", { vehicleId = 777 })
check("failed toll remains payable", c.toll.audit0 ~= nil and c.truce == nil)
for _ = 1, 30 do p.inventory:AddItem("Base.Money") end
I.command(p, "toll", { vehicleId = 777 })
check("toll is paid on server", p.inventory:count("Base.Money") == 0 and c.truce.audit0 ~= nil and c.toll.audit0 == nil)
local paidUntil = c.truce.audit0
I.command(p, "tollDone", { vehicleId = 777, txId = "fake", ok = true })
I.command(p, "dealDone", { vehicleId = 777, txId = "fake", ok = true })
check("forged acknowledgements do nothing", c.truce.audit0 == paidUntil and p.inventory:count("Base.Money") == 0)
c.halted = true
I.command(p, "recruit_npc", { vehicleId = 777 })
I.command(p, "form_caravan", { vehicleId = 777 })
check("unsupported recruitment preserves crew", #c.actorUids == 3 and A.metrics.playerCaravans == oldMetrics.playerCaravans)
p.z = 1
check("different floor rejected", not I.within(p, c))
p.z = 0
p.dead = true
I.command(p, "deal", { vehicleId = 777, take = {}, give = { { type = "Base.Money", count = 1 } } })
check("dead player does not interact", p.inventory:count("Base.Money") == 0)
p.dead = false
-- Replaying receipts must never mutate inventory (including old dealOk).
local beforeCount = #p.inventory.items
Cl.receive(A.MODULE, "dealOk", { txId = "legacy", give = {}, take = { { item = "Base.Money", count = 999 } } })
Cl.performDeal({ txId = "replay", give = {}, take = { { item = "Base.Money", count = 999 } } })
Cl.performDeal({ txId = "replay", give = {}, take = { { item = "Base.Money", count = 999 } } })
check("receipts cannot mint items", #p.inventory.items == beforeCount)
I.reply = oldReply
local originalSendServer = sendServerCommand
sendServerCommand = function() end
I.reply(p, "gift", { item = "Base.Money", count = 2 })
check("gifts are delivered by world owner", p.inventory:count("Base.Money") == 2)
sendServerCommand = originalSendServer

-- Exercise methods of the real client file, with the engine UI object mocked.
local oldWindow, oldJoypad, oldSetFocus = ALCTradeWindow, Joypad, setJoypadFocus
ALCTradeWindow = {}
Joypad = { AButton = 1, BButton = 2, XButton = 3, YButton = 4, Texture = { XButton = "X", YButton = "Y", BButton = "B" } }
local currentFocus, sent
function setJoypadFocus(index, window) currentFocus = window end
local loadedClient = assert(loadfile(MOD_ROOT .. "/42/media/lua/client/ALifeCaravans/ALC_Client.lua"))()
loadedClient.send = function(command, args, index) sent = { command = command, args = args, index = index } end
local function list()
    return { items = {}, selected = 1, onJoypadDirUp = function(self) self.selected = 1 end,
        onJoypadDirDown = function(self) self.selected = #self.items end }
end
local win = setmetatable({ sellList = list(), giveList = list(), playerNum = 1, vehicleId = 777, revision = 4 }, { __index = ALCTradeWindow })
win.joyList = win.sellList
win.updateSummary = function() end
check("gamepad empty list safe", pcall(win.onJoypadDown, win, Joypad.AButton))
win.sellList.items = { { item = { count = 2, selected = 0, index = 1 } } }
win.sellRows={win.sellList.items[1].item}
win.giveRows={}
win:onJoypadDown(Joypad.AButton)
check("gamepad A selects quantity", win.sellList.items[1].item.selected == 1)
win:onJoypadDirRight()
check("gamepad switches offer column", win.joyList == win.giveList)
win.quote = { ok = true }
win:onJoypadDown(Joypad.XButton)
check("gamepad trade preserves player/revision", sent and sent.command == "deal" and sent.index == 1 and sent.args.revision == 4)
-- Filtering must not silently throw away (or stop quoting) hidden basket rows.
win.sellRows[1].name="Bandage"
win.sellRows[2]={index=2,name="Hammer",count=3,selected=2}
win.giveRows={{type="Base.Money",name="Money",count=2000,selected=50}}
for _,box in ipairs({win.sellList,win.giveList}) do
    box.clear=function(self) self.items={} end
    box.addItem=function(self,name,row) self.items[#self.items+1]={item=row} end
end
win.sellSearch={getText=function() return "Hammer" end}
win.giveSearch={getText=function() return "No matching item" end}
win:filterLists()
check("search filters only presentation",#win.sellList.items==1 and #win.giveList.items==0)
local take,give=win:selection()
check("hidden basket choices remain in authoritative offer",take[1]==1 and take[2]==2 and give[1].count==50)
win:onJoypadDown(Joypad.XButton)
check("filtered trade still sends the whole offer",sent.args.take[1]==1 and sent.args.give[1].count==50)
win.sellSearch.getText=function() return "" end
win.giveSearch.getText=win.sellSearch.getText
win:filterLists()
win.giveRows[1].selected=999
win:selectRow(win.giveList,1,1)
check("UI quantity respects server per-type transaction bound",win.giveRows[1].selected==999)
win:selectRow(win.giveList,1,-1)
check("quantity can be reduced without clearing whole basket",win.giveRows[1].selected==998)
win.setVisible = function() end
win.removeFromUIManager = function() end
win.joyfocus = {}
currentFocus = win
win:onJoypadDown(Joypad.BButton)
check("gamepad B restores gameplay focus", currentFocus == nil)
local oldNear = A.Convoy.near
A.Convoy.near = function() return { { id = 777, entry = { name = "Audit", kind = "trade", halted = false } } } end
local p2 = player(1)
function getSpecificPlayer(index) if index == 0 then return p elseif index == 1 then return p2 end end
local menu = { options = {} }
function menu:addOption(label, target, callback)
    local item = { label = label, callback = callback }
    self.options[#self.options + 1] = item
    return item
end
function menu:getNew() return self end
function menu:addSubMenu() end
loadedClient.fill(1, menu, {}, false)
for _,item in ipairs(menu.options) do
    if item.label==A.Lines.ui("hail","Flag them down") then item.callback() end
end
check("split-screen context belongs to its player", sent.index == 1)
check("invalid context cannot throw", pcall(loadedClient.fill, 0, {}, {}, false))
local oldWorldContext, tested = ISWorldObjectContextMenu, false
ISWorldObjectContextMenu = { setTest = function() tested = true return true end }
loadedClient.fill(1, nil, {}, true)
check("controller context discovery signals available action", tested)
ISWorldObjectContextMenu = oldWorldContext
A.Convoy.near = oldNear
ALCTradeWindow, Joypad, setJoypadFocus = oldWindow, oldJoypad, oldSetFocus
A.Client = Cl
isServer, isClient = oldServer, oldClient
sendAddItemToContainer, sendRemoveItemFromContainer, getSpecificPlayer = oldAdd, oldRemove, oldSpecific
A.Ledger.byVehicle, A.Ledger.favor, A.Ledger.addFavor = oldByVehicle, oldFavor, oldAddFavor
I.say, I.reply, I.stanceFor = oldSay, oldReply, oldStance
A.Director.resume, A.Director.vars, A.Ledger.touch = oldResume, oldVars, oldTouch
A.settings, A.metrics = oldSettings, oldMetrics
print("interaction checks passed=" .. tostring(passed) .. " failed=" .. tostring(failed))
return failed
