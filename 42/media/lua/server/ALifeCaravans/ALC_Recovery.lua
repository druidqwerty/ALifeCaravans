-- Rebind saved caravans by persistent vehicle ModData, never by recycled getId().
-- Oracle: A-Life DrivingCrewHome scans IsoCell.getVehicles():iterator() on reload.
require "ALifeCaravans/ALC_Ledger"
local A = ALifeCaravans
local R = { nextAtMs = 0, graceMs = 30000 }
A.Recovery = R

local function loadedAt(cell, caravan)
    if caravan.x == nil or caravan.y == nil then return false end
    local ok, square = pcall(cell.getGridSquare, cell, math.floor(caravan.x), math.floor(caravan.y), 0)
    return ok and square ~= nil
end

local function crewFor(caravan, saved, cars)
    local p, seen, ids = ProjectALife, {}, {}
    local function add(uid)
        if type(uid) == "string" and not seen[uid] then seen[uid] = true ids[#ids + 1] = uid end
    end
    for _, uid in ipairs(saved.actorUids or {}) do add(uid) end
    local owner = p and (A.side() == "server" and p.DrivingDemoServer or p.DrivingDemoClient)
    for _, row in ipairs(cars) do
        local binding = owner and owner.bindings and owner.bindings[row.id]
        for _, spec in ipairs(binding and binding.crew or {}) do add(spec.uid) end
    end
    caravan.actorUids = ids
    local live, found = {}, {}
    for _, row in ipairs(cars) do
        local x, y = A.xyz(row.car)
        for _, member in ipairs(A.Spawn.survivors(caravan, x, y, 60)) do
            if not found[member.uid] then found[member.uid] = true live[#live + 1] = member.uid end
        end
    end
    return live
end

function R.tick(now)
    if not A.authority() then return end
    local pending = A.Ledger.reloadPending
    if A.isEmpty(pending) or now < R.nextAtMs then return end
    local cell = type(getCell) == "function" and getCell()
    if cell == nil or type(cell.getVehicles) ~= "function" then return false end
    R.nextAtMs = now + 1000
    local byTag = {}
    local cars = cell:getVehicles()
    local iterator = cars and cars:iterator()
    while iterator and iterator:hasNext() do
        local car = iterator:next()
        local tag, index = A.vehicleTag(car)
        if tag and pending[tag] then
            byTag[tag] = byTag[tag] or {}
            byTag[tag][#byTag[tag] + 1] = { car = car, id = car:getId(), index = tonumber(index) or 1 }
        end
    end
    for id, saved in pairs(pending) do
        local caravan = A.Ledger.get(id)
        if caravan == nil then pending[id] = nil
        else
            if not saved.prepared then
                -- Do not send old IDs to teardown or steering while chunks/actors restore.
                caravan.state, caravan.vehicleIds = "recovering", {}
                caravan.requestId, caravan.pendingUnit, caravan.renderUnit = nil, nil, nil
                caravan.recrew, caravan.arrivals, caravan.stuckReport = nil, 0, nil
                caravan.missingSinceMs = nil
                if caravan.sos then caravan.sos.sample = nil end
                saved.prepared = true
                A.Ledger.touch()
            end
            local matched = byTag[id] or {}
            if #matched > 0 or loadedAt(cell, caravan) then
                saved.startedMs = saved.startedMs or now
                table.sort(matched, function(a, b)
                    if a.index == b.index then return a.id < b.id end
                    return a.index < b.index
                end)
                local live = crewFor(caravan, saved, matched)
                if now - saved.startedMs >= R.graceMs then
                    caravan.vehicleIds, caravan.actorUids = {}, live
                    for _, row in ipairs(matched) do caravan.vehicleIds[#caravan.vehicleIds + 1] = row.id end
                    caravan.halted, caravan.haltUntilMs, caravan.riders, caravan.ridersAboard = nil, nil, nil, nil
                    -- Saved booleans are stale; keep actual occupants protected,
                    -- without granting ride permission to an NPC-only binding.
                    for _, row in ipairs(matched) do
                        if A.vehicleHasPlayer(row.car) then
                            caravan.ridersAboard = true
                            local owner = A.Spawn.sessionOf(row.id)
                            if owner and owner.allowRiders and owner.allowRiders[row.id] == true
                                    and owner.carModes and owner.carModes[row.id] == "mixed" then
                                caravan.riders = true
                            end
                        end
                    end
                    caravan.ambush = caravan.ambush and caravan.ambush.state == "armed" and caravan.ambush or nil
                    if #matched == 0 then
                        caravan.state, caravan.units = "offline", 0
                        caravan.nextRenderAtMs = now + 30000
                    elseif #live == 0 then
                        -- A-Life did not persist this transient crew. Preserve its parked cars;
                        -- never invent replacement NPCs or delete a player's occupied vehicle.
                        caravan.state, caravan.strandedAtMs = "stranded", now
                        caravan.recoveryReason = "no_live_crew"
                    else
                        caravan.state, caravan.renderedAtMs = "rendered", now
                        caravan.x, caravan.y = A.xyz(matched[1].car)
                        caravan.recoveryReason = nil
                    end
                    pending[id] = nil
                    if A.Director then A.Director.publishDirty = true end
                    A.Ledger.touch()
                    A.log("reload", id, caravan.state, "cars", #matched, "crew", #live)
                end
            end
        end
    end
end

return R
