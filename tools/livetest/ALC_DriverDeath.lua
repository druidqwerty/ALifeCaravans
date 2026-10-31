-- TEST ONLY: inject on the explicit isolated MP server AFTER ALC_Audit PASS.
-- One real engine Kill(nil); never change registry, seats, sessions or physics.
assert(isServer() and not isClient(), "driver-death probe requires isolated MP server")
local A,P=ALifeCaravans,ProjectALife
assert(ALRLive and ALRLive.audit and ALRLive.audit.phase=="done" and ALRLive.audit.ok==true,
    "complete normal ALC_Audit PASS before the deliberate driver-death case")
local resuming=ALRLive.resumeDriverDeathObservation==true
ALRLive.resumeDriverDeathObservation=nil
local previous=ALRLive.driverDeath
assert(resuming or not previous, "driver-death probe already armed; never repeat Kill")
local player=ALRLive.player
assert(A and P and player and not player:getVehicle(), "need the on-foot isolated test player")
local T={started=getTimestampMs(),phase="select",samples={},original={},survivors={},cars={}}
if resuming then
    assert(previous and previous.killIssued==true and previous.deathEvent==true and previous.ok~=true,
        "resume requires the already-issued one-shot death and its exact event")
    assert(previous.phase~="select" and previous.phase~="kill", "resume must never enter a killing phase")
    local actor=P.ActorRegistry.read(previous.oldUid)
    assert(actor and actor.lifecycle=="dead" and actor.generation==previous.oldGeneration,
        "resume requires authoritative death of the original UID/generation")
    for key,value in pairs(previous) do if key~="done" then T[key]=value end end
    T.authorityDeathConfirmed=true
    previous.done=true -- Retire only the old observer closures; do not touch game state.
end
ALRLive.driverDeath=T
local function log(text)
    T.samples[#T.samples+1]=text
    print("[ALRLive] DRIVER_DEATH "..text)
end
local function finish(ok,why)
    T.done,T.ok=true,ok
    log("RESULT "..(ok and "PASS " or "FAIL ")..why)
    local w=getFileWriter("ALRLive_driver_death_result.txt",true,false)
    w:writeln((ok and "PASS " or "FAIL ")..why)
    w:writeln("scope=one engine Kill(nil), upstream actor death, original survivor becomes driver with authoritative car key; same car drives >=10 tiles")
    for _,line in ipairs(T.samples) do w:writeln(line) end
    w:close()
end
local function follow(now)
    assert(not player:getVehicle(), "test player entered a car")
    if A.dist(player:getX(),player:getY(),T.car:getX(),T.car:getY())<=13 then return end
    if now-(T.followAt or 0)<3000 then return end
    T.followAt=now
    sendServerCommand(player,"ALRLiveMP","teleport",{x=T.car:getX()+7,y=T.car:getY()+7})
end
local function selectCar()
    T.c=ALRLive.audit.c
    assert(T.c and A.Ledger.get(T.c.id)==T.c and T.c.state=="rendered", "audited caravan is not rendered")
    for _,uid in ipairs(T.c.actorUids or {}) do T.original[uid]=true end
    local best=math.huge
    for _,id in ipairs(T.c.vehicleIds or {}) do
        local car=getVehicleById(id)
        assert(car and A.vehicleTag(car)==T.c.id and not A.vehicleHasPlayer(car), "caravan car missing, foreign or player occupied")
        T.cars[id]=car
        local driver,count,crew=car:getDriver(),0,{}
        for seat=0,car:getMaxPassengers()-1 do
            local body=car:getCharacter(seat)
            if body and instanceof(body,"IsoZombie") and not body:isDead() then
                local data=body:getModData()
                local actor=data.ProjectALifeUID and P.ActorRegistry.read(data.ProjectALifeUID)
                assert(T.original[data.ProjectALifeUID] and actor and actor.lifecycle=="active"
                    and actor.generation==data.ProjectALifeGeneration and body:getVehicle()==car, "unproven original crew body")
                count=count+1
                crew[data.ProjectALifeUID]={body=body,generation=data.ProjectALifeGeneration,seat=seat}
            end
        end
        local distance=A.dist(player:getX(),player:getY(),car:getX(),car:getY())
        if driver and instanceof(driver,"IsoZombie") and not driver:isDead() and count>=2 and distance<best then
            best=distance
            T.id,T.car,T.old,T.crew=id,car,driver,crew
        end
    end
    assert(T.car, "PRECONDITION audited caravan needs a real driver plus a living passenger")
    T.oldUid=T.old:getModData().ProjectALifeUID
    T.oldGeneration=T.old:getModData().ProjectALifeGeneration
    for uid,row in pairs(T.crew) do if uid~=T.oldUid then T.survivors[uid]=row end end
    log("SELECT car="..T.id.." originalDriver="..T.oldUid.." generation="..T.oldGeneration)
    for uid,row in pairs(T.survivors) do log("SURVIVOR uid="..uid.." generation="..row.generation.." originalSeat="..row.seat) end
    T.phase="kill"
end
local function identities()
    assert(A.Ledger.get(T.c.id)==T.c and getVehicleById(T.id)==T.car, "caravan or original vehicle replaced")
    local ids={}
    for _,id in ipairs(T.c.vehicleIds or {}) do
        assert(T.cars[id] and getVehicleById(id)==T.cars[id], "new or replaced caravan car")
        ids[id]=true
    end
    for id in pairs(T.cars) do assert(ids[id], "original caravan car removed") end
    local roster={}
    for _,uid in ipairs(T.c.actorUids or {}) do assert(T.original[uid], "new NPC UID added"); roster[uid]=true end
    for uid,row in pairs(T.survivors) do
        local actor=P.ActorRegistry.read(uid)
        assert(roster[uid] and actor and actor.lifecycle~="dead" and actor.generation==row.generation
            and P.DrivingDemo.findNpc(uid,row.generation)==row.body and not row.body:isDead(), "original survivor removed, replaced or killed")
    end
    local iterator=getCell():getVehicles():iterator()
    while iterator:hasNext() do
        local car=iterator:next()
        if A.vehicleTag(car)==T.c.id then assert(T.cars[car:getId()]==car, "new tagged caravan car spawned") end
    end
    assert(not A.vehicleHasPlayer(T.car), "player occupied the test vehicle")
    for seat=0,T.car:getMaxPassengers()-1 do
        local body=T.car:getCharacter(seat)
        if body then assert(T.crew[body:getModData().ProjectALifeUID]
            and T.crew[body:getModData().ProjectALifeUID].body==body, "new NPC body seated") end
    end
end
Events.OnZombieDead.Add(function(body)
    if not T.done and body==T.old then T.deathEvent=true end
end)
local function tick()
    if T.done then return end
    local now=getTimestampMs()
    if now-(T.tickAt or 0)<250 then return end
    T.tickAt=now
    if now-T.started>180000 then finish(false,"timeout phase="..T.phase.." deathEvent="..tostring(T.deathEvent)) return end
    if T.phase=="select" then selectCar() return end
    identities()
    follow(now)
    if T.phase=="kill" then
        assert(not T.killIssued and T.car:getDriver()==T.old and not T.old:isDead(), "driver changed before one-shot death")
        T.killIssued=true
        T.old:Kill(nil)
        T.phase="recover"
        log("KILL_ONCE uid="..T.oldUid.." attacker=nil")
        return
    end
    local oldActor=P.ActorRegistry.read(T.oldUid)
    -- Dead shells are pooled and may later report isDead=false for a new actor.
    -- Exact death event plus authoritative original UID/generation is durable proof.
    if T.deathEvent and oldActor and oldActor.lifecycle=="dead" and oldActor.generation==T.oldGeneration then
        T.authorityDeathConfirmed=true
    end
    local dead=T.authorityDeathConfirmed==true
    local driver=T.car:getDriver()
    local uid=driver and driver:getModData().ProjectALifeUID
    local original=uid and T.survivors[uid]
    local key=false
    if driver and driver~=T.old then
        assert(original and original.body==driver and not driver:isDead() and driver:getVehicle()==T.car,
            "replacement driver is not an original living survivor")
        local inventory=driver:getInventory()
        key=inventory and inventory:haveThisKeyId(T.car:getKeyId())~=nil or false
    end
    if dead and original and key and T.car:isEngineRunning() then
        if not T.driveOrigin then
            T.newUid,T.driveOrigin=uid,{x=T.car:getX(),y=T.car:getY()}
            T.phase="drive"
            log("REPLACED originalSurvivor="..uid.." actualSeat="..T.car:getSeat(driver).." keyId="..T.car:getKeyId())
        end
        assert(uid==T.newUid and T.car:getSeat(driver)==0, "new driver/seat changed during drive proof")
        T.distance=A.dist(T.car:getX(),T.car:getY(),T.driveOrigin.x,T.driveOrigin.y)
        if T.distance>=10 then
            finish(true,string.format("car=%d old=%s newOriginalSurvivor=%s key=true realDistance=%.2f no new car/NPC",T.id,T.oldUid,uid,T.distance))
            return
        end
    end
    if now-(T.sampleAt or 0)>=2000 then
        T.sampleAt=now
        log(string.format("t=%d phase=%s confirmedDeath=%s deathEvent=%s registryDead=%s driver=%s key=%s engine=%s distance=%.2f",
            now-T.started,T.phase,tostring(dead),tostring(T.deathEvent),tostring(oldActor and oldActor.lifecycle=="dead"),
            tostring(uid),tostring(key),tostring(T.car:isEngineRunning()),T.distance or 0))
    end
end
Events.OnTick.Add(function()
    if T.done then return end
    local ok,err=pcall(tick)
    if not ok then finish(false,tostring(err)) end
end)
if resuming then log("OBSERVATION_CORRECTION pooled old shell is not a living-state oracle; same one-shot case, original180s deadline retained")
else log("ARMED after ordinary two-crew audit PASS; no forced seats, sessions, keys or driving") end
