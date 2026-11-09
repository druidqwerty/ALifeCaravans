-- A-Life: Caravans v0.8.0 - Caravan Radio Dispatch, Supply Drop & Market Intel window.
-- Built on ISCollapsableWindow in the visual style of ALC_ContactWindow / ALC_TradeWindow.
-- Three tabs:
--   1. 101.6 MHz Airwaves (live caravan broadcasts, distress calls & market bulletins)
--   2. Supply Dispatch (order roadside supply crates or claim delivered drops)
--   3. Town Markets (regional shortage/surplus overview across towns)

require "ALifeCaravans/00_ALC_Core"
require "ALifeCaravans/01_ALC_Lines"
require "ALifeCaravans/05_ALC_Trade"
require "ALifeCaravans/07_ALC_Market"
require "ALifeCaravans/09_ALC_Radio"
require "ALifeCaravans/ALC_Style"
require "ALifeCaravans/ALC_Map"
pcall(require, "ISUI/ISCollapsableWindow")
pcall(require, "ISUI/ISButton")
pcall(require, "ISUI/ISScrollingListBox")

local A = ALifeCaravans
local U, L, R = A.Style, A.Lines, A.Radio

local Win = type(ISCollapsableWindow) == "table" and ISCollapsableWindow:derive("ALCRadioWindow") or nil
ALCRadioWindow = Win

local TABS = {
    { id = "airwaves", key = "rtab_airwaves", fallback = "101.6 MHz Airwaves" },
    { id = "dispatch", key = "rtab_dispatch", fallback = "Supply Dispatch" },
    { id = "markets",  key = "rtab_markets",  fallback = "Town Markets" },
}

local function player0(playerNum)
    if type(getSpecificPlayer) == "function" then
        local ok, p = pcall(getSpecificPlayer, tonumber(playerNum) or 0)
        if ok and p ~= nil then return p end
    end
    return A.players()[1]
end

if Win then
    function Win:createChildren()
        ISCollapsableWindow.createChildren(self)
        self.activeTab = self.activeTab or "airwaves"
        self.tabButtons = {}
        local tabW = math.floor((self.width - 24 - 12) / 3)
        for i, t in ipairs(TABS) do
            local bx = 12 + (i - 1) * (tabW + 6)
            local btn = ISButton:new(bx, 104, tabW, 28, L.ui(t.key, t.fallback), self, Win.onSelectTab)
            btn.tabId = t.id
            btn:initialise()
            U.button(btn, t.id == self.activeTab)
            self:addChild(btn)
            self.tabButtons[t.id] = btn
        end

        local listY = 140
        local listH = self.height - listY - 86
        self.list = ISScrollingListBox:new(12, listY, self.width - 24, listH)
        self.list:initialise()
        self.list:instantiate()
        self.list.itemheight = 52
        self.list.selected = 1
        self.list.backgroundColor = U.rgba(U.palette().panel)
        self.list.doDrawItem = function(box, y, item)
            return Win.drawRow(self, box, y, item)
        end
        self:addChild(self.list)

        local btnY = self.height - 76
        local btnW = math.floor((self.width - 24 - 12) / 3)
        self.btnPrimary = ISButton:new(12, btnY, btnW, 30, "", self, Win.onPrimary)
        self.btnPrimary:initialise()
        U.button(self.btnPrimary, true)
        self:addChild(self.btnPrimary)

        self.btnSecondary = ISButton:new(12 + btnW + 6, btnY, btnW, 30, "", self, Win.onSecondary)
        self.btnSecondary:initialise()
        U.button(self.btnSecondary, false)
        self:addChild(self.btnSecondary)

        self.btnMark = ISButton:new(12 + (btnW + 6) * 2, btnY, btnW, 30, L.ui("rbtn_mark_map", "Mark on Map"), self, Win.onMarkMap)
        self.btnMark:initialise()
        U.button(self.btnMark, false)
        self:addChild(self.btnMark)

        local bottomY = self.height - 38
        self.btnTune = ISButton:new(12, bottomY, 170, 26, L.ui("rbtn_tune", "Tune 101.6 MHz"), self, Win.onTune)
        self.btnTune:initialise()
        U.button(self.btnTune, false)
        self:addChild(self.btnTune)

        self.closeButton = ISButton:new(self.width - 132, bottomY, 120, 26, L.ui("close_button", "Close"), self, Win.close)
        self.closeButton:initialise()
        U.button(self.closeButton, false)
        self:addChild(self.closeButton)

        self:refresh()
    end

    function Win:onSelectTab(button)
        if button and button.tabId then
            self.activeTab = button.tabId
            self.list.selected = 1
            self:refresh()
        end
    end

    function Win:selectedRow()
        local items = self.list and self.list.items or nil
        if type(items) ~= "table" or #items == 0 then return nil end
        local idx = math.max(1, math.min(#items, tonumber(self.list.selected) or 1))
        return items[idx] and items[idx].item or nil
    end

    function Win:onTune()
        A.Client.send("radio_tune", { freq = R.frequency() }, self.playerNum)
    end

    function Win:onPrimary()
        local row = self:selectedRow()
        if self.activeTab == "airwaves" then
            A.Client.send("radio_hail_caravan", {}, self.playerNum)
        elseif self.activeTab == "dispatch" then
            if row and row.rowKind == "drop" then
                A.Client.send("radio_claim_drop", { id = row.id }, self.playerNum)
            elseif row and row.rowKind == "pkg" then
                A.Client.send("radio_supply_drop", { pkgId = row.id }, self.playerNum)
            end
        elseif self.activeTab == "markets" then
            A.Client.send("radio_market_intel", {}, self.playerNum)
        end
    end

    function Win:onSecondary()
        if self.activeTab == "airwaves" then
            A.Client.send("radio_market_intel", {}, self.playerNum)
        else
            A.Client.send("radio_hail_caravan", {}, self.playerNum)
        end
    end

    function Win:onMarkMap()
        local row = self:selectedRow()
        if not row or not tonumber(row.x) or not tonumber(row.y) then return end
        local p = player0(self.playerNum)
        local ok, why = A.Map.addSymbolNote(row.x, row.y, row.mapLabel or row.title, p)
        if ok then
            A.Client.notice(L.ui("rnotice_marked", "Marked on map: {label} ({x},{y})", {
                label = row.mapLabel or row.title, x = row.x, y = row.y
            }), self.playerNum)
        elseif why == "no_pen" then
            A.Client.notice(L.ui("err_no_pen", "Need a pen or pencil to mark coordinates on the map."), self.playerNum)
        end
    end

    function Win:refresh()
        if not self.list then return end
        self.list:clear()
        local cl = A.Client
        if self.activeTab == "airwaves" then
            for _, entry in ipairs(cl and cl.radioLog or {}) do
                local coordStr = (entry.x and entry.y) and string.format("%d, %d", entry.x, entry.y) or R.freqMhz(entry.freq)
                local row = {
                    rowKind = "air",
                    id = entry.id,
                    title = string.format("[%s] %s", R.freqMhz(entry.freq), tostring(entry.speaker or "Caravan Net")),
                    subtitle = tostring(entry.text or ""),
                    meta = coordStr,
                    x = entry.x,
                    y = entry.y,
                    mapLabel = string.format("[%s] %s", tostring(entry.speaker or "Caravan"), tostring(entry.town or "Road")),
                }
                self.list:addItem(row.title, row)
            end
            for _, m in ipairs(A.Map and A.Map.order or {}) do
                local mk = A.Map.markers[m]
                if mk ~= nil then
                    local row = {
                        rowKind = "convoy",
                        id = mk.id,
                        title = string.format("%s (%s) -> %s", tostring(mk.callsign or mk.name), tostring(mk.kind or "trade"), tostring(mk.dest or "?")),
                        subtitle = L.ui("rconvoy_sub", "Position: ({x},{y}) · Vehicles: {cars}", {
                            x = math.floor(mk.x1 or 0), y = math.floor(mk.y1 or 0), cars = tostring(mk.cars or 2)
                        }),
                        meta = mk.sos and "SOS" or tostring(mk.state or "road"),
                        x = math.floor(mk.x1 or 0),
                        y = math.floor(mk.y1 or 0),
                        mapLabel = string.format("Caravan %s -> %s", tostring(mk.callsign or mk.name), tostring(mk.dest or "?")),
                    }
                    self.list:addItem(row.title, row)
                end
            end
        elseif self.activeTab == "dispatch" then
            for _, d in ipairs(cl and cl.dispatches or {}) do
                if d.state == "ready" then
                    local row = {
                        rowKind = "drop",
                        id = d.id,
                        title = L.ui("rdrop_ready_title", "[READY DROP] {callsign} at ({x},{y})", {
                            callsign = d.callsign, x = d.x, y = d.y
                        }),
                        subtitle = L.ui("rdrop_ready_sub", "Approach within 25 tiles and click Claim Supply Drop."),
                        meta = "READY",
                        x = d.x,
                        y = d.y,
                        mapLabel = "Supply Drop " .. tostring(d.callsign or ""),
                    }
                    self.list:addItem(row.title, row)
                end
            end
            for _, pkg in ipairs(R.PACKAGES) do
                local name = L.ui(pkg.id, pkg.id)
                local desc = L.ui(pkg.id .. "_desc", "Roadside courier supply crate.")
                local row = {
                    rowKind = "pkg",
                    id = pkg.id,
                    title = string.format("%s — %s: %d", name, L.ui("rcost_label", "Credit"), pkg.cost),
                    subtitle = desc,
                    meta = R.freqMhz(),
                }
                self.list:addItem(row.title, row)
            end
        elseif self.activeTab == "markets" then
            for _, m in ipairs(cl and cl.markets or {}) do
                local sh = m.shortage and L.ui("cat_" .. tostring(m.shortage), tostring(m.shortage)) or "-"
                local sp = m.surplus and L.ui("cat_" .. tostring(m.surplus), tostring(m.surplus)) or "-"
                local row = {
                    rowKind = "market",
                    id = m.townId,
                    title = string.format("%s (%d, %d)", tostring(m.townName or m.townId), m.x or 0, m.y or 0),
                    subtitle = L.ui("rmarket_row_sub", "Shortage (+35%): {shortage} · Surplus (-15%): {surplus}", {
                        shortage = sh, surplus = sp
                    }),
                    meta = m.shortage and ("+35% " .. string.upper(tostring(m.shortage))) or "BALANCED",
                    x = m.x,
                    y = m.y,
                    mapLabel = string.format("%s: +%s", tostring(m.townName or m.townId), tostring(sh)),
                }
                self.list:addItem(row.title, row)
            end
        end
    end

    function Win:drawRow(box, y, item)
        if not item or not item.item then return y + box.itemheight end
        local row = item.item
        local c = U.palette()
        local isSel = box.selected == item.index
        if isSel then
            box:drawRect(0, y, box.width, box.itemheight - 1, 0.92, c.selected[1], c.selected[2], c.selected[3])
        else
            box:drawRect(0, y, box.width, box.itemheight - 1, 0.65, c.panel[1], c.panel[2], c.panel[3])
        end
        box:drawRectBorder(0, y, box.width, box.itemheight, 0.7, c.panelEdge[1], c.panelEdge[2], c.panelEdge[3])
        local barCol = row.rowKind == "drop" and c.good or (row.rowKind == "market" and c.warn or c.accent)
        box:drawRect(0, y, 3, box.itemheight - 1, 1, barCol[1], barCol[2], barCol[3])
        U.text(box, U.fit(row.title or "", box.width - 140, UIFont.Small), 12, y + 6, c.name, UIFont.Small)
        U.text(box, U.fit(row.subtitle or "", box.width - 28, UIFont.Small), 12, y + 27, c.text, UIFont.Small)
        if row.meta and row.meta ~= "" then
            local tw = type(getTextManager) == "function" and getTextManager():MeasureStringX(UIFont.Small, row.meta) or (#row.meta * 7)
            U.text(box, row.meta, box.width - 18 - tw, y + 6, barCol, UIFont.Small)
        end
        return y + box.itemheight
    end

    function Win:prerender()
        U.window(self)
        ISCollapsableWindow.prerender(self)
        local c = U.palette()
        U.panel(self, 12, 26, self.width - 24, 72, c)
        self:drawRect(12, 26, 3, 72, 1, c.accent[1], c.accent[2], c.accent[3])

        local p = player0(self.playerNum)
        local scan = R.scanPlayerRadios(p)
        local credit = R.countPlayerCredit(p)
        local canWrite = R.canWriteOnMap(p)

        U.text(self, L.ui("rheader_top", "CARAVAN RADIO NET & SUPPLY DISPATCH"), 22, 32, c.accent, UIFont.Small)
        local rLine = (scan.best and scan.hasPowered)
            and L.ui("rradio_on", "{name} ({freq})", { name = scan.best.name, freq = R.freqMhz(scan.best.channel) })
            or (scan.hasRadio and L.ui("rradio_off", "Radio OFF — click Tune 101.6 MHz below") or L.ui("rradio_none", "No radio found"))
        U.text(self, U.fit(rLine, self.width - 44, UIFont.Medium), 22, 50, scan.hasPowered and c.good or c.warn, UIFont.Medium)

        local metaLine = L.ui("rheader_meta", "Channel: {freq} · Barter Credit: {credit} · Pen/Pencil: {pen}", {
            freq = R.freqMhz(), credit = tostring(credit), pen = canWrite and L.ui("rpen_yes", "Ready") or L.ui("rpen_no", "None")
        })
        U.text(self, U.fit(metaLine, self.width - 44, UIFont.Small), 22, 75, c.muted, UIFont.Small)

        for id, btn in pairs(self.tabButtons or {}) do
            U.button(btn, id == self.activeTab)
        end

        local row = self:selectedRow()
        if self.activeTab == "airwaves" then
            self.btnPrimary:setTitle(L.ui("rbtn_hail_caravan", "Hail Nearest Caravan"))
            self.btnPrimary:setEnable(true)
            self.btnSecondary:setTitle(L.ui("rbtn_market_intel", "Request Market Intel"))
            self.btnSecondary:setEnable(true)
        elseif self.activeTab == "dispatch" then
            if row and row.rowKind == "drop" then
                self.btnPrimary:setTitle(L.ui("rbtn_claim_drop", "Claim Supply Drop"))
            else
                self.btnPrimary:setTitle(L.ui("rbtn_order_drop", "Order Supply Drop"))
            end
            self.btnPrimary:setEnable(row ~= nil)
            self.btnSecondary:setTitle(L.ui("rbtn_hail_caravan", "Hail Nearest Caravan"))
            self.btnSecondary:setEnable(true)
        elseif self.activeTab == "markets" then
            self.btnPrimary:setTitle(L.ui("rbtn_market_intel", "Broadcast Market Intel"))
            self.btnPrimary:setEnable(true)
            self.btnSecondary:setTitle(L.ui("rbtn_hail_caravan", "Hail Nearest Caravan"))
            self.btnSecondary:setEnable(true)
        end
        self.btnMark:setEnable(row ~= nil and tonumber(row.x) ~= nil and tonumber(row.y) ~= nil)
    end

    function Win:close()
        self:setVisible(false)
        self:removeFromUIManager()
        if A.Client and A.Client.radioWindow == self then
            A.Client.radioWindow = nil
        end
    end
end

function U.openRadioWindow(playerNum, tabId)
    if not Win then return false end
    if A.Client and A.Client.radioWindow then
        if tabId and A.Client.radioWindow.activeTab ~= tabId then
            A.Client.radioWindow.activeTab = tabId
            A.Client.radioWindow:refresh()
            return true, A.Client.radioWindow
        end
        A.Client.radioWindow:close()
        return false
    end
    local sw = type(getCore) == "function" and getCore():getScreenWidth() or 1280
    local sh = type(getCore) == "function" and getCore():getScreenHeight() or 720
    local width = math.min(680, sw - 40)
    local height = math.min(520, sh - 60)
    local x = math.floor((sw - width) / 2)
    local y = math.floor((sh - height) / 2)
    local win = Win:new(x, y, width, height)
    win.playerNum = tonumber(playerNum) or 0
    win.activeTab = tabId or "airwaves"
    win:setTitle(L.ui("rwindow_title", "A-Life: Caravans — 101.6 MHz Radio & Supply Dispatch"))
    win:initialise()
    win:addToUIManager()
    win:setVisible(true)
    win:setResizable(false)
    if A.Client then A.Client.radioWindow = win end
    return true, win
end

return U.openRadioWindow
