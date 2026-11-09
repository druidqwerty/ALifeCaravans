-- A-Life: Caravans v0.8.0 - server-side Caravan Radio Channel (101.6 MHz),
-- Radio Caravan Dispatch (hail/route nearest convoy), Roadside Supply Drops,
-- and Regional Town Market & Road Intel.

pcall(function() require "radio/ISDynamicRadio" end)
require "ALifeCaravans/00_ALC_Core"
require "ALifeCaravans/01_ALC_Lines"
require "ALifeCaravans/05_ALC_Trade"
require "ALifeCaravans/07_ALC_Market"
require "ALifeCaravans/09_ALC_Radio"
require "ALifeCaravans/ALC_Ledger"
require "ALifeCaravans/ALC_Economy"

local A = ALifeCaravans
local RS = {
    channel = nil,
    registered = false,
}
A.RadioServer = RS

local function P() return ProjectALife end

function RS.store()
    local root = A.Ledger.open()
    root.radioLog = type(root.radioLog) == "table" and root.radioLog or {}
    root.dispatches = type(root.dispatches) == "table" and root.dispatches or {}
    root.dropCooldowns = type(root.dropCooldowns) == "table" and root.dropCooldowns or {}
    root.dropReceipts = type(root.dropReceipts) == "table" and root.dropReceipts or {}
    root.radioSeq = tonumber(root.radioSeq) or 0
    return root
end

function RS.nextId(prefix)
    local root = RS.store()
    root.radioSeq = (tonumber(root.radioSeq) or 0) + 1
    A.Ledger.touch()
    return tostring(prefix or "alc_r") .. ":" .. tostring(root.radioSeq)
end

function RS.loadChannel(scriptManager)
    if not A.authority() or not A.settings.enabled then return false end
    if scriptManager == nil and type(getZomboidRadio) == "function" then
        local ok, zr = pcall(getZomboidRadio)
        if ok and zr ~= nil and type(zr.getScriptManager) == "function" then
            local ok2, sm = pcall(zr.getScriptManager, zr)
            if ok2 then scriptManager = sm end
        end
    end
    if scriptManager == nil then return false end
    local freq = A.Radio.frequency()
    local uuid = A.Radio.CHANNEL_UUID
    local ch = nil
    pcall(function()
        ch = scriptManager:getRadioChannel(uuid)
        if ch == nil and DynamicRadioChannel ~= nil and type(DynamicRadioChannel.new) == "function" then
            local cat = (type(ChannelCategory) == "table" or type(ChannelCategory) == "userdata") and ChannelCategory.Amateur or nil
            local candidate = DynamicRadioChannel.new(A.Radio.CHANNEL_NAME, freq, cat, uuid)
            scriptManager:AddChannel(candidate, false)
            ch = scriptManager:getRadioChannel(uuid) or candidate
        end
    end)
    if ch ~= nil then
        RS.channel = ch
        if type(DynamicRadio) == "table" and type(DynamicRadio.cache) == "table" then
            DynamicRadio.cache[uuid] = ch
        end
        return true
    end
    return false
end

function RS.air(speaker, text, meta)
    if not A.authority() or type(text) ~= "string" or text == "" then return nil end
    meta = type(meta) == "table" and meta or {}
    if RS.channel == nil then RS.loadChannel(nil) end
    local freq = A.Radio.frequency()
    local prefix = (type(speaker) == "string" and speaker ~= "") and ("[" .. speaker .. "] ") or ""
    local fullText = prefix .. text
    local color = meta.color or { 0.92, 0.84, 0.56 }

    pcall(function()
        if RS.channel ~= nil and RadioBroadCast ~= nil and RadioLine ~= nil then
            local bc = RadioBroadCast.new("alc-net-" .. tostring(A.now()), -1, -1)
            bc:AddRadioLine(RadioLine.new(fullText, color[1], color[2], color[3]))
            RS.channel:setAiringBroadcast(bc)
        end
        local knox = P() and (P().KnoxRadio or P().KnoxCountyRadio)
        if knox and knox.channel and knox.channel ~= RS.channel and knox.channel:getAiringBroadcast() == nil
                and RadioBroadCast ~= nil and RadioLine ~= nil then
            local bc2 = RadioBroadCast.new("alc-knox-" .. tostring(A.now()), -1, -1)
            bc2:AddRadioLine(RadioLine.new(fullText, color[1], color[2], color[3]))
            knox.channel:setAiringBroadcast(bc2)
        end
    end)

    local root = RS.store()
    local day, hour = 1, 12
    if A.Director and type(A.Director.clock) == "function" then day, hour = A.Director.clock() end
    local entry = {
        id = RS.nextId("air"),
        freq = freq,
        speaker = tostring(speaker or "Caravan Net"),
        text = text,
        x = meta.x and math.floor(tonumber(meta.x)) or nil,
        y = meta.y and math.floor(tonumber(meta.y)) or nil,
        town = meta.town,
        kind = meta.kind or "chatter",
        day = day,
        hour = math.floor(tonumber(hour) or 12),
        atMs = A.now(),
    }
    root.radioLog[#root.radioLog + 1] = entry
    while #root.radioLog > 40 do table.remove(root.radioLog, 1) end
    A.metrics.radio = A.metrics.radio + 1
    A.Ledger.touch()
    if A.Director then A.Director.publishDirty = true end
    return entry
end

function RS.marketSummaryList()
    local out = {}
    local G = A.Director and A.Director.graph() or nil
    if G == nil or type(G.nodes) ~= "table" then return out end
    local townIds = {}
    for id, node in pairs(G.nodes) do
        if node.kind == nil or node.kind == "town" then townIds[#townIds + 1] = id end
    end
    table.sort(townIds)
    for _, id in ipairs(townIds) do
        local node = G.nodes[id]
        local m = A.Economy and A.Economy.marketFor(G, id) or nil
        if m ~= nil and node ~= nil then
            out[#out + 1] = {
                townId = tostring(id),
                townName = m.townName,
                x = math.floor(tonumber(node.x) or 0),
                y = math.floor(tonumber(node.y) or 0),
                shortage = m.shortage,
                surplus = m.surplus,
            }
        end
    end
    return out
end

function RS.activeDispatches()
    local root = RS.store()
    local out = {}
    for _, d in pairs(root.dispatches) do
        if d.state == "ready" then out[#out + 1] = d end
    end
    table.sort(out, function(a, b) return tostring(a.id) < tostring(b.id) end)
    return out
end

function RS.recentBroadcasts()
    local root = RS.store()
    local out = {}
    for i = #root.radioLog, 1, -1 do
        out[#out + 1] = root.radioLog[i]
    end
    return out
end

function RS.hailNearestCaravan(player)
    if not A.authority() or player == nil or not A.settings.radioDispatchEnabled then return false, "disabled" end
    local okRadio, whyRadio = A.Radio.canUseRadio(player)
    if not okRadio then
        if A.Interact then A.Interact.reply(player, "serviceNotice", { key = "err_" .. tostring(whyRadio) }) end
        return false, whyRadio
    end
    local px, py = A.xyz(player)
    if px == nil then return false, "no_pos" end
    local G = A.Director and A.Director.graph() or nil
    local best, bestD = nil, math.huge
    for _, c in ipairs(A.Ledger.list()) do
        if not c.hostile and c.state ~= "defeated" and tonumber(c.x) and tonumber(c.y) then
            local d = A.dist(px, py, c.x, c.y)
            local effD = (c.state == "rendered" and d <= 220) and (d - 1000) or d
            if effD < bestD then best, bestD = c, effD end
        end
    end
    local realD = best and A.dist(px, py, best.x, best.y) or math.huge
    if best == nil and A.Director and type(A.Director.found) == "function" then
        local okF, created = A.Director.found(A.now(), A.Director.playerRows())
        if okF and type(created) == "table" then
            best = created
            bestD = A.dist(px, py, best.x or px, best.y or py)
        end
    end
    if best == nil then
        if A.Interact then A.Interact.reply(player, "serviceNotice", { key = "radio_no_caravan" }) end
        return false, "no_caravan"
    end

    if best.state == "rendered" and realD <= 220 and A.Director and type(A.Director.halt) == "function" then
        A.Director.halt(best, A.settings.haltSeconds or 180, "hail")
        A.metrics.halts = A.metrics.halts + 1
    elseif best.state == "offline" and G ~= nil then
        -- Nudge offline caravan closer along its route toward the player
        best.t = math.min(0.95, (tonumber(best.t) or 0) + 0.35)
        local pt = A.Director.offlinePosition(G, best)
        if pt then best.x, best.y = pt.x, pt.y end
    end

    local cx, cy = math.floor(best.x or px), math.floor(best.y or py)
    local vars = A.Director and A.Director.vars(best) or {
        name = tostring(best.callsign or best.name or "Convoy"),
        faction = tostring(best.factionName or best.name or "Traders"),
        town = tostring(best.destName or "?"),
        dest = tostring(best.destName or "?"),
    }
    vars.x, vars.y = tostring(cx), tostring(cy)
    local text = A.Lines.ui("radio_hail_reply", "{name} ({faction}) at ({x},{y}) bound for {dest} — holding frequency 101.6 MHz.", vars)
    local entry = RS.air(best.callsign or best.name, text, { x = cx, y = cy, town = vars.town, kind = "hail" })
    A.metrics.radioDispatches = A.metrics.radioDispatches + 1
    if A.Director then A.Director.publish(true) end
    if A.Interact then
        A.Interact.reply(player, "radioEvent", { kind = "hailed", entry = entry, caravanId = best.id, x = cx, y = cy, callsign = best.callsign or best.name })
    end
    return true, best
end

function RS.requestSupplyDrop(player, pkgId)
    if not A.authority() or player == nil or not A.settings.radioDispatchEnabled then return false, "disabled" end
    local okRadio, whyRadio = A.Radio.canUseRadio(player)
    if not okRadio then
        if A.Interact then A.Interact.reply(player, "serviceNotice", { key = "err_" .. tostring(whyRadio) }) end
        return false, whyRadio
    end
    local pkg = A.Radio.packageById(pkgId)
    if pkg == nil then return false, "bad_package" end
    local root = RS.store()
    local key = A.playerKey(player)
    local now = A.now()
    local cdUntil = tonumber(root.dropCooldowns[key]) or 0
    if now < cdUntil then
        local mins = math.max(1, math.ceil((cdUntil - now) / 60000))
        if A.Interact then A.Interact.reply(player, "serviceNotice", { key = "err_drop_cooldown", vars = { mins = mins } }) end
        return false, "cooldown"
    end
    local okPay, whyPay = A.Radio.spendPlayerCredit(player, pkg.cost)
    if not okPay then
        if A.Interact then A.Interact.reply(player, "serviceNotice", { key = "err_drop_credit", vars = { cost = pkg.cost } }) end
        return false, whyPay
    end
    local px, py = A.xyz(player)
    px, py = math.floor(tonumber(px) or 10630), math.floor(tonumber(py) or 9780)
    local dx, dy = px + 24, py + 12
    if A.Roads and type(A.Roads.scene) == "function" and type(A.Roads.snapRoad) == "function" then
        local roadPt = A.Roads.snapRoad(A.Roads.scene(player), px + 26, py + 10, 32)
        if roadPt and tonumber(roadPt.x) and tonumber(roadPt.y) then
            dx, dy = math.floor(roadPt.x), math.floor(roadPt.y)
        end
    end
    local callsign = "Supply-" .. tostring((root.radioSeq or 0) + 1)
    local drop = {
        id = RS.nextId("drop"),
        pkgId = pkg.id,
        callsign = callsign,
        owner = key,
        x = dx,
        y = dy,
        state = "ready",
        items = A.copy(pkg.items),
        atMs = now,
    }
    root.dispatches[drop.id] = drop
    root.dropCooldowns[key] = now + (tonumber(A.settings.supplyDropCooldownMinutes) or 10) * 60000
    local text = A.Lines.ui("radio_drop_sent", "{callsign} positioned supply crate at ({x},{y}). Approach within 25 tiles to claim.", {
        callsign = callsign, x = dx, y = dy
    })
    local entry = RS.air(callsign, text, { x = dx, y = dy, kind = "drop" })
    A.metrics.supplyDrops = A.metrics.supplyDrops + 1
    A.Ledger.touch()
    if A.Director then A.Director.publish(true) end
    if A.Interact then
        A.Interact.reply(player, "radioEvent", { kind = "drop_ready", drop = drop, entry = entry })
    end
    return true, drop
end

function RS.claimSupplyDrop(player, dropId)
    if not A.authority() or player == nil then return false, "no_authority" end
    local root = RS.store()
    local drop = root.dispatches[tostring(dropId or "")]
    if drop == nil or drop.state ~= "ready" then
        if A.Interact then A.Interact.reply(player, "serviceNotice", { key = "err_drop_closed" }) end
        return false, "closed"
    end
    local px, py = A.xyz(player)
    if px == nil or A.dist(px, py, drop.x, drop.y) > 25 then
        if A.Interact then A.Interact.reply(player, "serviceNotice", { key = "err_drop_far", vars = { x = drop.x, y = drop.y } }) end
        return false, "too_far"
    end
    if root.dropReceipts[drop.id] ~= nil then return false, "already_claimed" end
    drop.state = "claimed"
    drop.claimedMs = A.now()
    root.dropReceipts[drop.id] = { owner = A.playerKey(player), atMs = drop.claimedMs }
    local takeRows = {}
    for _, spec in ipairs(drop.items or {}) do
        takeRows[#takeRows + 1] = { item = spec[1] or spec.item, count = spec[2] or spec.count or 1 }
    end
    A.Trade.exchange(player, { giveRows = {}, takeRows = takeRows })
    A.metrics.supplyClaimed = A.metrics.supplyClaimed + 1
    A.Ledger.touch()
    if A.Director then A.Director.publish(true) end
    if A.Interact then
        A.Interact.reply(player, "radioEvent", { kind = "drop_claimed", callsign = drop.callsign, id = drop.id })
    end
    return true, takeRows
end

function RS.requestMarketIntel(player)
    if not A.authority() or player == nil or not A.settings.radioDispatchEnabled then return false, "disabled" end
    local okRadio, whyRadio = A.Radio.canUseRadio(player)
    if not okRadio then
        if A.Interact then A.Interact.reply(player, "serviceNotice", { key = "err_" .. tostring(whyRadio) }) end
        return false, whyRadio
    end
    local markets = RS.marketSummaryList()
    local parts = {}
    for i = 1, math.min(4, #markets) do
        local m = markets[i]
        if m.shortage then
            local catName = A.Lines.ui("cat_" .. tostring(m.shortage), tostring(m.shortage))
            parts[#parts + 1] = tostring(m.townName) .. " -> " .. tostring(catName) .. " (+35%)"
        end
    end
    local summary = #parts > 0 and table.concat(parts, "; ") or "Balanced supply across towns"
    local text = A.Lines.ui("radio_market_bulletin", "Trade Net Market Bulletin: {summary}. Active convoys: {count}.", {
        summary = summary, count = tostring(A.Ledger.count())
    })
    local firstM = markets[1]
    local entry = RS.air("Trade-HQ", text, { x = firstM and firstM.x, y = firstM and firstM.y, town = firstM and firstM.townName, kind = "intel" })
    A.metrics.marketIntel = A.metrics.marketIntel + 1
    if A.Director then A.Director.publish(true) end
    if A.Interact then
        A.Interact.reply(player, "radioEvent", { kind = "market_intel", entry = entry, markets = markets })
    end
    return true, markets
end

if not RS.registered and type(Events) == "table" then
    RS.registered = true
    if Events.OnLoadRadioScripts ~= nil and type(Events.OnLoadRadioScripts.Add) == "function" then
        Events.OnLoadRadioScripts.Add(function(sm) pcall(RS.loadChannel, sm) end)
    end
    if Events.OnGameStart ~= nil and type(Events.OnGameStart.Add) == "function" then
        Events.OnGameStart.Add(function() pcall(RS.loadChannel, nil) end)
    end
end

return RS
