-- Authoritative, persisted rescue escorts. No client-supplied outcome or item reward.
require "ALifeCaravans/00_ALC_Core"
require "ALifeCaravans/01_ALC_Lines"
require "ALifeCaravans/ALC_Ledger"

local A = ALifeCaravans
local S = { radius = 70, graceMs = 60000, minimumMs = 30000, reward = 3 }
A.SOS = S

function S.active(caravan)
    local incident = caravan and caravan.sos
    return incident ~= nil and (incident.state == "open" or incident.state == "cover" or incident.state == "escape")
end

function S.notice(player, key, vars)
    if player ~= nil and A.Interact ~= nil then
        A.Interact.reply(player, "sosNotice", { key = key, vars = vars or {} })
    end
end

function S.finish(caravan, success, reason, player)
    if not A.authority() or not S.active(caravan) then return false end
    local incident = caravan.sos
    if success and incident.owner == nil then return false end
    local store = A.Ledger.open()
    store.sosReceipts = store.sosReceipts or {}
    local receipt = store.sosReceipts[incident.id]
    if receipt ~= nil then
        -- A restored nonterminal snapshot must converge to its terminal receipt,
        -- not remain an active contract and never apply its reward a second time.
        incident.state, incident.reason, incident.finishedMs = receipt.state, receipt.reason, receipt.atMs
        incident.paid, incident.sample = (tonumber(receipt.reward) or 0) > 0, nil
        A.Ledger.touch()
        if A.Director then A.Director.publishDirty = true end
        return false
    end
    incident.state, incident.reason, incident.finishedMs = success and "done" or "failed", reason, A.now()
    incident.paid = success == true
    incident.sample = nil
    -- Terminal state, receipt and favor live in the same persistence bucket. Mark before reward.
    store.sosReceipts[incident.id] = { state = incident.state, playerKey = incident.owner,
        atMs = incident.finishedMs, reward = success and S.reward or 0, reason = reason }
    local count, oldestId, oldestMs = 0, nil, nil
    for id, receipt in pairs(store.sosReceipts) do
        count = count + 1
        local atMs = tonumber(receipt.atMs) or 0
        if id ~= incident.id and (oldestMs == nil or atMs < oldestMs) then oldestId, oldestMs = id, atMs end
    end
    if count > 128 and oldestId ~= nil then store.sosReceipts[oldestId] = nil end
    if success then A.Ledger.addFavor(incident.owner, caravan.factionId, S.reward) else A.Ledger.touch() end
    A.Director.publishDirty = true
    S.notice(player, success and "done" or "failed", { reward = S.reward, reasonKey = reason })
    A.log(caravan.id, "SOS", incident.id, incident.state, reason, incident.owner or "unclaimed")
    return true
end

function S.start(caravan, now)
    if caravan == nil then return false end
    local ambush = caravan.ambush
    if not A.authority() or not A.settings.enabled or not A.settings.sosContracts then return false end
    if caravan.state ~= "rendered" or caravan.hostile or caravan.kind == "raid" then return false end
    if ambush == nil or ambush.state ~= "fighting" or ambush.sosId ~= nil or S.active(caravan) then return false end
    caravan.sosSequence = (tonumber(caravan.sosSequence) or 0) + 1
    local id = tostring(caravan.id) .. ":sos:" .. tostring(caravan.sosSequence)
    caravan.sos = { id = id, state = "open", startedMs = now, deadlineMs = now + A.settings.sosTimeoutMinutes * 60000,
        distance = 0, coveredMs = 0, requiredDistance = A.settings.sosEscapeTiles }
    ambush.sosId = id
    A.Director.publishDirty = true
    A.Ledger.touch()
    A.log(caravan.id, "SOS opened", id)
    return true
end

function S.accept(caravan, player)
    if not A.authority() or not A.settings.enabled or not A.settings.sosContracts or player == nil then return false end
    if not S.active(caravan) or caravan.state ~= "rendered" or player:isDead() then return false end
    if not A.Interact.within(player, caravan) or A.Interact.stanceFor(caravan, player) == "hostile" then return false end
    local incident, key, now = caravan.sos, A.playerKey(player), A.now()
    if now >= incident.deadlineMs then S.finish(caravan, false, "timeout", player) return false end
    if incident.owner ~= nil then
        if incident.owner == key then S.status(caravan, player) else S.notice(player, "busy") end
        return incident.owner == key
    end
    incident.owner, incident.state, incident.acceptedMs, incident.lastSeenMs = key, "cover", now, now
    incident.sample = nil
    A.Ledger.touch()
    A.Director.publishDirty = true
    S.notice(player, "accepted", { distance = incident.requiredDistance })
    return true
end

function S.status(caravan, player)
    local incident = caravan.sos
    if incident == nil or player == nil then return end
    if incident.owner ~= nil and incident.owner ~= A.playerKey(player) then S.notice(player, "busy") return end
    if incident.state == "done" then S.notice(player, "done", { reward = S.reward })
    elseif incident.state == "failed" then
        S.notice(player, "failed", { reasonKey = incident.reason })
    else
        S.notice(player, incident.state == "escape" and "progress" or "cover", { distance = math.floor(incident.distance),
            target = incident.requiredDistance, seconds = math.floor(incident.coveredMs / 1000) })
    end
end

return S
