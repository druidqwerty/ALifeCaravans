-- Pure-Lua vehicle physics adapters for verified A-Life: Caravans sessions.
-- No Java bridge or ZombieBuddy dependency is required:
--   * SP local simulation uses BaseVehicle:authorizationChanged(npc / nil);
--   * SP save/reload wake uses checkSurroundingChunks() + setPhysicsActive();
--   * Parked wheel brakes are cleared once at the start of a verified drive
--     through a zero-power regulator step in BaseVehicle:updatePhysics(), plus
--     resetting premature boardPrepared flags while the driver is still outside.
require "ALifeCaravans/00_ALC_Core"
local A = ALifeCaravans
local F = { spVehicles = {}, spLeases = {} }
A.Physics = F

function F.ridersAllowed(v)
    local r = ProjectALife and ProjectALife.DrivingRiders
    return r and type(r.allowed) == "function" and r.allowed(v:getId()) == true or false
end

function F.playersAllowed(v)
    if not A.vehicleHasPlayer(v) then return true end
    if not F.ridersAllowed(v) or instanceof(v:getDriver(), "IsoPlayer") then return false end
    for seat = 0, v:getMaxPassengers() - 1 do
        local body = v:getCharacter(seat)
        if body and instanceof(body, "IsoPlayer") and (seat == 0 or body:getVehicle() ~= v) then return false end
    end
    return true
end

function F.wakeSP(v, npc, driving, s)
    local asleep = type(v.isPhysicsActive) == "function" and v:isPhysicsActive() == false
    local speed = type(v.getCurrentSpeedKmHour) == "function" and math.abs(v:getCurrentSpeedKmHour()) or 0
    if not driving or v:getDriver() ~= npc or npc:getVehicle() ~= v
            or not v:isEngineRunning() or (not asleep and speed > 0.5) then return false end
    local vx, vy = A.xyz(v)
    local now = A.now()
    local movedChunk = s and vx ~= nil and s.alcWokeSP and (s.alcChunkX == nil or A.dist(vx, vy, s.alcChunkX, s.alcChunkY) >= 5.5)
    local stalledDrive = s and s.alcWokeSP and (s.driveAcceleration or 0) > 1.0 and speed < 0.25 and now >= (s.alcWakeRetryAt or 0)
    if s and s.alcWokeSP and not asleep and not movedChunk and not stalledDrive then return true end
    if (asleep or stalledDrive) and s and s.alcWokeSP then
        if now < (s.alcWakeRetryAt or 0) then return false end
        s.alcWakeRetryAt = now + 1500
    end
    if type(v.checkSurroundingChunks) == "function" then v:checkSurroundingChunks() end
    if s and vx ~= nil then s.alcChunkX, s.alcChunkY = vx, vy end
    if not s or not s.alcWokeSP or asleep or stalledDrive then
        if type(v.setPhysicsActive) == "function" then
            if type(v.isPhysicsActive) == "function" and v:isPhysicsActive() then v:setPhysicsActive(false) end
            v:setPhysicsActive(true)
        end
    end
    local active = type(v.isPhysicsActive) ~= "function" or v:isPhysicsActive() == true
    if s then s.alcWokeSP = active or nil end
    return active
end

function F.acquireSP(v, npc, caravanId, uid, generation, ridersAllowed, driving, s)
    if isClient() or isServer() or not v or not npc or npc:isDead() then return false end
    if (type(v.getController) == "function" and v:getController() == nil)
            or (type(v.getSquare) == "function" and v:getSquare() == nil) then return false end
    local vData, nData = v:getModData(), npc:getModData()
    if not caravanId or not vData or vData[A.MODDATA_ID] ~= caravanId
            or not uid or not nData or nData.ProjectALifeUID ~= uid
            or type(nData.ProjectALifeGeneration) ~= "number" or nData.ProjectALifeGeneration ~= generation
            or (A.vehicleHasPlayer(v) and not ridersAllowed)
            or (v:getDriver() ~= nil and v:getDriver() ~= npc)
            or (npc:getVehicle() ~= nil and npc:getVehicle() ~= v)
            or (type(v.getVehicleTowedBy) == "function" and v:getVehicleTowedBy() ~= nil)
            or (type(v.getVehicleTowing) == "function" and v:getVehicleTowing() ~= nil) then return false end
    if v:isLocalPhysicSim() then
        F.wakeSP(v, npc, driving, s)
        return true
    end
    local nx, ny, nz = A.xyz(npc)
    local vx, vy, vz = A.xyz(v)
    if v:getNetPlayerId() ~= -1 or math.abs(v:getCurrentSpeedKmHour()) > 0.5
            or not nx or not vx or math.abs((nz or 0) - (vz or 0)) > 0.5
            or A.dist(nx, ny, vx, vy) > 40 or type(v.authorizationChanged) ~= "function" then return false end
    local assignedId = type(npc.getOnlineID) == "function" and npc:getOnlineID() or -1
    v:authorizationChanged(npc)
    if not v:isLocalPhysicSim() then return false end
    F.spLeases[v] = { assignedId = assignedId }
    F.wakeSP(v, npc, driving, s)
    return true
end

function F.isSeatedInVehicle(body, v)
    if not body then return false, nil, nil end
    local car, seat = nil, nil
    pcall(function()
        if type(body.getVehicle) == "function" then car = body:getVehicle() end
        if car ~= nil and type(car.getSeat) == "function" then seat = car:getSeat(body) end
    end)
    if car ~= nil then return true, car, seat end
    if v ~= nil then
        local foundSeat = nil
        pcall(function()
            local seats = type(v.getMaxPassengers) == "function" and v:getMaxPassengers() or 0
            for s = 0, math.max(0, seats - 1) do
                if type(v.getCharacter) == "function" and v:getCharacter(s) == body then
                    foundSeat = s
                    break
                end
            end
        end)
        if foundSeat ~= nil then return true, v, foundSeat end
    end
    return false, nil, nil
end

function F.syncBodyCrashGuard(body, v, active)
    if not body or instanceof(body, "IsoPlayer") or type(body.setGodMod) ~= "function" then return end
    local noBodyDamage = type(body.getBodyDamage) ~= "function" or body:getBodyDamage() == nil
    if not noBodyDamage then return end
    local inCar, car, seat = F.isSeatedInVehicle(body, v)
    local dead = false
    pcall(function() dead = type(body.isDead) == "function" and body:isDead() == true end)
    if inCar and dead then
        -- Java's setGodMod(true, true) is a no-op when isDead() is true, whereas
        -- setInvulnerable(true) calls setGodModCheat(true) unconditionally, and
        -- BaseVehicle.damagePlayers does not check isDead(). Eject dead bodiless
        -- occupants immediately (and fallback to setInvulnerable if still seated).
        pcall(function()
            if car ~= nil and type(car.exitRSync) == "function" and type(body.getVehicle) == "function" and body:getVehicle() == car then
                car:exitRSync(body)
            end
            if car ~= nil and type(car.clearPassenger) == "function" then
                if seat ~= nil and seat >= 0 and (type(car.getCharacter) ~= "function" or car:getCharacter(seat) == body) then
                    car:clearPassenger(seat)
                elseif type(car.getMaxPassengers) == "function" and type(car.getCharacter) == "function" then
                    for s = 0, math.max(0, car:getMaxPassengers() - 1) do
                        if car:getCharacter(s) == body then car:clearPassenger(s) end
                    end
                end
            end
            if type(body.setVehicle) == "function" and type(body.getVehicle) == "function" and body:getVehicle() ~= nil then
                body:setVehicle(nil)
            end
        end)
        inCar = F.isSeatedInVehicle(body, v)
    end
    -- As long as a bodiless NPC is physically seated in any vehicle, keep crash guard ON
    -- even if a caller requested active=false (e.g. DrivingEntry.clear called from inside
    -- DrivingEntry.seated, or F.releaseSP while crew is still aboard).
    local guard = inCar
    if guard and not dead then
        pcall(function()
            if type(body.isKnockedDown) == "function" and body:isKnockedDown() == true and type(body.setKnockedDown) == "function" then
                body:setKnockedDown(false)
            end
        end)
    end
    if guard or active == false or dead then
        local already = false
        pcall(function()
            already = type(body.isGodMod) == "function" and body:isGodMod() == guard
        end)
        if not already then
            pcall(body.setGodMod, body, guard, true)
            if type(body.setInvulnerable) == "function" then
                pcall(body.setInvulnerable, body, guard)
            end
        end
    end
end

function F.syncVehicleOccupants(v, active)
    if not v or isClient() then return end
    pcall(function()
        local seats = type(v.getMaxPassengers) == "function" and v:getMaxPassengers() or 0
        for seat = 0, math.max(0, seats - 1) do
            local body = v:getCharacter(seat)
            if body ~= nil then F.syncBodyCrashGuard(body, v, active) end
        end
    end)
end

function F.syncCrashGuard(v, members, active)
    if not v or isClient() then return end
    for _, member in ipairs(members or {}) do
        local body = member and member.npc
        if body ~= nil then
            local keep = active ~= false and member.boarded ~= false
            F.syncBodyCrashGuard(body, v, keep)
        end
    end
    F.syncVehicleOccupants(v, active)
end

function F.releaseSP(v)
    if not v or isServer() or isClient() then return false end
    local s = F.spVehicles[v]
    if s and ProjectALife and ProjectALife.DrivingDemo and type(ProjectALife.DrivingDemo.members) == "function" then
        F.syncCrashGuard(v, ProjectALife.DrivingDemo.members(s), false)
    end
    F.spVehicles[v] = nil
    local lease = F.spLeases[v]
    F.spLeases[v] = nil
    if not lease then return false end
    if not instanceof(v:getDriver(), "IsoPlayer") and v:isLocalPhysicSim()
            and v:getNetPlayerId() == lease.assignedId and type(v.authorizationChanged) == "function" then
        local ok, err = pcall(v.authorizationChanged, v, nil)
        if not ok then A.log("SP vehicle lease release failed:", tostring(err)) end
    end
    return true
end

function F.ensureSP(s, entry)
    if isServer() or isClient() or not s or not entry or s.alcSPError then return false end
    local v, npc = s.vehicle, s.npc
    if not v or not npc or not A.Convoy or A.Convoy.known[v:getId()] ~= entry
            or A.Convoy.sessionFor(v:getId()) ~= s then return false end
    local function refuse()
        F.syncVehicleOccupants(v, true)
        F.releaseSP(v)
        return false
    end
    if npc:isDead() or instanceof(npc, "IsoPlayer") or not F.playersAllowed(v)
            or v:getModData()[A.MODDATA_ID] ~= entry.caravanId then return refuse() end
    local p = ProjectALife
    if not p or not p.DrivingDemo or type(p.DrivingDemo.members) ~= "function" then return refuse() end
    local members, seenSeats, seenBodies = p.DrivingDemo.members(s), {}, {}
    local allBoarded = true
    if #members == 0 then return refuse() end
    for _, member in ipairs(members) do
        local body, seat = member.npc, member.seat or 0
        if not body or body:isDead() or instanceof(body, "IsoPlayer") or not member.uid
                or member.generation == nil or seenSeats[seat] or seenBodies[body]
                or seat < 0 or seat >= v:getMaxPassengers() or not v:isSeatInstalled(seat) then return refuse() end
        local data, occupied, other = body:getModData(), v:getCharacter(seat), body:getVehicle()
        if not data or data.ProjectALifeUID ~= member.uid or data.ProjectALifeGeneration ~= member.generation
                or occupied and occupied ~= body or other and (other ~= v or occupied ~= body)
                or member.boarded and (other ~= v or occupied ~= body) then return refuse() end
        if member.boarded ~= true or other ~= v or occupied ~= body then allBoarded = false end
        seenSeats[seat], seenBodies[body] = true, true
    end
    if not seenBodies[npc] or not seenSeats[0] then return refuse() end
    for seat = 0, v:getMaxPassengers() - 1 do
        local body = v:getCharacter(seat)
        if body and not seenBodies[body] and not (seat > 0 and instanceof(body, "IsoPlayer") and F.ridersAllowed(v)) then return refuse() end
    end
    local driving = allBoarded and s.phase == "driving" and s.entryComplete == true and not entry.halted
        and not s.braking and not s.exitAt and not s.exitRequested and not s.detaching
    if not driving then s.alcWokeSP = nil end
    -- Keep crash guard active whenever bodiless NPCs remain seated in the car
    -- (including while braking, halted, boarding, or slowing down to dismount)
    -- so wall impacts never trigger BaseVehicle.crash BodyDamage NPE.
    F.syncCrashGuard(v, members, true)
    local ok, result = pcall(F.acquireSP, v, npc, entry.caravanId, s.uid, s.generation, F.ridersAllowed(v), driving, s)
    if not ok then
        if not s.alcSPError then A.log("SP vehicle adapter failed:", tostring(result)) end
        s.alcSPError = true
        return refuse()
    end
    if result == true then F.spVehicles[v] = s return true end
    return refuse()
end

function F.sweepSP()
    if isServer() or isClient() then return end
    local release = {}
    for v, s in pairs(F.spVehicles) do
        if not A.Convoy or not A.Convoy.known[v:getId()] or A.Convoy.sessionFor(v:getId()) ~= s
                or not F.playersAllowed(v) then release[#release + 1] = v end
    end
    for _, v in ipairs(release) do F.releaseSP(v) end
end

function F.releaseBrake(v, ridersAllowed)
    if not v or isServer() or not v:isLocalPhysicSim() then return false, "not_local" end
    if isClient() then
        local player = getSpecificPlayer(0)
        if not player or v:getNetPlayerId() ~= player:getOnlineID() then return false, "not_owner" end
    end
    if not v:isEngineRunning() then return false, "engine_off" end
    if math.abs(v:getCurrentSpeedKmHour()) > 1.8 then return false, "moving" end
    local driver = v:getDriver()
    if not driver or instanceof(driver, "IsoPlayer") or driver:isDead() or driver:getVehicle() ~= v then return false, "driver" end
    local data = driver:getModData()
    if not data or data.ProjectALifeUID == nil then return false, "driver_identity" end
    if A.vehicleHasPlayer(v) and not ridersAllowed then return false, "player_aboard" end
    if (type(v.getController) == "function" and v:getController() == nil)
            or type(v.updatePhysics) ~= "function" then return false, "physics" end
    local needUnseat = type(driver.getMoodles) == "function" and driver:getMoodles() == nil
    if needUnseat and (type(v.clearPassenger) ~= "function" or type(v.enterRSync) ~= "function") then
        return false, "physics"
    end
    local originalBrake = v:getBrakingForce()
    local reg = type(v.isRegulator) == "function" and v:isRegulator() or false
    local regSpeed = type(v.getRegulatorSpeed) == "function" and v:getRegulatorSpeed() or 0
    local hasFeature = type(v.setEngineFeature) == "function" and type(v.getEngineQuality) == "function"
        and type(v.getEngineLoudness) == "function" and type(v.getEnginePower) == "function"
    local quality, loudness, power
    if hasFeature then quality, loudness, power = v:getEngineQuality(), v:getEngineLoudness(), v:getEnginePower() end
    local rpm = type(v.getEngineSpeed) == "function" and v:getEngineSpeed() or nil
    local stoplights = type(v.getStoplightsOn) == "function" and v:getStoplightsOn() or nil
    local sc = type(UIManager) == "table" and type(UIManager.getSpeedControls) == "function" and UIManager.getSpeedControls() or nil
    local gameSpeed = sc and type(sc.getCurrentGameSpeed) == "function" and sc:getCurrentGameSpeed() or nil
    local unseated = false
    local ok, err = pcall(function()
        if needUnseat then
            v:clearPassenger(0)
            unseated = true
        end
        v:setBrakingForce(0)
        if type(v.setBraking) == "function" then v:setBraking(false) end
        if stoplights ~= nil and not isClient() and type(v.setStoplightsOn) == "function" then v:setStoplightsOn(false) end
        if type(v.isBackSignalEmitting) == "function" and v:isBackSignalEmitting()
                and type(v.onBackMoveSignalStop) == "function" then v:onBackMoveSignalStop() end
        if hasFeature then v:setEngineFeature(quality, loudness, 0) end
        if type(v.setRegulator) == "function" then v:setRegulator(true) end
        if type(v.setRegulatorSpeed) == "function" then v:setRegulatorSpeed(math.abs(v:getCurrentSpeedKmHour()) + 5) end
        v:updatePhysics()
    end)
    if unseated and v:getDriver() ~= driver then
        pcall(v.enterRSync, v, 0, driver, v)
        if type(v.setCharacterPosition) == "function" then pcall(v.setCharacterPosition, v, driver, 0, "inside") end
    end
    if type(v.setRegulatorSpeed) == "function" then pcall(v.setRegulatorSpeed, v, regSpeed) end
    if type(v.setRegulator) == "function" then pcall(v.setRegulator, v, reg) end
    if hasFeature then pcall(v.setEngineFeature, v, quality, loudness, power) end
    if rpm ~= nil and type(v.setEngineSpeed) == "function" then pcall(v.setEngineSpeed, v, rpm) end
    if stoplights ~= nil and not isClient() and type(v.setStoplightsOn) == "function" then pcall(v.setStoplightsOn, v, stoplights) end
    if sc and gameSpeed and gameSpeed > 1 and type(sc.SetCurrentGameSpeed) == "function" then
        pcall(sc.SetCurrentGameSpeed, sc, gameSpeed)
    end
    pcall(v.setBrakingForce, v, originalBrake)
    if not ok then error(err) end
    return true
end

function F.parkBrake(v, ridersAllowed)
    if not v or isServer() or not v:isLocalPhysicSim() then return false end
    if A.vehicleHasPlayer(v) and not ridersAllowed then return false end
    if (type(v.getController) == "function" and v:getController() == nil)
            or type(v.updatePhysics) ~= "function" then return false end
    local driver = v:getDriver()
    if driver ~= nil and instanceof(driver, "IsoPlayer") then return false end
    local needUnseat = driver ~= nil and type(driver.getMoodles) == "function" and driver:getMoodles() == nil
    if needUnseat and (type(v.clearPassenger) ~= "function" or type(v.enterRSync) ~= "function") then return false end
    local reg = type(v.isRegulator) == "function" and v:isRegulator() or false
    local regSpeed = type(v.getRegulatorSpeed) == "function" and v:getRegulatorSpeed() or 0
    local rpm = type(v.getEngineSpeed) == "function" and v:getEngineSpeed() or nil
    local unseated = false
    pcall(function()
        if needUnseat then
            v:clearPassenger(0)
            unseated = true
        end
        if type(v.setRegulator) == "function" then v:setRegulator(false) end
        if type(v.setRegulatorSpeed) == "function" then v:setRegulatorSpeed(0) end
        v:updatePhysics()
    end)
    if unseated and driver ~= nil and v:getDriver() ~= driver then
        pcall(v.enterRSync, v, 0, driver, v)
        if type(v.setCharacterPosition) == "function" then pcall(v.setCharacterPosition, v, driver, 0, "inside") end
    end
    if type(v.setRegulatorSpeed) == "function" then pcall(v.setRegulatorSpeed, v, regSpeed) end
    if type(v.setRegulator) == "function" then pcall(v.setRegulator, v, reg) end
    if rpm ~= nil and type(v.setEngineSpeed) == "function" then pcall(v.setEngineSpeed, v, rpm) end
    return true
end

function F.prepare(s, entry)
    if not s or not entry or isServer() then return false end
    if not isClient() then F.ensureSP(s, entry) end
    if s.phase == "approach" and s.boardPrepared and not s.boarded and not s.releaseAt
            and s.vehicle and s.vehicle:getDriver() == nil then
        s.boardPrepared = nil
    end
    local v, npc = s.vehicle, s.npc
    if s.phase ~= "driving" or entry.halted then
        if s.alcBrakeReleased and v then pcall(F.parkBrake, v, F.ridersAllowed(v)) end
        s.alcBrakeReleased, s.alcBrakeError, s.alcBrakeWhy, s.alcBrakeStallAt = nil, nil, nil, nil
        return false
    end
    if v and not entry.halted and not s.braking and not s.exitAt and not s.exitRequested and not s.detaching then
        if type(v.isPhysicsActive) == "function" and v:isPhysicsActive() == false then
            local now = A.now()
            s.alcPhysicsWaiting = true
            s.lastProgressAt = now
            if type(s.navigation) == "table" then
                s.navigation.driveProgress, s.navigation.retryProgress = nil, nil
                s.navigation.blockedSince, s.navigation.progressMark = nil, nil
            end
        else
            s.alcPhysicsWaiting = nil
        end
        if s.alcBrakeReleased and not s.alcBrakeError and not s.obstacleSince and not s.terrainWaiting and not s.alcPhysicsWaiting then
            local speed = type(v.getCurrentSpeedKmHour) == "function" and math.abs(v:getCurrentSpeedKmHour()) or 0
            if (s.driveAcceleration or 0) > 1.0 and speed < 0.3 then
                local now = A.now()
                s.alcBrakeStallAt = s.alcBrakeStallAt or now
                local retryWait = (s.alcBrakeRetries or 0) < 3 and 750 or 1500
                if now - s.alcBrakeStallAt >= retryWait then
                    s.alcBrakeRetries = (s.alcBrakeRetries or 0) + 1
                    s.alcBrakeReleased = nil
                    s.alcBrakeStallAt = now
                    if type(v.checkSurroundingChunks) == "function" then pcall(v.checkSurroundingChunks, v) end
                    if not isClient() and type(v.setPhysicsActive) == "function" then pcall(v.setPhysicsActive, v, true) end
                end
            else
                s.alcBrakeStallAt = nil
            end
        end
    end
    if s.alcBrakeReleased or s.alcBrakeError or entry.halted or s.braking or s.exitAt or s.exitRequested
            or s.detaching or not s.entryComplete then return false end
    if not v or not npc or not A.Convoy or A.Convoy.known[v:getId()] ~= entry then return false end
    if A.Convoy.sessionFor(v:getId()) ~= s then return false end
    if not v:isLocalPhysicSim() then return false end
    if isClient() then
        local player = getSpecificPlayer(0)
        if not player or v:getNetPlayerId() ~= player:getOnlineID() then return false end
    end
    if math.abs(v:getCurrentSpeedKmHour()) > 1.8 or not v:isEngineRunning()
            or v:getDriver() ~= npc or npc:getVehicle() ~= v or npc:isDead()
            or instanceof(npc, "IsoPlayer") or not F.playersAllowed(v) then return false end
    local members = ProjectALife.DrivingDemo.members(s)
    if #members == 0 then return false end
    for _, member in ipairs(members) do
        local body = member.npc
        if not body or not member.boarded or body:isDead() or body:getVehicle() ~= v
                or v:getCharacter(member.seat or 0) ~= body then return false end
        local data = body:getModData()
        if not data or data.ProjectALifeUID ~= member.uid
                or data.ProjectALifeGeneration ~= member.generation then return false end
    end
    local ok, result, why = pcall(F.releaseBrake, v, F.ridersAllowed(v))
    if not ok then
        if not s.alcBrakeError then A.log("parked brake release failed:", tostring(result)) end
        s.alcBrakeError = true
        return false
    end
    if result ~= true then
        if s.alcBrakeWhy ~= why then
            s.alcBrakeWhy = why
            A.debug("car", v:getId(), "parked brake release waiting:", tostring(why))
        end
        return false  -- transient guard decline; retry next tick
    end
    s.alcBrakeWhy = nil
    s.alcBrakeReleased = true
    A.debug("car", v:getId(), "parked brake released for NPC drive")
    return true
end

F.nextCellGuardAt = 0

function F.installCompatHooks()
    if F.compatHooksInstalled then return end
    local tw = type(TilterWreck) == "table" and TilterWreck or nil
    local veh = tw and type(tw.Vehicle) == "table" and tw.Vehicle or nil
    if not veh or type(veh.update) ~= "function" then return end
    F.compatHooksInstalled = true
    local origUpdate = veh.update
    veh.update = function(v, ...)
        if v ~= nil then F.syncVehicleOccupants(v, true) end
        return origUpdate(v, ...)
    end
    if type(veh.pushBack) == "function" then
        local origPush = veh.pushBack
        veh.pushBack = function(v, obj, f, ...)
            if v ~= nil then F.syncVehicleOccupants(v, true) end
            return origPush(v, obj, f, ...)
        end
    end
end

function F.guardCellVehicles()
    if isClient() then return end
    if A.Convoy and type(A.Convoy.installHooks) == "function" then
        pcall(A.Convoy.installHooks)
    end
    pcall(F.installCompatHooks)
    for v in pairs(F.spVehicles) do
        F.syncVehicleOccupants(v, true)
    end
    if A.Convoy and type(A.Convoy.known) == "table" and type(getVehicleById) == "function" then
        for id in pairs(A.Convoy.known) do
            local v = getVehicleById(id)
            if v ~= nil then F.syncVehicleOccupants(v, true) end
        end
    end
    local p = ProjectALife
    if p and type(getVehicleById) == "function" then
        local owner = (isServer() and p.DrivingDemoServer) or p.DrivingDemoClient
        if owner then
            for id, s in pairs(owner.sessions or {}) do
                local v = (s and s.vehicle) or getVehicleById(id)
                if v ~= nil then F.syncVehicleOccupants(v, true) end
            end
            for id, rec in pairs(owner.sleeping or {}) do
                local v = (rec and rec.session and rec.session.vehicle) or getVehicleById(id)
                if v ~= nil then F.syncVehicleOccupants(v, true) end
            end
        end
        if p.VehicleArrivals and type(p.VehicleArrivals.active) == "table" then
            for id, car in pairs(p.VehicleArrivals.active) do
                local v = car or getVehicleById(id)
                if v ~= nil then F.syncVehicleOccupants(v, true) end
            end
        end
    end
    local now = A.now()
    if now < (F.nextCellGuardAt or 0) then return end
    F.nextCellGuardAt = now + 150
    local cell = type(getCell) == "function" and getCell() or nil
    local list = cell and type(cell.getVehicles) == "function" and cell:getVehicles() or nil
    if not list then return end
    pcall(function()
        if type(list.iterator) == "function" then
            local it = list:iterator()
            while it and it:hasNext() do
                local v = it:next()
                if v ~= nil then F.syncVehicleOccupants(v, true) end
            end
        elseif type(list.size) == "function" and type(list.get) == "function" then
            for i = 0, list:size() - 1 do
                local v = list:get(i)
                if v ~= nil then F.syncVehicleOccupants(v, true) end
            end
        end
    end)
end

if Events and Events.OnTick and type(Events.OnTick.Add) == "function" then
    Events.OnTick.Add(F.guardCellVehicles)
end

return F