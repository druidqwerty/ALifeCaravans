return function(check, newVehicle)
    local A=ALifeCaravans
    local T,D=A.Threats,A.Director
    local saved={cell=getCell,safe=SafeHouse,resume=D.resume,list=A.Ledger.list,
        scan=T.scan,session=A.Spawn.sessionOf,queue=A.Crew.queue,
        living=A.settings.livingWorld,at=D.livingWorldCheckAtMs}
    local car=newVehicle("Base.CarNormal",100,100)
    local c={id="pressure",state="rendered",x=100,y=100,actorUids={},vehicleIds={car.id},
        halted=true,haltReason="wait"}
    local cars={{id=car.id,vehicle=car,x=100,y=100}}
    local bodies={}
    local function zombie(x,y,z,dead,owned)
        return {getX=function() return x end,getY=function() return y end,getZ=function() return z end,
            isDead=function() return dead end,getModData=function() return {ProjectALifeOwned=owned} end}
    end
    local square={}
    getCell=function() return {getZombieList=function() return {
        size=function() return #bodies end,get=function(_,i) return bodies[i+1] end} end,
        getGridSquare=function() return square end} end
    bodies={zombie(101,100,1),zombie(101,100,0,true),zombie(101,100,0,false,true),zombie(130,100,0)}
    check("local pressure excludes other floors corpses NPCs and remote zombies",T.scan(cars).near==0)
    bodies[#bodies+1]=zombie(104,100,0)
    bodies[#bodies+1]=zombie(102,100,0)
    check("local pressure counts nearby zombies once per convoy",T.scan({cars[1],cars[1]}).near==2 and T.scan(cars).contact==1)
    local resumed,queued=0,0
    D.resume=function(v) resumed=resumed+1 v.halted=nil v.haltReason=nil end
    A.Spawn.sessionOf=function() return {},{phase="seated"} end
    A.Crew.queue=function() queued=queued+1 end
    A.settings.livingWorld=true
    T.tick(c,CLOCK,cars)
    check("zombie at parked vehicle triggers departure instead of another halt",resumed==1 and c.threatState=="escape")
    check("seated crew is not dismounted or duplicated under threat",queued==0)
    T.tick(c,CLOCK+2000,cars)
    check("continued pressure cannot repeatedly stop the caravan",resumed==1 and not c.halted)
    A.Spawn.sessionOf=function() return {},nil,nil end
    T.tick(c,CLOCK+4000,cars)
    check("sessionless living crew receives normal safe reboarding request",queued==1)
    c.ambush,c.halted={state="fighting"},true
    T.tick(c,CLOCK+6000,cars)
    check("scripted combat retains its bounded fight and regroup policy",queued==1 and c.halted)
    c.ambush=nil
    bodies={}
    T.tick(c,CLOCK+18000,cars)
    check("escape status clears after quiet grace",c.threatState==nil)
    c.haltReason="horde_block"
    A.settings.livingWorld=false
    T.tick(c,CLOCK+20000,cars)
    check("saved obsolete horde stop migrates even with living world disabled",not c.halted)
    A.settings.livingWorld=true
    c.dangerUntilMs=0
    A.Ledger.list=function() return {c} end
    local calls=0
    SafeHouse={getSafeHouse=function(...)
        check("B42 safehouse lookup receives exactly one IsoGridSquare",select("#",...)==1 and (...)==square)
        calls=calls+1
        return nil
    end}
    D.livingWorldCheckAtMs=0
    D.livingWorldTick(CLOCK+22000,{})
    check("living world performs valid safehouse check",calls==1)
    square=nil
    D.livingWorldCheckAtMs=0
    D.livingWorldTick(CLOCK+24000,{})
    check("unloaded square never sent to SafeHouse API",calls==1)
    getCell,SafeHouse=saved.cell,saved.safe
    D.resume,A.Ledger.list,T.scan=saved.resume,saved.list,saved.scan
    A.Spawn.sessionOf,A.Crew.queue=saved.session,saved.queue
    A.settings.livingWorld,D.livingWorldCheckAtMs=saved.living,saved.at
end
