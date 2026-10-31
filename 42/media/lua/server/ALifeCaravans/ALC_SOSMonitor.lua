-- Observe physical escape, never accept distance/time/completion supplied by a client.
require "ALifeCaravans/ALC_SOS"
local A, S = ALifeCaravans, ALifeCaravans.SOS

function S.onRelease(caravan, reason)
    if not A.authority() or not S.active(caravan) then return end
    caravan.sos.sample = nil
    if reason == "far" or reason == "cars_gone" then
        caravan.sos.missingSinceMs = caravan.sos.missingSinceMs or A.now()
        A.Ledger.touch()
    else
        S.finish(caravan, false, "lost")
    end
end

local function movingCar(caravan, player)
    local px, py = A.xyz(player)
    if px == nil then return nil end
    for _, id in ipairs(caravan.vehicleIds or {}) do
        local car = getVehicleById(id)
        if car ~= nil and A.vehicleTag(car) == caravan.id then
            local x, y = A.xyz(car)
            local driver = car:getDriver()
            local fuel, engine = A.Spawn.carHealth(car)
            if x ~= nil and A.dist(px, py, x, y) <= S.radius and driver ~= nil
                and not instanceof(driver, "IsoPlayer") and engine and fuel > 0.3 then
                for _, row in ipairs(A.Spawn.survivors(caravan, x, y, 15)) do
                    if row.npc == driver then return car, x, y end
                end
            end
        end
    end
end

function S.tick(caravan, now, players)
    if not A.authority() or not S.active(caravan) then return end
    local incident, player = caravan.sos, nil
    for _, row in ipairs(players or {}) do
        if row.key == incident.owner then player = row.player break end
    end
    if not A.settings.enabled or not A.settings.sosContracts then S.finish(caravan, false, "disabled", player) return end
    if now >= incident.deadlineMs then S.finish(caravan, false, "timeout", player) return end
    if caravan.state == "stranded" or caravan.state == "fighting" then S.finish(caravan, false, "lost", player) return end
    if player ~= nil and player:isDead() then S.finish(caravan, false, "absent", player) return end
    if player ~= nil and A.Interact.stanceFor(caravan, player) == "hostile" then S.finish(caravan, false, "hostile", player) return end
    local present, car, x, y = false, nil, nil, nil
    if caravan.state == "rendered" then
        local anyCar = false
        for _, id in ipairs(caravan.vehicleIds or {}) do
            local body = getVehicleById(id)
            if body ~= nil and A.vehicleTag(body) == caravan.id then
                anyCar = true
                local px, py = A.xyz(player)
                local cx, cy = A.xyz(body)
                if px ~= nil and cx ~= nil and A.dist(px, py, cx, cy) <= S.radius then present = true end
            end
        end
        if anyCar then incident.missingSinceMs = nil end
        car, x, y = movingCar(caravan, player)
        if not anyCar then incident.missingSinceMs = incident.missingSinceMs or now end
    else
        incident.missingSinceMs = incident.missingSinceMs or now
    end
    if incident.missingSinceMs ~= nil and now - incident.missingSinceMs >= S.graceMs then
        S.finish(caravan, false, "lost", player) return
    end
    if incident.owner == nil then return end
    if present then incident.lastSeenMs = now
    elseif now - (incident.lastSeenMs or incident.acceptedMs) >= S.graceMs then
        S.finish(caravan, false, "absent", player) return
    end
    local fighting = caravan.ambush ~= nil and caravan.ambush.state == "fighting"
    local ready = present and car ~= nil and not caravan.halted and not fighting and A.isEmpty(caravan.recrew)
    if not ready then incident.sample = nil return end
    if incident.state ~= "escape" then
        incident.state = "escape"
        incident.escapeOrigin = { x = x, y = y }
        A.Director.publishDirty = true
        A.Ledger.touch()
        S.notice(player, "escape", { distance = incident.requiredDistance })
    end
    local previous = incident.sample
    incident.sample = { id = car:getId(), x = x, y = y, atMs = now }
    if previous ~= nil and previous.id == car:getId() then
        local dt, distance = now - previous.atMs, A.dist(previous.x, previous.y, x, y)
        -- Ignore stale samples, vehicle swaps and jumps faster than physically plausible driving.
        if dt > 0 and dt <= 5000 and distance >= 0.25 and distance <= (dt / 1000) * 28 + 2 then
            incident.distance = incident.distance + distance
            incident.coveredMs = incident.coveredMs + dt
            local origin = incident.escapeOrigin or { x = x, y = y }
            if incident.distance >= incident.requiredDistance and incident.coveredMs >= S.minimumMs
                and A.dist(origin.x, origin.y, x, y) >= incident.requiredDistance then
                S.finish(caravan, true, "escaped", player) return
            end
            A.Ledger.touch()
        elseif dt > 0 and dt <= 5000 and distance > (dt / 1000) * 28 + 2 then
            incident.distance, incident.coveredMs, incident.escapeOrigin = 0, 0, { x = x, y = y }
            A.Ledger.touch()
        end
    end
end

return S
