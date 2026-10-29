-- A-Life: Caravans - the caravan ledger (server / single player). Persistent
-- through A-Life's own world store (Persistence.bucket) so caravans survive a
-- reload with their route, crew and cargo; falls back to global ModData.

require "ALifeCaravans/00_ALC_Core"

local A = ALifeCaravans
local Ledger = { store = nil, fallback = false }
A.Ledger = Ledger

local DEFAULTS = { schema = 1, caravans = {}, sequence = 0, nextFoundAtMs = 0 }

function Ledger.open()
    if Ledger.store ~= nil then return Ledger.store end
    local persistence = ProjectALife and ProjectALife.Persistence
    if persistence ~= nil and type(persistence.bucket) == "function" then
        local ok, store = pcall(persistence.bucket, "alc_caravans", A.copy(DEFAULTS))
        if ok and type(store) == "table" then
            store.caravans = type(store.caravans) == "table" and store.caravans or {}
            store.sequence = tonumber(store.sequence) or 0
            Ledger.store = store
            return store
        end
        A.fail("ledger bucket", store)
    end
    local store
    if type(ModData) == "table" and type(ModData.getOrCreate) == "function" then
        local ok, data = pcall(ModData.getOrCreate, "ALifeCaravans.v1")
        if ok and type(data) == "table" then store = data end
    end
    store = store or {}
    for key, value in pairs(DEFAULTS) do
        if store[key] == nil then store[key] = A.copy(value) end
    end
    Ledger.store = store
    Ledger.fallback = true
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
    store.sequence = (tonumber(store.sequence) or 0) + 1
    local id = "caravan:" .. tostring(store.sequence)
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

function Ledger.reset()
    local store = Ledger.open()
    store.caravans = {}
    store.sequence = 0
    store.nextFoundAtMs = 0
    Ledger.touch()
end

return Ledger
