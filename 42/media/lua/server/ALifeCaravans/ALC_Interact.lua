-- A-Life: Caravans - interactions (server / single player). Players flag a
-- caravan down (menu, horn, headlight flashes), talk to the driver, barter,
-- hitch a ride, ask it to wait, offer an escort, threaten it, pay a raider's
-- toll. Reactions follow A-Life's stance of the crew toward the player
-- (friendly / neutral / careful / hostile), the caravan's class (traders fold
-- or flee, soldiers and raiders fight) and the player's favor with the faction.
-- Trades are server-authoritative: the server quotes and reserves, the client
-- moves the items in its own inventory exactly once per transaction id, the
-- server commits on the acknowledgement or rolls the reservation back.

require "ALifeCaravans/00_ALC_Core"
require "ALifeCaravans/01_ALC_Lines"
require "ALifeCaravans/04_ALC_Convoy"
require "ALifeCaravans/05_ALC_Trade"
require "ALifeCaravans/ALC_Ledger"
require "ALifeCaravans/ALC_Spawn"
require "ALifeCaravans/ALC_Director"

local A = ALifeCaravans
local I = { reach = 18, tollPrice = 60, installed = false, reservationMs = 20000, txSerial = 0 }
A.Interact = I
local T = A.Trade

-- NEW INTERACTIONS: Join caravan, request distress help, recruit NPC, inspect cargo
I.newCommands = {
    "join_caravan",      -- player asks to travel with caravan to destination
    "leave_caravan",     -- player leaves a caravan they joined
    "distress_help",     -- player responds to distress call
    "recruit_npc",       -- player tries to recruit an NPC from caravan
    "inspect_cargo",     -- player inspects physical cargo in trunks
    "form_caravan",      -- player forms their own caravan with recruited NPCs
    "caravan_status",    -- get detailed status of a caravan
    "give_supplies",     -- player gives supplies to struggling caravan
}

local function P() return ProjectALife end

function I.leaderActor(caravan)
    local registry = P() and P().ActorRegistry
    local uid = caravan.actorUids and caravan.actorUids[1] or nil
    if registry == nil or uid == nil then return nil end
    local ok, actor = pcall(registry.read, uid)
    if ok then return actor end
    return nil
end

-- A-Life's stance of the crew toward the player, with the caravan's truce,
-- anger and the player's favor on top.
function I.stanceFor(caravan, player)
    local key = A.playerKey(player)
    local truce = caravan.truce and caravan.truce[key]
    if truce ~= nil and A.now() < truce then return "neutral" end
    if caravan.angry and caravan.angry[key] then return "hostile" end
    local relations = P() and P().Relations
    local actor = I.leaderActor(caravan)
    local stance
    if relations ~= nil and actor ~= nil and type(relations.playerStance) == "function" then
        local ok, value = pcall(relations.playerStance, actor, player)
        if ok and type(value) == "string" then stance = value end
    end
    if stance == nil then stance = caravan.hostile and "hostile" or "neutral" end
    local favor = A.Ledger.favor(key, caravan.factionId)
    if stance == "careful" and favor >= 3 then stance = "neutral" end
    if stance == "neutral" and favor >= 6 then stance = "friendly" end
    return stance
end

function I.fights(caravan)
    return caravan.class == "military" or caravan.class == "police" or caravan.class == "raider"
end

function I.caravanOf(args)
    if type(args) ~= "table" then return nil end
    local id = tonumber(args.vehicleId)
    if id == nil then return nil end
    return A.Ledger.byVehicle(id), id
end

function I.within(player, caravan)
    local px, py = A.xyz(player)
    if px == nil or caravan.x == nil then return false end
    if A.dist(px, py, caravan.x, caravan.y) <= I.reach then return true end
    -- a rider is always "with" the caravan
    for _, id in ipairs(caravan.vehicleIds or {}) do
        local car = getVehicleById(id)
        local cx, cy = A.xyz(car)
        if cx ~= nil and A.dist(px, py, cx, cy) <= I.reach then return true end
    end
    return false
end

function I.say(caravan, situation, player, vars, cooldownMs)
    local shell, uid = A.Director.driverShell(caravan)
    if shell == nil then return false end
    return A.Lines.say(shell, situation, { uid = uid, vars = vars, cooldownMs = cooldownMs or 1500 })
end

function I.reply(player, command, args)
    if A.side() == "server" then
        pcall(sendServerCommand, player, A.MODULE, command, args)
    elseif A.Client ~= nil and type(A.Client.receive) == "function" then
        pcall(A.Client.receive, A.MODULE, command, args)
    end
end

function I.vars(caravan, player)
    local vars = A.Director.vars(caravan)
    vars.price = tostring(I.tollPrice)
    return vars
end

function I.makeAngry(caravan, player)
    caravan.angry = caravan.angry or {}
    local key = A.playerKey(player)
    caravan.angry[key] = true
    caravan.escort = nil
    A.Ledger.addFavor(key, caravan.factionId, -3)
    local reputation = P() and P().Reputation
    if reputation ~= nil and type(reputation.onPlayerProvoked) == "function" then
        pcall(reputation.onPlayerProvoked, player, caravan.factionId)
    end
end

function I.fight(caravan, player, situation)
    local px, py = A.xyz(player)
    caravan.state = "fighting"
    caravan.fightingAtMs = A.now()
    A.Director.resume(caravan)
    I.say(caravan, situation or "attacked", player, I.vars(caravan, player))
    A.Spawn.dismount(caravan, px and { x = px, y = py } or nil)
    A.metrics.fights = A.metrics.fights + 1
    A.Director.publishDirty = true
end

function I.flee(caravan, player, situation)
    caravan.speedKmh = math.min(70, (tonumber(caravan.speedKmh) or A.settings.cruiseKmh) + 15)
    A.Director.resume(caravan)
    I.say(caravan, situation or "flee", player, I.vars(caravan, player))
    A.metrics.flights = A.metrics.flights + 1
    local Tun = P() and P().DrivingTuning
    for _, id in ipairs(caravan.vehicleIds or {}) do
        local owner, s = A.Spawn.sessionOf(id)
        if s ~= nil and Tun ~= nil and type(Tun.apply) == "function" then
            local values = Tun.copy(s.tuning)
            values.speedKmh = caravan.speedKmh
            pcall(Tun.apply, s, values)
            if owner ~= nil and owner.tunings then owner.tunings[id] = values end
        end
    end
    A.Director.publishDirty = true
end

-- A crew member was attacked by a player (A-Life reputation hook).
function I.onAttacked(player, actorOrFaction)
    local uid = type(actorOrFaction) == "table" and actorOrFaction.uid or nil
    if uid == nil then return end
    local caravan = A.Ledger.byActor(uid)
    if caravan == nil or caravan.state ~= "rendered" then return end
    local now = A.now()
    if now < (caravan.attackedAtMs or 0) + 20000 then return end
    caravan.attackedAtMs = now
    I.makeAngry(caravan, player)
    if I.fights(caravan) then I.fight(caravan, player, "attacked") else I.flee(caravan, player, "flee") end
end

function I.install()
    if I.installed then return end
    I.installed = true
    local reputation = P() and P().Reputation
    if reputation ~= nil then
        for _, name in ipairs({ "onPlayerDamagedActor", "onPlayerKilledActor" }) do
            A.wrap(reputation, name, function(original)
                return function(player, actorOrFaction, ...)
                    pcall(I.onAttacked, player, actorOrFaction)
                    return original(player, actorOrFaction, ...)
                end
            end, "Reputation." .. name)
        end
    end
end

function I.hail(caravan, player, viaHorn)
    local vars = I.vars(caravan, player)
    A.metrics.hails = A.metrics.hails + 1
    if caravan.state ~= "rendered" then return end
    if caravan.halted then I.say(caravan, "hail_busy", player, vars) return end
    local stance = I.stanceFor(caravan, player)
    if stance == "hostile" then
        if caravan.kind == "raid" then
            A.Director.halt(caravan, A.settings.haltSeconds, "toll")
            caravan.toll = caravan.toll or {}
            caravan.toll[A.playerKey(player)] = A.now() + 120000
            I.say(caravan, "toll_ask", player, vars)
            A.metrics.tolls = A.metrics.tolls + 1
        else
            I.say(caravan, "hail_hostile", player, vars)
        end
        return
    end
    if stance == "careful" and A.rand(100) < 50 then I.say(caravan, "hail_refuse", player, vars) return end
    A.Director.halt(caravan, A.settings.haltSeconds, viaHorn and "horn" or "hail")
    I.say(caravan, "hail_ok", player, vars)
end

-- Stock rows with the prices this player pays (and what the caravan pays).
function I.stockView(caravan, player)
    local key = A.playerKey(player)
    local favor = A.Ledger.favor(key, caravan.factionId)
    local rows = {}
    for index, row in ipairs(caravan.stock or {}) do
        if row.count > 0 then
            rows[#rows + 1] = { index = index, item = row.item, name = row.name, count = row.count, price = T.sellPrice(row, caravan.kind, favor) }
        end
    end
    return { vehicleId = nil, rows = rows, kind = caravan.kind, favor = favor, buyRate = T.rateFor(caravan.kind).buy, currency = T.currency,
        leader = caravan.leaderName, callsign = caravan.callsign }
end

function I.canTrade(caravan, player)
    if not A.settings.tradeEnabled then return false, "trade_none" end
    if caravan.state ~= "rendered" or not caravan.halted then return false, "trade_none" end
    local stance = I.stanceFor(caravan, player)
    if stance == "hostile" then return false, "trade_refuse" end
    if caravan.kind == "raid" and stance ~= "neutral" then return false, "trade_refuse" end
    return true
end

-- A deal: validate against the live stock, reserve it, let the client move the items.
function I.deal(caravan, player, vehicleId, args)
    local ok, why = I.canTrade(caravan, player)
    if not ok then I.say(caravan, why, player, I.vars(caravan, player)) I.reply(player, "dealRefused", { vehicleId = vehicleId, reason = why }) return end
    local key = A.playerKey(player)
    local favor = A.Ledger.favor(key, caravan.factionId)
    local quote = T.quote(caravan.stock or {}, caravan.kind, favor, args.take, args.give)
    if not quote.ok then
        I.say(caravan, quote.reason == "short" and "trade_broke" or "trade_none", player, I.vars(caravan, player))
        I.reply(player, "dealRefused", { vehicleId = vehicleId, reason = quote.reason })
        return
    end
    caravan.pending = caravan.pending or {}
    for id, entry in pairs(caravan.pending) do
        if A.now() > entry.expiresMs then caravan.pending[id] = nil end
    end
    -- one open reservation per player; the stock counts already reserved stay out of reach
    for id, entry in pairs(caravan.pending) do
        if entry.playerKey == key then caravan.pending[id] = nil end
    end
    for _, row in ipairs(quote.takeRows) do
        local reserved = 0
        for _, entry in pairs(caravan.pending) do
            for _, other in ipairs(entry.quote.takeRows) do
                if other.index == row.index then reserved = reserved + other.count end
            end
        end
        local stockRow = caravan.stock[row.index]
        if stockRow == nil or stockRow.count - reserved < row.count then
            I.reply(player, "dealRefused", { vehicleId = vehicleId, reason = "out_of_stock" })
            return
        end
    end
    I.txSerial = I.txSerial + 1
    local txId = tostring(caravan.id) .. ":" .. tostring(I.txSerial) .. ":" .. tostring(A.now())
    caravan.pending[txId] = { quote = quote, playerKey = key, expiresMs = A.now() + I.reservationMs }
    I.reply(player, "dealOk", { vehicleId = vehicleId, txId = txId, take = quote.takeRows, give = quote.giveRows, currency = T.currency,
        cost = quote.cost, credit = quote.credit })
end

function I.dealDone(caravan, player, vehicleId, args)
    local txId = tostring(args.txId or "")
    local entry = caravan.pending and caravan.pending[txId] or nil
    if entry == nil then return end
    caravan.pending[txId] = nil
    if entry.playerKey ~= A.playerKey(player) then return end
    if args.ok ~= true then
        I.say(caravan, "trade_broke", player, I.vars(caravan, player))
        return
    end
    T.commit(caravan.stock, entry.quote)
    A.metrics.trades = A.metrics.trades + 1
    if #entry.quote.giveRows > 0 and entry.quote.giveRows[1].type ~= T.currency then A.metrics.barters = A.metrics.barters + 1 end
    if entry.quote.cost >= 20 or entry.quote.credit >= 20 then A.Ledger.addFavor(entry.playerKey, caravan.factionId, 1) end
    local vars = I.vars(caravan, player)
    vars.item = entry.quote.takeRows[1] and entry.quote.takeRows[1].name or (entry.quote.giveRows[1] and entry.quote.giveRows[1].name) or "goods"
    I.say(caravan, "trade_done", player, vars)
    I.reply(player, "stock", I.stockView(caravan, player))
    A.Ledger.touch()
end

function I.escortReward(caravan, players)
    local escort = caravan.escort
    if escort == nil then return end
    caravan.escort = nil
    local row
    for _, candidate in ipairs(players or {}) do if candidate.key == escort.playerKey then row = candidate end end
    A.Ledger.addFavor(escort.playerKey, caravan.factionId, 3)
    A.metrics.escorts = A.metrics.escorts + 1
    if row == nil then return end
    local reward = { item = T.currency, name = "cash", count = 80 + A.rand(81) }
    for _, stockRow in ipairs(caravan.stock or {}) do
        if stockRow.value >= 40 and stockRow.count > 0 and A.rand(2) == 0 then
            reward = { item = stockRow.item, name = stockRow.name, count = 1 }
            stockRow.count = stockRow.count - 1
            break
        end
    end
    I.say(caravan, "escort_done", row.player, I.vars(caravan, row.player))
    I.reply(row.player, "gift", { vehicleId = caravan.vehicleIds and caravan.vehicleIds[1], item = reward.item, name = reward.name, count = reward.count, reason = "escort" })
    A.log(caravan.id, "escort by", escort.playerKey, "paid:", reward.count, reward.item)
end

function I.command(player, command, args)
    if player == nil or type(command) ~= "string" then return end
    if command == "stateRequest" then A.Director.sendState(player) return end
    local caravan, vehicleId = I.caravanOf(args)
    if caravan == nil then return end
    if command == "arrived" or command == "stuck" then A.Director.onConvoyReport(player, command, args) return end
    if not I.within(player, caravan) then return end
    local vars = I.vars(caravan, player)
    local key = A.playerKey(player)
    if command == "hail" then
        I.hail(caravan, player, args.horn == true)
    elseif command == "news" then
        if caravan.state ~= "rendered" then return end
        local stance = I.stanceFor(caravan, player)
        if stance == "hostile" then I.say(caravan, "hail_hostile", player, vars) return end
        I.say(caravan, A.rand(2) == 0 and "news_dest" or "news", player, vars)
    elseif command == "trade" then
        local ok, why = I.canTrade(caravan, player)
        if not ok then I.say(caravan, why, player, vars) return end
        if #(caravan.stock or {}) == 0 then I.say(caravan, "trade_sold", player, vars) return end
        I.say(caravan, "trade_open", player, vars)
        local view = I.stockView(caravan, player)
        view.vehicleId = vehicleId
        I.reply(player, "stock", view)
    elseif command == "deal" then
        I.deal(caravan, player, vehicleId, args)
    elseif command == "dealDone" then
        I.dealDone(caravan, player, vehicleId, args)
    elseif command == "ride" then
        if caravan.state ~= "rendered" or not caravan.halted then return end
        local stance = I.stanceFor(caravan, player)
        if not A.settings.allowRiders or stance == "hostile" or stance == "careful" or caravan.kind == "raid" then
            I.say(caravan, "ride_refuse", player, vars)
            return
        end
        caravan.riders = true
        A.Spawn.setRiders(caravan, true)
        I.reply(player, "riders", { vehicleId = vehicleId, enabled = true })
        I.say(caravan, "ride_ok", player, vars)
        A.metrics.rides = A.metrics.rides + 1
        A.Director.publishDirty = true
    elseif command == "wait" then
        if not caravan.halted then return end
        caravan.waits = (caravan.waits or 0) + 1
        if caravan.waits > 2 then I.say(caravan, "wait_no", player, vars) return end
        A.Director.halt(caravan, A.settings.haltSeconds, "wait")
        I.say(caravan, "wait_ok", player, vars)
    elseif command == "farewell" then
        if not caravan.halted then return end
        A.Director.resume(caravan)
        I.say(caravan, "farewell", player, vars)
    elseif command == "escort" then
        if caravan.state ~= "rendered" or not A.settings.escortContracts then return end
        if caravan.escort ~= nil then I.say(caravan, "escort_busy", player, vars) return end
        local stance = I.stanceFor(caravan, player)
        if stance == "hostile" or stance == "careful" or caravan.kind == "raid" then I.say(caravan, "escort_refuse", player, vars) return end
        caravan.escort = { playerKey = key, sinceMs = A.now(), lastSeenMs = A.now(), dest = caravan.destName }
        I.say(caravan, "escort_ok", player, vars)
        if caravan.halted then A.Director.resume(caravan) end
        A.Director.publishDirty = true
    elseif command == "threaten" then
        if caravan.state ~= "rendered" then return end
        I.makeAngry(caravan, player)
        if I.fights(caravan) then
            I.fight(caravan, player, caravan.kind == "raid" and "threat_laugh" or "threat_fight")
        else
            local gift = nil
            for index, row in ipairs(caravan.stock or {}) do
                if row.count > 0 then gift = { index = index, row = row } break end
            end
            I.say(caravan, "threat_fold", player, vars)
            if gift ~= nil then
                gift.row.count = gift.row.count - 1
                I.reply(player, "gift", { vehicleId = vehicleId, item = gift.row.item, name = gift.row.name, count = 1, reason = "threat" })
            end
            I.flee(caravan, player, nil)
        end
    elseif command == "toll" then
        local due = caravan.toll and caravan.toll[key]
        if due == nil or A.now() > due then return end
        I.txSerial = I.txSerial + 1
        local txId = "toll:" .. tostring(caravan.id) .. ":" .. tostring(I.txSerial)
        caravan.pending = caravan.pending or {}
        caravan.pending[txId] = { quote = { takeRows = {}, giveRows = { { type = T.currency, name = "cash", count = I.tollPrice, price = 1 } }, cost = 0, credit = I.tollPrice },
            playerKey = key, expiresMs = A.now() + I.reservationMs, toll = true }
        I.reply(player, "dealOk", { vehicleId = vehicleId, txId = txId, take = {}, give = { { type = T.currency, name = "cash", count = I.tollPrice, price = 1 } },
            currency = T.currency, cost = 0, credit = I.tollPrice, toll = true })
    elseif command == "tollDone" then
        local txId = tostring(args.txId or "")
        local entry = caravan.pending and caravan.pending[txId] or nil
        if entry == nil or not entry.toll or entry.playerKey ~= key then return end
        caravan.pending[txId] = nil
        caravan.toll = caravan.toll or {}
        caravan.toll[key] = nil
        if args.ok == true then
            caravan.truce = caravan.truce or {}
            caravan.truce[key] = A.now() + 1800000
            local talk = P() and P().Talk
            local registry = P() and P().ActorRegistry
            if talk ~= nil and registry ~= nil and type(talk.tolerate) == "function" then
                for _, uid in ipairs(caravan.actorUids or {}) do
                    local ok, actor = pcall(registry.read, uid)
                    if ok and actor ~= nil then pcall(talk.tolerate, actor, key, A.now() + 1800000) end
                end
            end
            I.say(caravan, "toll_paid", player, vars)
            A.Director.resume(caravan)
        else
            I.say(caravan, "toll_broke", player, vars)
        end

    -- NEW INTERACTIONS
    elseif command == "join_caravan" then
        if not A.settings.allowRiders or caravan.state ~= "rendered" or not caravan.halted then return end
        local stance = I.stanceFor(caravan, player)
        if stance == "hostile" or stance == "careful" or caravan.kind == "raid" then
            I.say(caravan, "ride_refuse", player, vars)
            return
        end
        -- Add player as rider
        caravan.riders = true
        caravan.playerRiders = caravan.playerRiders or {}
        caravan.playerRiders[key] = { sinceMs = A.now(), dest = caravan.destName }
        A.Spawn.setRiders(caravan, true)
        I.reply(player, "joinCaravanOk", { vehicleId = vehicleId, dest = caravan.destName, caravanId = caravan.id })
        I.say(caravan, "ride_ok", player, vars)
        A.metrics.rides = A.metrics.rides + 1
        A.Director.publishDirty = true
    elseif command == "leave_caravan" then
        if not caravan.playerRiders or not caravan.playerRiders[key] then return end
        caravan.playerRiders[key] = nil
        -- Check if any player riders remain
        local anyLeft = false
        for _ in pairs(caravan.playerRiders or {}) do anyLeft = true break end
        if not anyLeft then
            caravan.riders = false
            A.Spawn.setRiders(caravan, false)
        end
        I.reply(player, "leaveCaravanOk", { vehicleId = vehicleId })
        I.say(caravan, "farewell", player, vars)
        A.Director.publishDirty = true
    elseif command == "distress_help" then
        if not caravan.distress then return end
        -- Player responded to distress call
        caravan.distress.helpers = caravan.distress.helpers or {}
        caravan.distress.helpers[key] = A.now()
        A.Ledger.addFavor(key, caravan.factionId, 5) -- Big reputation boost
        I.say(caravan, "distress_help", player, vars)
        I.reply(player, "distressHelpOk", { vehicleId = vehicleId, caravanId = caravan.id })
        A.log(caravan.id, "player", key, "responded to distress call")
    elseif command == "recruit_npc" then
        if not A.settings.playerCanFormCaravan or caravan.state ~= "rendered" or not caravan.halted then return end
        local stance = I.stanceFor(caravan, player)
        if stance ~= "friendly" and stance ~= "neutral" then
            I.say(caravan, "recruit_refuse", player, vars)
            return
        end
        if #(caravan.actorUids or {}) <= 2 then
            I.say(caravan, "recruit_refuse", player, vars) -- Can't spare anyone
            return
        end
        -- Recruit the last NPC (not the leader)
        local recruitUid = caravan.actorUids[#caravan.actorUids]
        table.remove(caravan.actorUids)
        -- Give the NPC to player's faction
        local registry = P() and P().ActorRegistry
        if registry then
            pcall(function()
                local ok, actor = pcall(registry.read, recruitUid)
                if ok and actor then
                    pcall(registry.updateTransient, recruitUid, actor.revision, function(record)
                        record.memory.playerRecruit = { playerKey = key, sinceMs = A.now() }
                    end)
                end
            end)
        end
        I.say(caravan, "recruit_ok", player, vars)
        I.reply(player, "recruitOk", { vehicleId = vehicleId, uid = recruitUid })
        A.metrics.playerCaravans = A.metrics.playerCaravans + 1
        A.log(caravan.id, "NPC", recruitUid, "recruited by", key)
        D.publishDirty = true
    elseif command == "inspect_cargo" then
        if not A.settings.caravanCargo or caravan.state ~= "rendered" then return end
        if not caravan.halted and I.stanceFor(caravan, player) ~= "friendly" then
            I.say(caravan, "inspect_refuse", player, vars)
            return
        end
        -- Show physical cargo in trunks
        local cargo = {}
        for _, id in ipairs(caravan.vehicleIds or {}) do
            local car = getVehicleById(id)
            if car then
                local trunk = car:getPartById("TruckBed") or car:getPartById("Trunk")
                if trunk then
                    local container = trunk:getContainer()
                    if container then
                        for i = 0, container:getItems():size() - 1 do
                            local item = container:getItems():get(i)
                            cargo[#cargo + 1] = { name = item:getDisplayName(), type = item:getFullType() }
                        end
                    end
                end
            end
        end
        I.reply(player, "cargoView", { vehicleId = vehicleId, cargo = cargo, caravanId = caravan.id })
        I.say(caravan, "inspect_ok", player, vars)
    elseif command == "form_caravan" then
        if not A.settings.playerCanFormCaravan then return end
        -- Player wants to form their own caravan with recruited NPCs
        local recruits = {}
        local registry = P() and P().ActorRegistry
        if registry then
            for _, uid in ipairs(caravan.actorUids or {}) do
                local ok, actor = pcall(registry.read, uid)
                if ok and actor and actor.memory and actor.memory.playerRecruit and actor.memory.playerRecruit.playerKey == key then
                    recruits[#recruits + 1] = uid
                end
            end
        end
        if #recruits < 2 then
            I.say(caravan, "form_refuse_not_enough", player, vars)
            return
        end
        -- Create player caravan (simplified - just mark the NPCs)
        for _, uid in ipairs(recruits) do
            pcall(function()
                local ok, actor = pcall(registry.read, uid)
                if ok and actor then
                    pcall(registry.updateTransient, uid, actor.revision, function(record)
                        record.memory.playerCaravanLeader = key
                        record.memory.playerCaravanSince = A.now()
                    end)
                end
            end)
        end
        I.say(caravan, "form_ok", player, vars)
        I.reply(player, "formCaravanOk", { vehicleId = vehicleId, recruits = recruits, count = #recruits })
        A.metrics.playerCaravans = A.metrics.playerCaravans + 1
        A.log("PLAYER CARAVAN formed by", key, "with", #recruits, "NPCs")
    elseif command == "caravan_status" then
        local status = {
            caravanId = caravan.id,
            name = caravan.name,
            callsign = caravan.callsign,
            kind = caravan.kind,
            faction = caravan.factionName,
            leader = caravan.leaderName,
            dest = caravan.destName,
            speed = caravan.speedKmh,
            crew = #(caravan.actorUids or {}),
            vehicles = #(caravan.vehicleIds or {}),
            trip = caravan.trip or 0,
            state = caravan.state,
            stance = I.stanceFor(caravan, player),
            favor = A.Ledger.favor(key, caravan.factionId),
            stockCount = #(caravan.stock or {}),
            hasEvent = caravan.eventType ~= nil,
            eventType = caravan.eventType,
            distress = caravan.distress ~= nil,
            halted = caravan.halted == true,
        }
        I.reply(player, "caravanStatus", status)
    elseif command == "give_supplies" then
        if caravan.state ~= "rendered" or not caravan.halted then return end
        local stance = I.stanceFor(caravan, player)
        if stance == "hostile" then return end
        -- Player gives items from their inventory
        local give = args.give or {}
        if #give == 0 then return end
        local quote = T.quote(caravan.stock or {}, caravan.kind, A.Ledger.favor(key, caravan.factionId), {}, give)
        if not quote.ok then return end
        -- Add to caravan stock
        for _, row in ipairs(quote.giveRows) do
            if row.type ~= T.currency then
                local found = false
                for _, stockRow in ipairs(caravan.stock) do
                    if stockRow.item == row.type then
                        stockRow.count = stockRow.count + row.count
                        found = true
                        break
                    end
                end
                if not found and #caravan.stock < T.maxStock then
                    caravan.stock[#caravan.stock + 1] = { item = row.type, name = T.name(row.type), value = T.valueOf(row.type), count = row.count }
                end
            end
        end
        A.Ledger.addFavor(key, caravan.factionId, 2)
        I.say(caravan, "give_supplies", player, vars)
        I.reply(player, "stock", I.stockView(caravan, player))
        A.log(caravan.id, "received supplies from", key)
        D.publishDirty = true
    end
end

-- The horn (or headlight flashes) of a player's car hails the nearest caravan.
function I.onHorn(character, vehicle, pressed)
    if not pressed or not A.settings.hornHails or not A.authority() then return end
    if character == nil or type(instanceof) ~= "function" or not instanceof(character, "IsoPlayer") then return end
    local now = A.now()
    I.hornAt = I.hornAt or {}
    local key = A.playerKey(character)
    if now < (I.hornAt[key] or 0) then return end
    I.hornAt[key] = now + 4000
    local px, py = A.xyz(character)
    if px == nil then return end
    local best, bestD = nil, 30
    for _, caravan in ipairs(A.Ledger.list()) do
        if caravan.state == "rendered" and caravan.x ~= nil then
            local d = A.dist(px, py, caravan.x, caravan.y)
            if d < bestD then best, bestD = caravan, d end
        end
    end
    if best == nil then return end
    I.hail(best, character, true)
end

return I
