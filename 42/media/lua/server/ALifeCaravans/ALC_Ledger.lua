-- A-Life: Caravans - the caravan ledger (server / single player). Persistent
-- through A-Life's own world store (Persistence.bucket) so caravans survive a
-- reload with their route, crew, stock and favor; falls back to global ModData.
-- Schema 2 (0.2.0) migrates 0.1.0 ledgers in place.

require "ALifeCaravans/00_ALC_Core"
require "ALifeCaravans/05_ALC_Trade"

local A = ALifeCaravans
local Ledger = { store = nil, fallback = false, reloadPending = {} }
A.Ledger = Ledger

local DEFAULTS = { schema = A.SCHEMA, caravans = {}, sequence = 0, nextFoundAtMs = 0, favor = {}, sosReceipts = {} }

-- 0.1.0 -> 0.2.0: offers { item, name, price, stock } become stock rows
-- { item, name, value, count }; new fields get their defaults.
function Ledger.migrate(store)
    local from = tonumber(store.schema) or 1
    if from >= A.SCHEMA then return false end
    for _, caravan in pairs(store.caravans or {}) do
        if caravan.stock == nil then
            local rows = {}
            for _, offer in ipairs(caravan.offers or {}) do
                rows[#rows + 1] = { item = offer.item, name = offer.name, value = tonumber(offer.price) or A.Trade.valueOf(offer.item),
                    count = tonumber(offer.stock) or 1 }
            end
            caravan.stock = rows
        end
        caravan.offers = nil
        caravan.trip = caravan.trip or 0
        caravan.abandoned = caravan.abandoned or {}
        caravan.units = caravan.units or 0
        caravan.truce = caravan.truce or {}
        if caravan.state == "rendering" or caravan.state == "rendered" or caravan.state == "fighting" then
            -- cars of a previous session are gone after a reload; the director re-renders
            caravan.state = "offline"
            caravan.vehicleIds, caravan.actorUids = {}, {}
        end
    end
    store.favor = store.favor or {}
    store.schema = A.SCHEMA
    A.log("ledger migrated from schema", from, "to", A.SCHEMA)
    return true
end

function Ledger.open()
    if Ledger.store ~= nil then return Ledger.store end
    local persistence = ProjectALife and ProjectALife.Persistence
    local store
    Ledger.fallback = false
    if persistence ~= nil and type(persistence.bucket) == "function" then
        local ok, bucket = pcall(persistence.bucket, "alc_caravans", A.copy(DEFAULTS))
        if ok and type(bucket) == "table" then store = bucket else A.fail("ledger bucket", bucket) end
    end
    if store == nil then
        if type(ModData) == "table" and type(ModData.getOrCreate) == "function" then
            local ok, data = pcall(ModData.getOrCreate, "ALifeCaravans.v1")
            if ok and type(data) == "table" then store = data end
        end
        store = store or {}
        Ledger.fallback = true
    end
    for key, value in pairs(DEFAULTS) do
        if store[key] == nil then store[key] = A.copy(value) end
    end
    store.caravans = type(store.caravans) == "table" and store.caravans or {}
    store.sequence = tonumber(store.sequence) or 0
    store.favor = type(store.favor) == "table" and store.favor or {}
    store.sosReceipts = type(store.sosReceipts) == "table" and store.sosReceipts or {}
    Ledger.reloadPending = {}
    for id, caravan in pairs(store.caravans) do
        local serial = tonumber(string.match(tostring(id), "^caravan:(%d+)$")) or 0
        store.sequence = math.max(store.sequence, serial)
        if type(caravan) == "table" then
            caravan.id = caravan.id or id
            if caravan.state == "rendered" or caravan.state == "rendering" or caravan.state == "fighting"
                    or caravan.state == "recovering" then
                Ledger.reloadPending[id] = { state = caravan.state, actorUids = A.copy(caravan.actorUids or {}) }
            end
        end
    end
    Ledger.store = store
    if Ledger.migrate(store) then Ledger.touch() end
    return store
end

function Ledger.touch()
    local persistence = ProjectALife and ProjectALife.Persistence
    if not Ledger.fallback and persistence ~= nil and type(persistence.touch) == "function" then
        pcall(persistence.touch)
    elseif Ledger.fallback and type(ModData) == "table" and type(ModData.transmit) == "function" then
        pcall(ModData.transmit, "ALifeCaravans.v1")
    end
end

function Ledger.create(fields)
    local store = Ledger.open()
    local id
    repeat
        store.sequence = (tonumber(store.sequence) or 0) + 1
        id = "caravan:" .. tostring(store.sequence)
    until store.caravans[id] == nil
    fields.id = id
    store.caravans[id] = fields
    Ledger.touch()
    return fields
end

function Ledger.get(id)
    return Ledger.open().caravans[id]
end

function Ledger.remove(id)
    local store = Ledger.open()
    if store.caravans[id] == nil then return false end
    store.caravans[id] = nil
    Ledger.reloadPending[id] = nil
    Ledger.touch()
    return true
end

function Ledger.count()
    local count = 0
    for _ in pairs(Ledger.open().caravans) do count = count + 1 end
    return count
end

-- Stable order (by id) so ticks are deterministic.
function Ledger.list()
    local out = {}
    for _, caravan in pairs(Ledger.open().caravans) do out[#out + 1] = caravan end
    table.sort(out, function(a, b) return tostring(a.id) < tostring(b.id) end)
    return out
end

function Ledger.byVehicle(vehicleId)
    for _, caravan in pairs(Ledger.open().caravans) do
        for _, id in ipairs(caravan.vehicleIds or {}) do
            if id == vehicleId then return caravan end
        end
    end
    return nil
end

function Ledger.byActor(uid)
    for _, caravan in pairs(Ledger.open().caravans) do
        for _, actorUid in ipairs(caravan.actorUids or {}) do
            if actorUid == uid then return caravan end
        end
    end
    return nil
end

-- Favor of a player with a faction (-10..10), earned by fair trades and escorts.
function Ledger.favor(playerKey, factionId)
    local store = Ledger.open()
    local row = store.favor[tostring(playerKey)]
    return row and tonumber(row[tostring(factionId)]) or 0
end

function Ledger.addFavor(playerKey, factionId, delta)
    local store = Ledger.open()
    local key = tostring(playerKey)
    store.favor[key] = store.favor[key] or {}
    local value = math.max(-10, math.min(10, (tonumber(store.favor[key][tostring(factionId)]) or 0) + (tonumber(delta) or 0)))
    store.favor[key][tostring(factionId)] = value
    Ledger.touch()
    return value
end

function Ledger.reset()
    local store = Ledger.open()
    Ledger.reloadPending = {}
    store.sosReceipts = {}
    store.caravans = {}
    -- Never reuse persisted vehicle tags or SOS incident IDs after a debug reset.
    store.nextFoundAtMs = 0
    store.favor = {}
    store.schema = A.SCHEMA
    Ledger.touch()
end

return Ledger
