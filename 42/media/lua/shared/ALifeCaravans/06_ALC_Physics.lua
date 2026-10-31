-- B42.21 retains native wheel brakes across an NPC vehicle handoff.
-- Clear the parked controller only once at the start of a verified ALC drive.
-- Standard ZombieBuddy bridge; no vehicle relocation, extra propulsion or AI
-- replacement. SP leases local simulation and wakes a verified driving body
-- through vanilla chunk-aware activation (including cars restored from a save).
require "ALifeCaravans/00_ALC_Core"
local A = ALifeCaravans
local F = { spVehicles = {} }
A.Physics = F

function F.ridersAllowed(v)
    local r = ProjectALife and ProjectALife.DrivingRiders
    return r and type(r.allowed) == "function" and r.allowed(v:getId()) == true or false
end

function F.playersAllowed(v)
    if not A.vehicleHasPlayer(v) then return true end
    if not F.ridersAllowed(v) or instanceof(v:getDriver(), "IsoPlayer") then return false end
    for seat = 0, v:getMaxPassengers()-1 do
        local body = v:getCharacter(seat)
        if body and instanceof(body, "IsoPlayer") and (seat == 0 or body:getVehicle() ~= v) then return false end
    end
    return true
end

function F.releaseSP(v)
    if not v or isServer() or isClient() then return false end
    F.spVehicles[v] = nil
    if type(ALCNativeReleaseSP) ~= "function" then return false end
    local ok, result = pcall(ALCNativeReleaseSP, v)
    if not ok then A.log("SP vehicle lease release failed:", tostring(result)) end
    return ok and result == true
end

-- No MP bypass: the multiplayer handoff/owner rules remain entirely A-Life's.
-- This guard accepts members approaching their reserved doors as well as those
-- already seated. It never teleports or seats an NPC itself.
function F.ensureSP(s, entry)
    if isServer() or isClient() or not s or not entry or s.alcSPError
            or type(ALCNativeAcquireSP) ~= "function" then return false end
    local v, npc = s.vehicle, s.npc
    if not v or not npc or not A.Convoy or A.Convoy.known[v:getId()] ~= entry
            or A.Convoy.sessionFor(v:getId()) ~= s then return false end
    local function refuse() F.releaseSP(v) return false end
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
    for seat = 0, v:getMaxPassengers()-1 do
        local body = v:getCharacter(seat)
        if body and not seenBodies[body] and not (seat > 0 and instanceof(body, "IsoPlayer") and F.ridersAllowed(v)) then return refuse() end
    end
    local driving = allBoarded and s.phase == "driving" and s.entryComplete == true and not entry.halted
        and not s.braking and not s.exitAt and not s.exitRequested and not s.detaching
    local ok, result = pcall(ALCNativeAcquireSP, v, npc, entry.caravanId, s.uid, s.generation, F.ridersAllowed(v), driving)
    if not ok then
        if not s.alcSPError then A.log("SP vehicle adapter failed:", tostring(result)) end
        s.alcSPError = true
        return refuse()
    end
    if result == true then F.spVehicles[v] = s return true end
    return refuse()
end

-- Called when known caravans/session lifetimes change. Sleeping/restoring a car
-- may create a different session; only an explicit revalidated prepare reacquires.
function F.sweepSP()
    if isServer() or isClient() then return end
    local release = {}
    for v, s in pairs(F.spVehicles) do
        if not A.Convoy or not A.Convoy.known[v:getId()] or A.Convoy.sessionFor(v:getId()) ~= s
                or not F.playersAllowed(v) then release[#release + 1] = v end
    end
    for _, v in ipairs(release) do F.releaseSP(v) end
end

function F.prepare(s, entry)
    if not s or not entry or isServer() then return false end
    if not isClient() then F.ensureSP(s, entry) end
    if s.phase ~= "driving" then s.alcBrakeReleased = nil return false end
    if s.alcBrakeReleased or s.alcBrakeError or entry.halted or s.braking or s.exitAt or s.exitRequested
            or s.detaching or not s.entryComplete or type(ALCNativeReleaseBrake) ~= "function" then return false end
    local v, npc = s.vehicle, s.npc
    if not v or not npc or not A.Convoy or A.Convoy.known[v:getId()] ~= entry then return false end
    if A.Convoy.sessionFor(v:getId()) ~= s then return false end
    if not v:isLocalPhysicSim() then return false end
    if isClient() then
        local player = getSpecificPlayer(0)
        if not player or v:getNetPlayerId() ~= player:getOnlineID() then return false end
    end
    if math.abs(v:getCurrentSpeedKmHour()) > 0.5 or not v:isEngineRunning()
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
    local original = v:getBrakingForce()
    local ok, err = pcall(function()
        v:setBrakingForce(0)
        if ALCNativeReleaseBrake(v, F.ridersAllowed(v)) ~= true then error("native guard declined parked-brake release") end
    end)
    -- Restore the vehicle's brake specification even if the bridge throws.
    v:setBrakingForce(original)
    if not ok then
        if not s.alcBrakeError then A.log("parked brake release refused:", tostring(err)) end
        s.alcBrakeError = true
        return false
    end
    s.alcBrakeReleased = true
    A.debug("car", v:getId(), "native parked brake released for NPC drive")
    return true
end

return F
