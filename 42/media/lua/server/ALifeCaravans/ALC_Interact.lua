-- A-Life: Caravans - interactions (server / single player). Players flag a
-- caravan down (menu, or the horn), talk to the driver, trade, hitch a ride,
-- ask it to wait, threaten it, pay a raider's toll. Reactions follow A-Life's
-- stance of the crew toward the player (friendly / neutral / careful / hostile)
-- and the caravan's class (traders fold or flee, soldiers and raiders fight).
-- The driver answers through A-Life's speech bubbles.

require "ALifeCaravans/00_ALC_Core"
require "ALifeCaravans/01_ALC_Lines"
require "ALifeCaravans/04_ALC_Convoy"
require "ALifeCaravans/ALC_Ledger"
require "ALifeCaravans/ALC_Spawn"
require "ALifeCaravans/ALC_Director"

local A = ALifeCaravans
local I = { reach = 18, tollPrice = 60, installed = false }
A.Interact = I

local function P() return ProjectALife end

-- Goods by caravan kind: { item, price (money), stock }. Items that do not
-- exist in this game (mods removed) are skipped.
I.goods = {
    trade = {
        { "Base.TinnedBeans", 15, 3 }, { "Base.CannedCornedBeef", 18, 2 }, { "Base.WaterBottleFull", 8, 4 },
        { "Base.Bandage", 10, 3 }, { "Base.Antibiotics", 60, 1 }, { "Base.PetrolCan", 45, 2 },
        { "Base.Bullets9mmBox", 50, 2 }, { "Base.ShotgunShellsBox", 55, 1 }, { "Base.Cigarettes", 12, 4 },
        { "Base.Axe", 70, 1 }, { "Base.Hammer", 25, 1 }, { "Base.Nails", 10, 2 }, { "Base.Rope", 20, 2 },
        { "Base.CannedTomato", 12, 2 }, { "Base.Pills", 20, 2 }, { "Base.Seeds_PotatoBag", 18, 1 },
    },
    convoy = {
        { "Base.556Box", 70, 2 }, { "Base.Bullets9mmBox", 50, 2 }, { "Base.FirstAidKit", 80, 1 },
        { "Base.Bandage", 10, 3 }, { "Base.MRE", 20, 3 }, { "Base.WaterBottleFull", 8, 2 }, { "Base.PetrolCan", 45, 1 },
    },
    patrol = {
        { "Base.Bullets9mmBox", 50, 2 }, { "Base.ShotgunShellsBox", 55, 1 }, { "Base.Bandage", 10, 2 },
        { "Base.WaterBottleFull", 8, 2 }, { "Base.Cigarettes", 12, 2 },
    },
    rescue = {
        { "Base.Bandage", 8, 4 }, { "Base.FirstAidKit", 70, 1 }, { "Base.Pills", 15, 3 }, { "Base.Antibiotics", 50, 1 },
        { "Base.WaterBottleFull", 8, 3 }, { "Base.Disinfectant", 25, 2 },
    },
    raid = {},
}
I.currency = "Base.Money"

local function itemExists(fullType)
    local ok, found = pcall(function()
        local manager = getScriptManager()
        if type(manager.getItem) == "function" then return manager:getItem(fullType) ~= nil end
        if type(manager.FindItem) == "function" then return manager:FindItem(fullType) ~= nil end
        return true
    end)
    return ok and found == true
end

local function itemName(fullType)
    local ok, name = pcall(function() return getItemNameFromFullType(fullType) end)
    if ok and type(name) == "string" and name ~= "" then return name end
    return string.gsub(fullType, "^Base%.", "")
end

function I.offersFor(caravan)
    local pool = I.goods[caravan.kind] or I.goods.trade
    local offers = {}
    local chosen, count = {}, math.min(#pool, 4 + A.rand(3))
    local guard = 0
    while #offers < count and guard < 40 do
        guard = guard + 1
        local row = pool[A.rand(#pool) + 1]
        if row ~= nil and not chosen[row[1]] then
            chosen[row[1]] = true
            if itemExists(row[1]) then
                local price = math.floor(row[2] * (0.8 + A.randFloat() * 0.6))
                offers[#offers + 1] = { item = row[1], name = itemName(row[1]), price = math.max(1, price), stock = row[3] }
            end
        end
    end
    return offers
end

function I.leaderActor(caravan)
    local registry = P() and P().ActorRegistry
    local uid = caravan.actorUids and caravan.actorUids[1] or nil
    if registry == nil or uid == nil then return nil end
    local ok, actor = pcall(registry.read, uid)
    if ok then return actor end
    return nil
end

-- A-Life's stance of the crew toward the player, with the caravan's truce on top.
function I.stanceFor(caravan, player)
    local key = A.playerKey(player)
    local truce = caravan.truce and caravan.truce[key]
    if truce ~= nil and A.now() < truce then return "neutral" end
    if caravan.angry and caravan.angry[key] then return "hostile" end
    local relations = P() and P().Relations
    local actor = I.leaderActor(caravan)
    if relations ~= nil and actor ~= nil and type(relations.playerStance) == "function" then
        local ok, stance = pcall(relations.playerStance, actor, player)
        if ok and type(stance) == "string" then return stance end
    end
    if caravan.hostile then return "hostile" end
    return "neutral"
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
    return A.dist(px, py, caravan.x, caravan.y) <= I.reach
end

function I.say(caravan, situation, player, vars, cooldownMs)
    local shell, uid = A.Director.driverShell(caravan)
    if shell == nil then return false end
    return A.Lines.say(shell, situation, { face = player, uid = uid, vars = vars, cooldownMs = cooldownMs or 1500 })
end

function I.reply(player, command, args)
    if A.side() == "server" then
        pcall(sendServerCommand, player, A.MODULE, command, args)
    elseif A.Client ~= nil and type(A.Client.receive) == "function" then
        pcall(A.Client.receive, A.MODULE, command, args)
    end
end

function I.vars(caravan, player)
    local town = nil
    local speech = P() and P().Speech
    if speech ~= nil and type(speech.nearestTown) == "function" then
        local ok, name = pcall(speech.nearestTown, caravan.x or 0, caravan.y or 0)
        if ok and type(name) == "string" and name ~= "" then town = name end
    end
    local day = A.Director.clock()
    return { dest = tostring(caravan.destName or "?"), town = tostring(town or caravan.destName or "?"),
        faction = tostring(caravan.factionName or caravan.name), day = tostring(day), price = tostring(I.tollPrice) }
end

function I.makeAngry(caravan, player)
    caravan.angry = caravan.angry or {}
    caravan.angry[A.playerKey(player)] = true
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
    -- live speed for the driving session
    local T = P() and P().DrivingTuning
    for _, id in ipairs(caravan.vehicleIds or {}) do
        local owner, s = A.Spawn.sessionOf(id)
        if s ~= nil and T ~= nil and type(T.apply) == "function" then
            local values = T.copy(s.tuning)
            values.speedKmh = caravan.speedKmh
            pcall(T.apply, s, values)
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
            -- raiders stop you to rob you
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

function I.command(player, command, args)
    if player == nil or type(command) ~= "string" then return end
    if command == "stateRequest" then A.Director.sendState(player) return end
    local caravan, vehicleId = I.caravanOf(args)
    if caravan == nil then return end
    if command == "arrived" then A.Director.onConvoyReport(player, command, args) return end
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
    elseif command == "offers" then
        if not A.settings.tradeEnabled or caravan.state ~= "rendered" or not caravan.halted then I.say(caravan, "trade_none", player, vars) return end
        local stance = I.stanceFor(caravan, player)
        if stance == "hostile" or caravan.kind == "raid" or caravan.offers == nil or #caravan.offers == 0 then
            I.say(caravan, "trade_none", player, vars)
            return
        end
        local list = {}
        for index, offer in ipairs(caravan.offers) do
            if offer.stock > 0 then list[#list + 1] = { index = index, item = offer.item, name = offer.name, price = offer.price, stock = offer.stock } end
        end
        if #list == 0 then I.say(caravan, "trade_sold", player, vars) return end
        I.say(caravan, "trade_open", player, vars)
        I.reply(player, "offers", { vehicleId = vehicleId, currency = I.currency, offers = list })
    elseif command == "buy" then
        local offer = caravan.offers and caravan.offers[tonumber(args.index) or 0] or nil
        if not A.settings.tradeEnabled or offer == nil or offer.stock <= 0 or not caravan.halted or I.stanceFor(caravan, player) == "hostile" then
            I.say(caravan, "trade_none", player, vars)
            return
        end
        I.reply(player, "tradeOk", { vehicleId = vehicleId, index = args.index, item = offer.item, name = offer.name,
            price = offer.price, currency = I.currency })
    elseif command == "tradeDone" then
        local offer = caravan.offers and caravan.offers[tonumber(args.index) or 0] or nil
        if args.ok == true and offer ~= nil then
            offer.stock = math.max(0, offer.stock - 1)
            A.metrics.trades = A.metrics.trades + 1
            vars.item = offer.name
            I.say(caravan, "trade_done", player, vars)
            A.Ledger.touch()
        else
            I.say(caravan, "trade_broke", player, vars)
        end
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
    elseif command == "threaten" then
        if caravan.state ~= "rendered" then return end
        I.makeAngry(caravan, player)
        if I.fights(caravan) then
            I.fight(caravan, player, caravan.kind == "raid" and "threat_laugh" or "threat_fight")
        else
            local gift = nil
            for index, offer in ipairs(caravan.offers or {}) do
                if offer.stock > 0 then gift = { index = index, offer = offer } break end
            end
            I.say(caravan, "threat_fold", player, vars)
            if gift ~= nil then
                gift.offer.stock = gift.offer.stock - 1
                I.reply(player, "tradeOk", { vehicleId = vehicleId, index = gift.index, item = gift.offer.item,
                    name = gift.offer.name, price = 0, currency = I.currency })
            end
            I.flee(caravan, player, nil)
        end
    elseif command == "toll" then
        local due = caravan.toll and caravan.toll[key]
        if due == nil or A.now() > due then return end
        I.reply(player, "tradeOk", { vehicleId = vehicleId, index = -1, item = nil, name = "toll", price = I.tollPrice, currency = I.currency, toll = true })
    elseif command == "tollDone" then
        local due = caravan.toll and caravan.toll[key]
        if due == nil then return end
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
    end
end

-- The horn of a player's car hails the nearest caravan ahead.
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
