-- Local vehicle pressure, not an arbitrary district-wide zombie count.
require "ALifeCaravans/00_ALC_Core"
local A = ALifeCaravans
local T = {}
A.Threats = T

function T.scan(cars)
    local result = {near=0, contact=0, closest=math.huge}
    local cell = type(getCell) == "function" and getCell()
    local zombies = cell and cell:getZombieList()
    if not zombies then return result end
    for i=0,zombies:size()-1 do
        local zombie = zombies:get(i)
        local data = zombie:getModData()
        if not zombie:isDead() and not (data and data.ProjectALifeOwned == true) then
            local x,y,z = A.xyz(zombie)
            local distance = math.huge
            for _, row in ipairs(cars) do
                local _,_,cz = A.xyz(row.vehicle)
                if x and math.floor(z or 0)==math.floor(cz or 0) then
                    distance = math.min(distance,A.dist(x,y,row.x,row.y))
                end
            end
            if distance <= 8 then
                result.near = result.near+1
                result.closest = math.min(result.closest,distance)
                if distance <= 2.5 then result.contact=result.contact+1 end
            end
        end
    end
    return result
end

function T.tick(c, now, cars)
    local D = A.Director
    -- Migrate an old saved horde stop even when LivingWorld was disabled.
    if c.halted and c.haltReason == "horde_block" then D.resume(c) end
    if not A.settings.livingWorld or c.state ~= "rendered" then return end
    local pressure = T.scan(cars)
    local urgent = pressure.contact > 0 or (pressure.near >= 3 and pressure.closest <= 5)
    if urgent then
        c.dangerUntilMs = now+10000
        if not c.threatState then
            c.threatState = "escape"
            c.threatEscapeStartMs = now
            c.threatEscapeX, c.threatEscapeY = c.x, c.y
            D.publishDirty = true
            A.log(c.id,"local threat: attempting departure",pressure.near,pressure.contact)
        elseif c.threatEscapeX and c.x and A.dist(c.x, c.y, c.threatEscapeX, c.threatEscapeY) >= 2.5 then
            c.threatEscapeStartMs = now
            c.threatEscapeX, c.threatEscapeY = c.x, c.y
        end
        -- The scripted fight has its own bounded regroup; do not cancel it
        -- midway or manufacture passengers. Normal parked crews stay seated
        -- unless a swarm pins the car in place and prevents departure.
        if not (c.ambush and c.ambush.state == "fighting") then
            if c.halted then D.resume(c) end
            local hasSeatedSession = false
            for _, row in ipairs(cars) do
                local _, session, sleeping = A.Spawn.sessionOf(row.id)
                if not session and not sleeping then
                    A.Crew.queue(c,row.id,"danger_return",now)
                elseif session and not session.exitAt and not session.exitRequested then
                    hasSeatedSession = true
                end
            end
            local pinned = hasSeatedSession and c.threatEscapeStartMs and (now - c.threatEscapeStartMs >= 8000)
                and (pressure.contact >= 2 or (pressure.contact >= 1 and pressure.near >= 4))
                and not (type(D.ridersAboard) == "function" and D.ridersAboard(c))
            if pinned and A.Spawn and type(A.Spawn.dismount) == "function" then
                c.state = "fighting"
                c.fightingAtMs = now
                c.crewQuietAtMs = nil
                c.threatState, c.threatEscapeStartMs = nil, nil
                A.Spawn.dismount(c, { x = c.x or cars[1].x, y = c.y or cars[1].y })
                D.publishDirty = true
                A.log(c.id, "local threat pinned car: crew dismounting to fight", pressure.near, pressure.contact)
                return
            end
        end
        if now >= (c.threatSaidAtMs or 0) then
            c.threatSaidAtMs = now+20000
            local shell,uid = D.driverShell(c)
            if shell then A.Lines.say(shell,"horde_block",{uid=uid,cooldownMs=20000}) end
        end
    elseif c.threatState and now >= (c.dangerUntilMs or 0) then
        c.threatState = nil
        c.threatEscapeStartMs, c.threatEscapeX, c.threatEscapeY = nil, nil, nil
        D.publishDirty = true
    end
end

return T
