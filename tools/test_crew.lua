-- Lifecycle regressions: stops and absent replicas are not proof of a wreck.
return function(check,newVehicle)
    local A=ALifeCaravans
    local D,R,S=A.Director,A.Crew,A.Spawn
    local saved={session=S.sessionOf,recrew=S.recrew,survivors=S.survivors,zombies=S.zombiesNear,
        get=A.Ledger.get,resume=D.resume,abandon=D.abandonCar,release=S.releaseCar}
    local car=newVehicle("Base.CarNormal",100,100)
    local c={id="crew-regression",state="rendered",vehicleIds={car.id},actorUids={},x=100,y=100,
        speedKmh=30,goals={{x=200,y=100}},trip=1}
    A.tagVehicle(car,c.id,1)
    local session, attempts, scraps, resumed=nil,0,0,0
    S.sessionOf=function() return {},session end
    S.survivors=function() return {} end
    S.recrew=function() attempts=attempts+1 return false,"no_survivors" end
    D.abandonCar=function() scraps=scraps+1 end
    D.resume=function(v) v.halted=nil resumed=resumed+1 end
    A.Ledger.get=function() return c end
    for i=1,12 do D.onSessionFinished(c.id,car.id,"temporary blockage") end
    check("repeated finish notifications never scrap a healthy car",scraps==0 and c.recrew[tostring(car.id)]~=nil)
    for i=1,12 do R.tick(c,CLOCK+i*40000) end
    check("unloaded crew replicas retain car after retry budget",scraps==0 and attempts>=6)
    c.halted=true
    local prior=attempts
    R.tick(c,CLOCK+900000)
    check("waiting caravan does not silently start boarding departure",attempts==prior)
    c.halted=nil
    session={phase="boarding",crew={{uid="reserved-member"}}}
    R.tick(c,CLOCK+1000000)
    check("active boarding session is not destroyed by another retry",attempts==prior and A.isEmpty(c.recrew))
    session=nil
    c.crewMissing={}
    R.watch(c,CLOCK)
    R.watch(c,CLOCK+13000)
    check("unexpected session loss schedules return after grace",c.recrew[tostring(car.id)]~=nil)
    c.state,c.fightingAtMs,c.crewQuietAtMs="fighting",CLOCK,nil
    S.zombiesNear=function() return 0 end
    R.watch(c,CLOCK+21000)
    R.watch(c,CLOCK+32000)
    check("non-scripted fight ends in regroup and departure",c.state=="rendered" and resumed==1)
    c.state,c.fightingAtMs,c.crewQuietAtMs="fighting",CLOCK,nil
    S.zombiesNear=function() return 3 end
    R.watch(c,CLOCK+30000)
    check("ongoing danger does not trigger immediate reboarding",c.state=="fighting")
    R.watch(c,CLOCK+151000)
    check("prolonged fight uses bounded retreat instead of permanent abandonment",c.state=="rendered")
    c.state,c.fightingAtMs,c.crewQuietAtMs="fighting",CLOCK,nil
    c.ambush={state="armed"}
    S.zombiesNear=function() return 0 end
    R.watch(c,CLOCK+21000)
    R.watch(c,CLOCK+32000)
    check("armed future ambush cannot trap player-provoked fight forever",c.state=="rendered")
    c.ambush=nil
    local sleeping, releases, suspendedOwner = nil, 0, {bindings={}}
    S.sessionOf=function() return suspendedOwner,session,sleeping end
    S.releaseCar=function() releases=releases+1 session,sleeping=nil,nil return true end
    S.recrew=function(_,_,_,_,reserved)
        attempts=attempts+1
        return not reserved["live-suspended-passenger"],1
    end
    S.survivors=function() return {{uid="live-suspended-passenger"}} end
    c.actorUids={"dead-suspended-driver","live-suspended-passenger"}
    ACTORS[c.actorUids[1]]={uid=c.actorUids[1],lifecycle="dead"}
    ACTORS[c.actorUids[2]]={uid=c.actorUids[2],lifecycle="active"}
    session={uid=c.actorUids[1],crew={{uid=c.actorUids[1]},{uid=c.actorUids[2]}}}
    sleeping={session=session}
    c.recrew,c.crewDeadAt={},{}
    R.watch(c,CLOCK+1200000)
    check("dead suspended driver receives restore grace",A.isEmpty(c.recrew) and releases==0)
    R.watch(c,CLOCK+1213000)
    R.tick(c,CLOCK+1218000)
    check("proven dead suspended driver releases stale handoff and assigns live passenger",
        releases==1 and A.isEmpty(c.recrew))
    session={uid=c.actorUids[1],crew={{uid=c.actorUids[1]}}}
    sleeping={session=session}
    ACTORS[c.actorUids[1]].lifecycle="dormant"
    R.watch(c,CLOCK+1300000)
    R.watch(c,CLOCK+1400000)
    R.tick(c,CLOCK+1500000)
    check("dormant suspended driver never destroys legitimate handoff",releases==1 and A.isEmpty(c.recrew) and sleeping~=nil)
    ACTORS[c.actorUids[1]].lifecycle="dead"
    car.occupied=true
    R.watch(c,CLOCK+1600000)
    R.watch(c,CLOCK+1613000)
    R.tick(c,CLOCK+1618000)
    check("dead-driver recovery preserves player aboard",releases==1 and sleeping~=nil)
    car.occupied=false
    ACTORS[c.actorUids[1]].lifecycle="active"
    ACTORS[c.actorUids[2]].lifecycle="dead"
    session={uid=c.actorUids[1],riders={{uid=c.actorUids[2]}}}
    sleeping={session=session}
    suspendedOwner.bindings[car.id]={crew={{uid=c.actorUids[1],seat=0},{uid=c.actorUids[2],seat=1}}}
    c.recrew,c.crewDeadAt={},{}
    S.survivors=function() return {{uid=c.actorUids[1]}} end
    R.watch(c,CLOCK+1700000)
    check("dead suspended passenger receives the same restore grace",releases==1 and A.isEmpty(c.recrew))
    R.watch(c,CLOCK+1713000)
    R.tick(c,CLOCK+1718000)
    check("proven dead passenger unblocks live driver handoff",releases==2 and A.isEmpty(c.recrew))
    session={uid=c.actorUids[1],riders={{uid=c.actorUids[2]}}}
    sleeping={session=session}
    ACTORS[c.actorUids[2]]=nil
    R.watch(c,CLOCK+1800000)
    R.watch(c,CLOCK+1900000)
    R.tick(c,CLOCK+1905000)
    check("missing passenger record is not proof of death",releases==2 and sleeping~=nil and A.isEmpty(c.recrew))
    ACTORS[c.actorUids[2]]={uid=c.actorUids[2],lifecycle="dormant"}
    R.watch(c,CLOCK+2000000)
    R.watch(c,CLOCK+2100000)
    R.tick(c,CLOCK+2105000)
    check("unloaded dormant passenger preserves sleeping handoff",releases==2 and sleeping~=nil and A.isEmpty(c.recrew))
    ACTORS["unrelated-dead-rider"]={uid="unrelated-dead-rider",lifecycle="dead"}
    suspendedOwner.bindings[car.id].crew[3]={uid="unrelated-dead-rider",seat=2}
    R.watch(c,CLOCK+2200000)
    R.watch(c,CLOCK+2300000)
    R.tick(c,CLOCK+2305000)
    check("unowned dead binding member cannot authorize recovery",releases==2 and sleeping~=nil and A.isEmpty(c.recrew))
    ACTORS[c.actorUids[2]].lifecycle="dead"
    car.occupied=true
    R.watch(c,CLOCK+2400000)
    R.watch(c,CLOCK+2413000)
    R.tick(c,CLOCK+2418000)
    check("dead-passenger recovery preserves player aboard",releases==2 and sleeping~=nil)
    car.occupied=false
    S.sessionOf,S.recrew,S.survivors,S.zombiesNear=saved.session,saved.recrew,saved.survivors,saved.zombies
    S.releaseCar=saved.release
    A.Ledger.get,D.resume,D.abandonCar=saved.get,saved.resume,saved.abandon

    local entry={goals={{x=200,y=100}},goalIndex=1}
    local points,why=A.Convoy.legFor(entry,{vehicle=car,route={{x=200,y=100}}},false)
    check("queued destination is not a physical arrival",points==nil and why=="route_queued" and entry.goalIndex==1)
    local oldByVehicle=A.Ledger.byVehicle
    A.Ledger.byVehicle=function() return c end
    c.arrivals,c.arrivedCars=0,{}
    D.onConvoyReport(nil,"arrived",{vehicleId=car.id})
    check("far destination arrival report rejected",c.arrivals==0)
    car.x=200
    D.onConvoyReport(nil,"arrived",{vehicleId=car.id})
    D.onConvoyReport(nil,"arrived",{vehicleId=car.id})
    check("physical arrival counted once per vehicle and trip",c.arrivals==1)
    local npc=newShell("destination-driver","destination-faction")
    npc.x,npc.y,npc.vehicle=car.x,car.y,car
    SHELLS[npc.uid],car.passengers[0]=npc,npc
    ACTORS[npc.uid]={uid=npc.uid,generation=1,lifecycle="active",revision=1,memory={}}
    c.actorUids,c.arrivals,c.arrivedCars,c.goalIndex={npc.uid},0,{},1
    local oldEntry=A.Convoy.known[car.id]
    A.Convoy.known[car.id]=nil
    local boarded,reason=S.recrew(c,car.id,nil,1,{})
    check("sessionless final-goal car records arrival instead of no-route deadlock",
        not boarded and reason=="at_destination" and c.arrivals==1)
    S.recrew(c,car.id,nil,1,{})
    check("final-goal reboard retry cannot duplicate physical arrival",c.arrivals==1)
    A.Convoy.known[car.id]=oldEntry
    A.Ledger.byVehicle=oldByVehicle

    local oldRand,oldHalt,oldChance=A.rand,D.halt,A.settings.breakdownChance
    A.rand=function() return 0 end
    D.halt=function(v,seconds) v.halted=true v.testSeconds=seconds end
    A.settings.breakdownChance=100
    c.halted,c.breakdownCheckAtMs=nil,0
    local before=car.engine
    D.breakdownTick(c,CLOCK,{})
    check("random roadside stop never destroys working engine",car.engine==before and c.testSeconds==45)
    A.rand,D.halt,A.settings.breakdownChance=oldRand,oldHalt,oldChance

    local oldList,oldClock,oldWeather=A.Ledger.list,D.clock,A.settings.weatherEffects
    A.settings.weatherEffects=true
    A.Ledger.list=function() return {c} end
    D.clock=function() return 1,23 end
    c.halted,c.baseSpeedKmh,c.speedKmh=nil,nil,40
    D.weatherCheckAtMs=0 D.weatherTick(CLOCK,{})
    local once=c.speedKmh
    D.weatherCheckAtMs=0 D.weatherTick(CLOCK+60000,{})
    check("night penalty does not compound every minute",c.speedKmh==once and c.baseSpeedKmh==40)
    A.Ledger.list,D.clock,A.settings.weatherEffects=oldList,oldClock,oldWeather
end
