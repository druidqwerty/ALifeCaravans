-- Trade presentation; transactions stay in the authoritative interaction service.
return function(Cl, player0)
local A = ALifeCaravans
local L, T = A.Lines, A.Trade
local U = require "ALifeCaravans/ALC_Style"
local Paint = require "ALifeCaravans/ALC_TradePaint"
require "ISUI/ISTextEntryBox"
-- ------------------------------------------------------------- trade window
local function tradableInventory(player)
    local rows, seen = {}, {}
    for _, candidate in ipairs(T.inventoryItems(player)) do
        local fullType = candidate.type
        if seen[fullType] == nil then
            local row = { type = fullType, name = T.name(fullType), count = 0 }
            seen[fullType] = row
            rows[#rows + 1] = row
        end
        seen[fullType].count = seen[fullType].count + 1
    end
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
        local top = 150
        local half = math.floor((self.width - 30) / 2)
        self.theyLabel = L.ui("they_sell", "They sell (price)")
        self.youLabel = L.ui("you_offer", "You offer (they pay)")
        self.sellList = ISScrollingListBox:new(10, top + 20, half, self.height - top - 110)
        self.sellList:initialise()
        self.sellList:instantiate()
        self.sellList.itemheight = math.max(48, getTextManager():getFontHeight(UIFont.Small)*2+12)
        self.sellList.font = UIFont.Small
        self.sellList.doDrawItem = function(list, y, item, alt) return self:drawRow(list, y, item, alt) end
        self.sellList.onMouseDown = function(list, x, y) return self:clickRow(list, x, y, "take") end
        self:addChild(self.sellList)
        self.giveList = ISScrollingListBox:new(20 + half, top + 20, half, self.height - top - 110)
        self.giveList:initialise()
        self.giveList:instantiate()
        self.giveList.itemheight = self.sellList.itemheight
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
        self.searchHeight = math.max(24,getTextManager():getFontHeight(UIFont.Small)+8)
        for i,list in ipairs({self.sellList,self.giveList}) do
            local search=ISTextEntryBox:new("",12,136,half,self.searchHeight)
            search:initialise()
            search:instantiate()
            search:setPlaceholderText(L.ui("search_items","Search items..."))
            search:setClearButton(true)
            search.onTextChange=function() self:filterLists() end
            self:addChild(search)
            if i==1 then self.sellSearch=search else self.giveSearch=search end
            U.entry(search)
            list.onRightMouseDown=function(box,x,y)
                local index=box:rowAt(x,y)
                if index and index>=1 and index<=#box.items then self:selectRow(box,index,-1) end
                return true
            end
            list.prerender=function(box)
                ISScrollingListBox.prerender(box)
                if #box.items==0 then
                    U.text(box,L.ui("no_matches","No matching items"),10,12-box:getYScroll(),U.palette().muted)
                end
            end
        end
        U.button(self.tradeButton,true)
        U.button(self.clearButton)
        U.button(self.closeButton)
        self.tradeButton.tooltip=L.ui("quantity_hint","Click to add; right-click to remove. Hold Shift for five.")
        self.minimumWidth,self.minimumHeight=600,450
        Paint.layout(self)
        self.joyList = self.sellList
        self:refresh()
    end

    function ALCTradeWindow:drawRow(list, y, item, alt)
        return Paint.row(self,list,y,item,alt)
    end

    function ALCTradeWindow:clickRow(list, x, y, side)
        local index = list:rowAt(x, y)
        if type(index) ~= "number" or index < 1 or index > #list.items then return true end
        list.selected=index
        self:selectRow(list,index,x>=list.width-100 and x<list.width-60 and -1 or 1)
        return true
    end

    function ALCTradeWindow:selectRow(list, index, delta)
        if list.items[index] == nil then return end
        local row = list.items[index].item
        local step=(type(isShiftKeyDown)=="function" and isShiftKeyDown()) and 5 or 1
        local selected = (tonumber(row.selected) or 0) + (delta or 1)*step
        if selected > math.min(999,row.count) then selected = delta==nil and 0 or math.min(999,row.count) end
        selected=math.max(0,selected)
        row.selected = selected
        self:updateSummary()
    end

    function ALCTradeWindow:selection()
        local take, give = {}, {}
        for _, row in ipairs(self.sellRows or {}) do
            if (tonumber(row.selected) or 0) > 0 then take[row.index] = row.selected end
        end
        for _, row in ipairs(self.giveRows or {}) do
            if (tonumber(row.selected) or 0) > 0 then give[#give + 1] = { type = row.type, count = row.selected } end
        end
        return take, give
    end

    function ALCTradeWindow:updateSummary()
        local take, give = self:selection()
        local stock = {}
        for _, row in ipairs(self.sellRows or {}) do stock[row.index] = row end
        local quote = T.quote(stock, self.kind, self.favor, take, give)
        self.quote = quote
        if self.tradeButton then self.tradeButton:setEnable(quote.ok==true) end
    end

    function ALCTradeWindow:refresh()
        local view = Cl.stock[self.vehicleId]
        self.sellRows,self.giveRows={},{}
        self.sellList:clear()
        self.giveList:clear()
        if view == nil then return end
        self.kind, self.favor, self.revision = view.kind, view.favor, view.revision
        for _, row in ipairs(view.rows or {}) do
            self.sellRows[#self.sellRows+1]={ index = row.index, item = row.item, name = row.name, count = row.count, price = row.price,
                value = row.price / (T.rateFor(view.kind).sell * T.favorFactor(view.favor)), selected = 0 }
        end
        local player = player0(self.playerNum)
        for _, row in ipairs(tradableInventory(player)) do
            local price = T.buyPrice(row.type, view.kind)
            if price > 0 then
                self.giveRows[#self.giveRows+1]={ type = row.type, name = row.name, count = row.count, price = price, selected = 0 }
            end
        end
        self:filterLists()
        self:updateSummary()
    end

    function ALCTradeWindow:filterLists()
        for i,list in ipairs({self.sellList,self.giveList}) do
            local search=i==1 and self.sellSearch or self.giveSearch
            local query=string.lower(search and search:getText() or "")
            list:clear()
            for _,row in ipairs(i==1 and self.sellRows or self.giveRows or {}) do
                if query=="" or string.find(string.lower(row.name),query,1,true) then list:addItem(row.name,row) end
            end
        end
    end

    function ALCTradeWindow:onResize()
        ISCollapsableWindow.onResize(self)
        Paint.layout(self)
    end

    function ALCTradeWindow:prerender()
        ISCollapsableWindow.prerender(self)
        Paint.window(self,A.Convoy.entry(self.vehicleId) or Cl.stock[self.vehicleId] or {})
    end

    function ALCTradeWindow:onTrade()
        if self.quote == nil or not self.quote.ok then return end
        local take, give = self:selection()
        if A.isEmpty(take) and #give == 0 then return end
        Cl.send("deal", { vehicleId = self.vehicleId, take = take, give = give, revision = self.revision }, self.playerNum)
    end

    function ALCTradeWindow:onClear()
        self:refresh()
    end

    function ALCTradeWindow:onClose()
        self:setVisible(false)
        self:removeFromUIManager()
        if Cl.window == self then Cl.window = nil end
        if self.joyfocus and type(setJoypadFocus) == "function" then setJoypadFocus(self.playerNum or 0, nil) end
    end

    function ALCTradeWindow:close() self:onClose() end

    function ALCTradeWindow:onGainJoypadFocus(joypadData)
        self.joyfocus = joypadData
        self.joyList = self.joyList or self.sellList
        self.joyList.selected = math.max(1, self.joyList.selected or 1)
        self.tradeButton:setJoypadButton(Joypad.Texture.XButton)
        self.clearButton:setJoypadButton(Joypad.Texture.YButton)
        self.closeButton:setJoypadButton(Joypad.Texture.BButton)
    end

    function ALCTradeWindow:onLoseJoypadFocus() self.joyfocus = nil end
    function ALCTradeWindow:onJoypadDirLeft() self.joyList = self.sellList end
    function ALCTradeWindow:onJoypadDirRight() self.joyList = self.giveList end
    function ALCTradeWindow:onJoypadDirUp() self.joyList:onJoypadDirUp() end
    function ALCTradeWindow:onJoypadDirDown() self.joyList:onJoypadDirDown() end
    function ALCTradeWindow:onJoypadDown(button)
        if button == Joypad.AButton then self:selectRow(self.joyList, self.joyList.selected or 1)
        elseif button == Joypad.XButton then self:onTrade()
        elseif button == Joypad.YButton then self:onClear()
        elseif button == Joypad.BButton then self:onClose() end
    end
end

end
