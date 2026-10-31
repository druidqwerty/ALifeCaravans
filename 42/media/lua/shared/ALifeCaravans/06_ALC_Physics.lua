-- B42.21 retains native wheel brakes across an NPC vehicle handoff.
-- Clear the parked controller only once at the start of a verified ALC drive.
-- Uses our small bridge loaded by standard ZombieBuddy; no authority changes,
-- vehicle relocation, extra propulsion or replacement of A-Life's controller.
require "ALifeCaravans/00_ALC_Core"
local A = ALifeCaravans
local F = {}
A.Physics = F

function F.prepare(s, entry)
    if not s or not entry or isServer() then return false end
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
            or instanceof(npc, "IsoPlayer") or A.vehicleHasPlayer(v) then return false end
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
        if ALCNativeReleaseBrake(v) ~= true then error("native guard declined parked-brake release") end
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
