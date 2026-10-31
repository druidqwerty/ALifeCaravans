-- MP 215915: initial driver died; promoted survivor boarded but could not start
-- the engine because only the dead arrival driver had received the vehicle key.
return function(check)
    local A, P = ALifeCaravans, ProjectALife
    local S, owner = A.Spawn, P.VehicleArrivals.owner()
    local car = newVehicle("Base.CarNormal",100,100)
    local dead = newShell("key-dead-driver","fixture")
    local survivor = newShell("key-promoted-driver","fixture")
    for _, npc in ipairs({dead,survivor}) do
        npc.x,npc.y = car.x,car.y
        SHELLS[npc.uid] = npc
        ACTORS[npc.uid] = {uid=npc.uid,generation=1,lifecycle="active",revision=1,memory={}}
    end
    dead.dead, ACTORS[dead.uid].lifecycle = true,"dead"
    local c = {id="driver-key-fixture",speedKmh=30,x=100,y=100,
        vehicleIds={car.id},actorUids={dead.uid,survivor.uid},legPoints={{x=140,y=100}}}
    A.tagVehicle(car,c.id,1)
    local old = {vehicle=car,uid=dead.uid,exitRequested=true}
    local binding = {vehicleId=car.id,crew={{uid=dead.uid,generation=1,seat=0}}}
    owner.sessions[car.id], owner.bindings[car.id] = old,binding
    local grant, calls, releases = P.VehicleArrivalKeys.grant,#KEY_GRANTS,#RELEASED
    local function untouched()
        return owner.sessions[car.id]==old and owner.bindings[car.id]==binding
            and #RELEASED==releases and #KEY_GRANTS==calls
    end
    P.VehicleArrivalKeys.grant = nil
    local ok,reason = S.recrew(c,car.id,nil,1)
    check("missing key service defers promotion without release",not ok and reason=="driver_key_service_unavailable" and untouched())
    P.VehicleArrivalKeys.grant = function() return false,"registry conflict" end
    ok,reason = S.recrew(c,car.id,nil,1)
    check("refused key grant retains original session for retry",not ok and reason=="driver_key_failed:registry conflict" and untouched())
    P.VehicleArrivalKeys.grant = function() error("key inventory unavailable") end
    ok,reason = S.recrew(c,car.id,nil,1)
    check("throwing key grant retains original session for retry",not ok and string.find(reason,"driver_key_failed:",1,true)==1 and untouched())
    P.VehicleArrivalKeys.grant = grant
    A.tagVehicle(car,"foreign-owner",1)
    ok,reason = S.recrew(c,car.id,nil,1)
    check("foreign car cannot grant a key to caravan crew",not ok and reason=="foreign_car" and untouched())
    A.tagVehicle(car,c.id,1)
    local survivors = S.survivors
    S.survivors = function(...)
        local rows=survivors(...)
        ACTORS[survivor.uid].generation=2
        return rows
    end
    ok,reason = S.recrew(c,car.id,nil,1)
    check("driver generation change cannot grant key to stale body",not ok and reason=="driver_changed" and untouched())
    ACTORS[survivor.uid].generation=1
    S.survivors = function(...)
        local rows=survivors(...)
        survivor.dead=true
        return rows
    end
    ok,reason = S.recrew(c,car.id,nil,1)
    check("driver dying after selection cannot receive replacement key",not ok and reason=="driver_changed" and untouched())
    survivor.dead=false
    -- The grant must receive a fresh registry revision, not the earlier candidate.
    local fresh = {uid=survivor.uid,generation=1,lifecycle="active",revision=17,memory={}}
    S.survivors = function(...)
        local rows=survivors(...)
        ACTORS[survivor.uid]=fresh
        return rows
    end
    ok = S.recrew(c,car.id,nil,1)
    S.survivors = survivors
    local received=KEY_GRANTS[#KEY_GRANTS]
    check("dead-driver replacement grants key to exact promoted live driver",ok and received and received.npc==survivor
        and received.car==car and received.actor==fresh and received.actor.revision==17)
    check("promoted driver key goes through persistent ArrivalKeys contract",fresh.memory.arrivalCarKey
        and fresh.memory.arrivalCarKey.keyId==car.id and survivor.testKeys[car.id]~=nil and dead.testKeys==nil)
    check("keyed survivor becomes actual driver session and seat zero",owner.sessions[car.id].uid==survivor.uid
        and owner.bindings[car.id].crew[1].seat==0 and car.passengers[0]==survivor)
    local key=survivor.testKeys[car.id]
    ok=S.recrew(c,car.id,nil,1)
    check("repeat reboard reuses existing vehicle key",ok and survivor.testKeys[car.id]==key)
    S.releaseCar(car.id,c.id)
    for _,npc in ipairs({dead,survivor}) do ACTORS[npc.uid],SHELLS[npc.uid]=nil,nil end
    VEHICLES[car.id]=nil
end
