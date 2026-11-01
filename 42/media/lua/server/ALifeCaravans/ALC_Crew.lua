-- Recovery policy for real caravan crews. A stop is not a destroyed car.
require "ALifeCaravans/00_ALC_Core"
local A = ALifeCaravans
local R = { retryMs = 8000, quietMs = 10000, missingGraceMs = 12000 }
A.Crew = R

local function sessionMembers(s)
    if not s then return {} end
    local demo = ProjectALife and ProjectALife.DrivingDemo
    if demo and type(demo.members) == "function" then return demo.members(s) end
    local members = {s}
    for _, rider in ipairs(s.riders or {}) do members[#members+1] = rider end
    return members
end

-- A-Life keeps a sleeping binding forever when ANY attached crew member died:
-- DrivingLifecycle.resolve refuses that actor and cannot revise its own crew.
-- Missing/dormant actors and ownership handoffs are NOT proof of death.
function R.deadSleepingCrew(c, id, s, sleeping, now, owner)
    c.crewDeadAt = c.crewDeadAt or {}
    local key = tostring(id)
    local owned = {}
    for _, uid in ipairs(c.actorUids or {}) do owned[uid] = true end
    local registry = ProjectALife and ProjectALife.ActorRegistry
    local binding = owner and owner.bindings and owner.bindings[id]
    local dead = false
    if sleeping and registry then
        local members = binding and binding.crew or sessionMembers(s)
        for _, member in ipairs(members or {}) do
            if owned[member.uid] then
                local ok, actor = pcall(registry.read, member.uid)
                if ok and actor and actor.lifecycle == "dead" then dead = true break end
            end
        end
    end
    if not dead then
        c.crewDeadAt[key] = nil
        return false
    end
    c.crewDeadAt[key] = c.crewDeadAt[key] or now
    return now - c.crewDeadAt[key] >= R.missingGraceMs
end

function R.queue(c, id, reason, now)
    c.recrew = c.recrew or {}
    local key = tostring(id)
    if c.recrew[key] then return end
    c.recrew[key] = {vehicleId=id, reason=reason or "regroup", firstAtMs=now, dueMs=now+4000}
end

function R.finished(c, id, reason)
    if c.state ~= "rendered" and c.state ~= "fighting" then return end
    local owned = false
    for _, vid in ipairs(c.vehicleIds or {}) do if vid == id then owned = true end end
    if not owned then return end
    R.queue(c, id, reason, A.now())
    A.Director.publishDirty = true
end

function R.watch(c, now)
    if c.state ~= "rendered" and c.state ~= "fighting" then return end
    -- Combat may finish outside the scripted ambush path (threats/attacks).
    if c.state == "fighting" and not (c.ambush and c.ambush.state == "fighting") then
        local clear = A.Spawn.zombiesNear(c.x, c.y, 22) == 0
        if clear then c.crewQuietAtMs = c.crewQuietAtMs or now else c.crewQuietAtMs = nil end
        local age = now - (c.fightingAtMs or now)
        if (age >= 20000 and c.crewQuietAtMs and now-c.crewQuietAtMs >= R.quietMs) or age >= 150000 then
            c.state = "rendered"
            A.Director.resume(c)
            for _, id in ipairs(c.vehicleIds or {}) do R.queue(c,id,"post_combat",now) end
        else return end
    end
    if c.halted or (c.ambush and c.ambush.state == "fighting") then return end
    c.crewMissing = c.crewMissing or {}
    for _, id in ipairs(c.vehicleIds or {}) do
        local owner, s, sleeping = A.Spawn.sessionOf(id)
        if R.deadSleepingCrew(c,id,s,sleeping,now,owner) then
            R.queue(c,id,"dead_suspended_member",now)
        elseif s or sleeping then
            c.crewMissing[tostring(id)] = nil
        elseif A.Spawn.canRestoreRiders(c,id) then
            R.queue(c,id,"passenger_crew_recovery",now)
        else
            local key = tostring(id)
            c.crewMissing[key] = c.crewMissing[key] or now
            if now-c.crewMissing[key] >= R.missingGraceMs then R.queue(c,id,"unexpected_exit",now) end
        end
    end
end

function R.tick(c, now)
    if c.halted or c.state == "fighting" or (c.ambush and c.ambush.state == "fighting") then return end
    local pending, reserved = {}, {}
    -- Reserve crew in sessions from earlier ticks as well as this allocation tick.
    for _, id in ipairs(c.vehicleIds or {}) do
        local owner, s, sleeping = A.Spawn.sessionOf(id)
        if s and not s.exitAt and not s.exitRequested and not s.detaching
                and not R.deadSleepingCrew(c,id,s,sleeping,now,owner) then
            for _, member in ipairs(sessionMembers(s)) do
                if member.uid then reserved[member.uid] = true end
            end
        end
    end
    for key, request in pairs(c.recrew or {}) do
        if now >= (request.dueMs or 0) then pending[#pending+1] = {key=key, request=request} end
    end
    table.sort(pending,function(a,b) return tostring(a.request.vehicleId)<tostring(b.request.vehicleId) end)
    if #pending == 0 then return end
    local free = 0
    for _, row in ipairs(A.Spawn.survivors(c,c.x or 0,c.y or 0,100)) do
        if row.inCar == nil and not reserved[row.uid] then free=free+1 end
    end
    local quota = math.max(1, math.ceil(free/#pending))
    for _, item in ipairs(pending) do
        local q, id = item.request, item.request.vehicleId
        local car = getVehicleById(id)
        local owner, s, sleeping = A.Spawn.sessionOf(id)
        if car and not A.vehicleHasPlayer(car) and R.deadSleepingCrew(c,id,s,sleeping,now,owner) then
            if A.Spawn.releaseCar(id, c.id) then s, sleeping = nil, nil end
        end
        local busy = s and not s.exitAt and not s.exitRequested and not s.detaching
        -- Do not destroy an in-flight handoff or a boarding session to retry it.
        if busy or sleeping then
            c.recrew[item.key] = nil
        elseif car and A.vehicleHasPlayer(car) and not A.Spawn.canRestoreRiders(c, id) then
            q.dueMs = now+R.retryMs
        else
            local ok, detail = A.Spawn.recrew(c,id,nil,quota,reserved)
            if ok then
                c.recrew[item.key] = nil
                A.Director.publishDirty = true
                A.log(c.id,"car",id,"crew returning:",q.reason,detail)
            else
                q.firstAtMs = q.firstAtMs or now
                q.tries = (q.tries or 0)+1
                q.dueMs = now+math.min(30000,R.retryMs*q.tries)
                q.lastReason = tostring(detail)
                -- A temporary missing body, blocked door or absent owner never
                -- proves destruction. Keep the car and retry with bounded backoff.
                local registry = ProjectALife and ProjectALife.ActorRegistry
                local allDead = #(c.actorUids or {}) > 0 and registry ~= nil
                for _, uid in ipairs(c.actorUids or {}) do
                    local readOK, actor = pcall(function() return registry and registry.read(uid) end)
                    if not readOK or not actor or actor.lifecycle ~= "dead" then allDead=false break end
                end
                if allDead and now-q.firstAtMs >= 30000 then
                    A.Director.abandonCar(c,id,"crew_dead")
                end
            end
        end
    end
end

return R
