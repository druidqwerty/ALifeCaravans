-- DrivingCrewHome restores bindings/modes, not a live or sleeping session.
-- Use actual registry-backed survivor lookup and real owner table shapes.
return function(check)
    local A, P = ALifeCaravans, ProjectALife
    local owner, oldClock = P.VehicleArrivals.owner(), CLOCK
    local car = newVehicle("Base.CarNormal", 100, 100)
    car.speed = 0
    function car:getCurrentSpeedKmHour() return self.speed end
    local driver = newShell("reload-rider-driver", "fixture")
    local rider = newShell("reload-rider-guard", "fixture")
    for _, npc in ipairs({driver, rider}) do
        npc.x, npc.y = car.x, car.y
        SHELLS[npc.uid] = npc
        ACTORS[npc.uid] = {uid=npc.uid,generation=1,revision=1,lifecycle="active",memory={}}
    end
    driver.vehicle = car
    car.passengers = {[0]=driver,[1]=PLAYER}
    local c = {id="restored-rider-fixture",state="rendered",x=100,y=100,speedKmh=30,
        vehicleIds={car.id},actorUids={driver.uid,rider.uid},legPoints={{x=150,y=100}}}
    A.tagVehicle(car,c.id,1)
    local binding = {vehicleId=car.id,restoredCrew=true,revision=1,
        crew={{uid=driver.uid,generation=1,seat=0},{uid=rider.uid,generation=1,seat=2}}}
    owner.bindings[car.id] = binding
    owner.allowRiders[car.id], owner.carModes[car.id] = true, "mixed"
    local function eligible() return A.Spawn.canRestoreRiders(c,car.id) end
    check("saved mixed passenger binding is eligible without session", eligible())
    car.speed = 2
    check("saved passenger recovery refuses a moving car", not eligible())
    car.speed, car.x = 0, 1000
    check("saved passenger recovery refuses unloaded car", not eligible())
    car.x = 100
    A.tagVehicle(car,"foreign",1)
    check("saved passenger recovery proves caravan ownership", not eligible())
    A.tagVehicle(car,c.id,1)
    car.passengers[0] = PLAYER
    check("saved passenger recovery never claims human driver", not eligible())
    car.passengers[0] = driver
    owner.allowRiders[car.id] = false
    check("saved passenger recovery requires explicit rider permission", not eligible())
    owner.allowRiders[car.id], owner.carModes[car.id] = true, "player"
    check("saved passenger recovery never claims player mode", not eligible())
    owner.carModes[car.id], binding.restoredCrew = "mixed", nil
    check("saved passenger recovery requires restored binding provenance", not eligible())
    binding.restoredCrew, owner.sessions[car.id] = true, {vehicle=car}
    local held = owner.sessions[car.id]
    local ok = A.Spawn.recrew(c,car.id,nil,1)
    check("saved passenger recovery preserves an existing live session", not ok and owner.sessions[car.id]==held)
    owner.sessions[car.id], owner.sleeping[car.id] = nil, {session={vehicle=car}}
    held = owner.sleeping[car.id]
    ok = A.Spawn.recrew(c,car.id,nil,1)
    check("saved passenger recovery preserves sleeping handoff", not ok and owner.sleeping[car.id]==held)
    owner.sleeping[car.id], owner.departures[car.id] = nil, {}
    check("saved passenger recovery waits for queued departure", not eligible())
    owner.departures[car.id], owner.pending[car.id] = nil, {}
    check("saved passenger recovery waits for pending action", not eligible())
    owner.pending[car.id] = nil
    binding.crew[2].uid = "someone-else"
    check("saved passenger recovery rejects unowned bound crew", not eligible())
    binding.crew[2].uid = rider.uid
    ACTORS[driver.uid].lifecycle, ACTORS[rider.uid].lifecycle = "dead", "dormant"
    check("saved passenger recovery requires real living owned bodies", not eligible())
    ACTORS[driver.uid].lifecycle, ACTORS[rider.uid].lifecycle = "active", "active"
    car.passengers[3] = newShell("stranger", "other")
    check("saved passenger recovery leaves unrelated NPC occupant alone", not eligible())
    car.passengers[3] = nil
    -- Exercise the watchdog bypass, not only the direct Spawn helper.
    A.Crew.queue(c,car.id,"reload",CLOCK)
    CLOCK = CLOCK + 4001
    A.Crew.tick(c,CLOCK)
    local session = owner.sessions[car.id]
    binding = owner.bindings[car.id]
    check("watchdog recreates missing saved passenger session", session and session.uid==driver.uid and next(c.recrew)==nil)
    check("saved passenger retains actual seat while owned guard takes free seat", car.passengers[1]==PLAYER
        and binding.crew[1].seat==0 and binding.crew[2].seat==2 and car.passengers[2]==rider)
    check("recreated boarding session distinguishes seated NPC from approaching guard", binding.crew[1].boarded==true
        and binding.crew[2].boarded~=true)
    check("recreated passenger session retains explicit mixed permission", owner.allowRiders[car.id]==true and owner.carModes[car.id]=="mixed")
    -- A transient create failure must not erase the permission needed to retry.
    owner.sessions[car.id], owner.departures[car.id] = nil, nil
    local create = P.DrivingLifecycle.create
    P.DrivingLifecycle.create = function() return nil,"transient restore" end
    ok = A.Spawn.recrew(c,car.id,nil,1)
    P.DrivingLifecycle.create = create
    check("failed saved passenger create preserves eligibility and seat", not ok and eligible() and car.passengers[1]==PLAYER)
    ok = A.Spawn.recrew(c,car.id,nil,1)
    check("saved passenger restore retries after transient create failure", ok and owner.sessions[car.id]~=nil)
    owner.sessions[car.id], owner.departures[car.id] = nil, nil
    local server = isServer
    isServer = function() return true end
    ok = A.Spawn.recrew(c,car.id,nil,1)
    isServer = server
    check("failed server suspend preserves passenger restore permission for retry", not ok and eligible()
        and owner.sessions[car.id]==nil and car.passengers[1]==PLAYER)
    -- Release bookkeeping for this isolated fixture only; production cleanup guards
    -- are unchanged and tested separately in test_ownership/test_crew.
    car.passengers[1] = nil
    A.Spawn.releaseCar(car.id,c.id)
    for _, npc in ipairs({driver, rider}) do ACTORS[npc.uid], SHELLS[npc.uid] = nil, nil end
    VEHICLES[car.id], CLOCK = nil, oldClock
end
