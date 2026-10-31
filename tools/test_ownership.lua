-- Lifecycle/ownership guards: transient vehicle IDs never authorize mutation.
return function(check)
    local A,P=ALifeCaravans,ProjectALife
    local S,D,R=A.Spawn,A.Director,A.Crew
    local owner=P.VehicleArrivals.owner()
    local foreign=newVehicle("Base.CarNormal",130,100)
    A.tagVehicle(foreign,"foreign-convoy",1)
    local foreignSession={vehicle=foreign,uid="foreign-driver"}
    owner.sessions[foreign.id]=foreignSession
    owner.bindings[foreign.id]={crew={{uid="foreign-driver"}}}
    local c={id="ownership-regression",vehicleIds={foreign.id},actorUids={},abandoned={foreign.id},
        state="rendered",x=130,y=100,goals={{x=130,y=100}},trip=1,arrivals=0}
    local before=#RELEASED
    check("foreign vehicle ID cannot release other convoy bookkeeping",not S.releaseCar(foreign.id,c.id)
        and owner.sessions[foreign.id]==foreignSession and #RELEASED==before)
    local ok,reason=S.recrew(c,foreign.id,nil,1,{})
    check("foreign tagged car cannot receive a replacement crew",not ok and reason=="foreign_car")
    check("foreign tagged car cannot be abandoned",not S.abandon(c,foreign.id) and c.vehicleIds[1]==foreign.id)
    S.teardownVehicles({foreign.id},c.id)
    check("failed-spawn cleanup cannot remove foreign tagged car",not foreign.removed and owner.sessions[foreign.id]==foreignSession)
    D.onConvoyReport(nil,"arrived",{vehicleId=foreign.id})
    local positions,missing=D.vehiclePositions(c)
    check("stale vehicle ID is missing, not another convoy position",#positions==0 and missing==1)
    foreign.occupied=true
    check("foreign passenger cannot keep stale caravan alive",not D.ridersAboard(c))
    S.teardown(c,"test_stale_id")
    check("teardown skips foreign session and abandoned-ID bookkeeping",not foreign.removed
        and owner.sessions[foreign.id]==foreignSession and owner.bindings[foreign.id]~=nil and #RELEASED==before)
    foreign.occupied=false

    local own=newVehicle("Base.CarNormal",140,100)
    c=A.Ledger.create({state="rendering",x=140,y=100,vehicleIds={own.id},actorUids={},abandoned={},
        renderingAtMs=CLOCK-121000,units=1,route={"townA","townB"},goals={{x=200,y=100}}})
    A.tagVehicle(own,c.id,1)
    own.occupied=true
    D.step(D.graph(),c,CLOCK,0,{{player=PLAYER,key="ivan",x=140,y=100}})
    check("occupied render timeout keeps real vehicle managed",c.state=="stranded" and c.vehicleIds[1]==own.id and not own.removed)
    D.step(D.graph(),c,CLOCK+1800001,0,{})
    check("stranded timeout preserves passenger vehicle and ledger",A.Ledger.get(c.id)==c and c.vehicleIds[1]==own.id and not own.removed)
    c.state="rendering"
    D.onSpawnOutcome(c.id,{ok=false,reason="test_failure"},1)
    check("occupied first-unit failure cannot resume offline spawning",c.state=="stranded" and c.vehicleIds[1]==own.id and not own.removed)
    c.state="rendering"
    A.tagVehicle(own,c.id,3)
    D.onSpawnOutcome(c.id,{ok=false,reason="test_failure"},2)
    check("occupied second-unit failure retains its vehicle membership",c.state=="rendered" and c.vehicleIds[1]==own.id and not own.removed)
    own.occupied=false

    local oldSession,oldSurvivors,oldRecrew=S.sessionOf,S.survivors,S.recrew
    local oldMembers=P.DrivingDemo.members
    local second=newVehicle("Base.CarNormal",145,100)
    A.tagVehicle(second,c.id,2)
    c.vehicleIds={own.id,second.id}
    c.recrew={[tostring(second.id)]={vehicleId=second.id,dueMs=CLOCK}}
    -- Exact upstream session shape, not a fabricated .crew field.
    local session={uid="boarding-driver",riders={{uid="boarding-passenger"}},phase="approach",vehicle=own}
    local calledMembers,reservedDriver,reservedPassenger=0,false,false
    P.DrivingDemo.members=function(s)
        calledMembers=calledMembers+1
        local rows={s}
        for _,rider in ipairs(s.riders or {}) do rows[#rows+1]=rider end
        return rows
    end
    S.sessionOf=function(id) return owner,id==own.id and session or nil end
    S.survivors=function() return {{uid="boarding-passenger"}} end
    S.recrew=function(_,_,_,_,reserved)
        reservedDriver,reservedPassenger=reserved["boarding-driver"],reserved["boarding-passenger"]
        return false,"waiting"
    end
    R.tick(c,CLOCK)
    check("real session driver and riders reserved through DrivingDemo.members",calledMembers>0 and reservedDriver and reservedPassenger)
    S.sessionOf,S.survivors,S.recrew=oldSession,oldSurvivors,oldRecrew
    P.DrivingDemo.members=oldMembers

    local oldList,oldMerge,oldMax=A.Ledger.list,A.settings.mergeCaravans,A.settings.maxVehicles
    local bcar=newVehicle("Base.CarNormal",150,100)
    local b=A.Ledger.create({state="rendered",x=150,y=100,factionId="merge-faction",vehicleIds={bcar.id},
        actorUids={},crew={},vehicles={"Base.CarNormal"},stock={},abandoned={}})
    A.tagVehicle(bcar,b.id,1)
    c.factionId,c.halted,c.recrew,c.ambush="merge-faction",nil,{},nil
    c.crew,c.vehicles,c.stock,c.trip={},{"Base.CarNormal","Base.CarNormal"},{},1
    c.arrivals,c.arrivedCars=1,{[tostring(own.id)]=1}
    A.Ledger.list=function() return {c,b} end
    A.settings.mergeCaravans,A.settings.maxVehicles=true,4
    D.mergeCheckAtMs=0
    D.mergeTick(CLOCK,{})
    check("merge preserves receiver already-arrived report",#c.vehicleIds==3 and c.arrivals==1 and c.arrivedCars[tostring(own.id)]==1)
    check("merge retires donor without deleting transferred vehicle",A.Ledger.get(b.id)==nil and not bcar.removed and A.vehicleTag(bcar)==c.id)
    c.goals,c.goalIndex={},1
    for index=1,61 do c.goals[index]={x=100+index*100,y=100} end
    local view=D.knownTable()[own.id]
    check("long route publishes all bounded generated goals",view and #view.goals==61 and view.goals[61].x==c.goals[61].x)
    view.goalIndex=40
    local nextGoal=A.Convoy.goalFor(view,c.goals[40].x,c.goals[40].y)
    check("former40-goal cutoff advances to real next goal",nextGoal==view.goals[41] and view.goalIndex==41)
    view.goalIndex=61
    local finished=A.Convoy.goalFor(view,c.goals[61].x,c.goals[61].y)
    check("long route arrival requires final published goal",finished==nil and view.goalIndex==62)
    for index=62,100 do c.goals[index]={x=100+index*100,y=100} end
    view=D.knownTable()[own.id]
    check("oversized stored route publication remains bounded",view and #view.goals==61)
    A.Ledger.list,A.settings.mergeCaravans,A.settings.maxVehicles=oldList,oldMerge,oldMax
end
