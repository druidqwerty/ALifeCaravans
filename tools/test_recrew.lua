-- Exact regression: a seated driver plus one survivor outside, quota=1.
return function(check, newVehicle)
    local A, P = ALifeCaravans, ProjectALife
    local original = A.Spawn.survivors
    local car = newVehicle("Base.CarNormal", 100, 100)
    local other = newVehicle("Base.CarNormal", 102, 100)
    local driver, passenger = newShell("recrew-driver","fixture"), newShell("recrew-foot","fixture")
    local rows = {
        {uid="recrew-driver",generation=1,npc=driver,inCar=car},
        {uid="recrew-foot",generation=1,npc=passenger},
    }
    SHELLS[rows[1].uid], SHELLS[rows[2].uid] = driver, passenger
    for _, row in ipairs(rows) do ACTORS[row.uid] = {uid=row.uid,generation=1,lifecycle="active",revision=1,memory={}} end
    car.passengers[0] = driver
    A.Spawn.survivors = function() return rows end
    local c = {id="recrew-fixture",speedKmh=30,legPoints={{x=130,y=100}},actorUids={rows[1].uid,rows[2].uid}}
    A.tagVehicle(car,c.id,1)
    A.tagVehicle(other,c.id,2)
    local reserved = {}
    local ok, count = A.Spawn.recrew(c,car.id,nil,1,reserved)
    local binding = P.DrivingDemoClient.bindings[car.id]
    check("seated driver does not consume on-foot quota", ok and count==2)
    check("driver seat identity preserved", binding and binding.crew[1].uid==rows[1].uid and binding.crew[1].seat==0)
    check("outside passenger gets a real seat reservation", binding and binding.crew[2] and binding.crew[2].uid==rows[2].uid and binding.crew[2].seat==1)
    check("successful crew reserved across same allocation tick", reserved[rows[1].uid] and reserved[rows[2].uid])
    -- Simulate asynchronous boarding: the outside body still reports no car.
    local again = A.Spawn.recrew(c,other.id,nil,1,reserved)
    check("pending passenger not assigned to another car", not again)
    car.passengers = {[0]=PLAYER}
    rows[1].inCar = nil
    ok = A.Spawn.recrew(c,car.id,nil,2)
    check("player driver never displaced by recrew", not ok and car.passengers[0]==PLAYER)
    local stranger = {}
    car.passengers = {[0]=stranger}
    ok = A.Spawn.recrew(c,car.id,nil,2)
    check("unrelated NPC driver never displaced", not ok and car.passengers[0]==stranger)
    car.passengers = {[0]=driver,[1]=PLAYER}
    rows[1].inCar = car
    ok = A.Spawn.recrew(c,car.id,nil,1)
    binding = P.DrivingDemoClient.bindings[car.id]
    check("occupied live session cannot be replaced by recrew", not ok and car.passengers[1]==PLAYER)
    A.Spawn.survivors = original
    SHELLS[rows[1].uid], SHELLS[rows[2].uid] = nil,nil
    ACTORS[rows[1].uid], ACTORS[rows[2].uid] = nil,nil
    assert(loadfile(MOD_ROOT .. "/tools/test_rider_reload.lua"))()(check)
    assert(loadfile(MOD_ROOT .. "/tools/test_driver_keys.lua"))()(check)
end
