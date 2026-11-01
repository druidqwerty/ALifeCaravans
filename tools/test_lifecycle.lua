return function(check, newVehicle)
    local A = ALifeCaravans
    local R, D, L = A.Lifecycle, A.Director, A.Ledger
    local saved = {store=L.store, pending=L.reloadPending, release=A.Spawn.releaseCar,
        known=A.Convoy.known, stock=A.Client.stock, window=A.Client.window,
        server=isServer, client=isClient}
    L.store = A.copy(L.open())
    L.store.caravans, L.reloadPending = {}, {}
    local car = newVehicle("Base.CarNormal",100,100)
    local c = L.create({state="rendered",vehicleIds={car.id},actorUids={"life-a","life-b"},
        x=100,y=100,halted=true,stock={{item="Base.Bandage",count=1}},goals={}})
    A.tagVehicle(car,c.id,1)
    ACTORS["life-a"]={uid="life-a",lifecycle="dead"}
    ACTORS["life-b"]={uid="life-b",lifecycle="active"}
    check("one surviving crew member preserves active caravan",not R.allDead(c) and R.visible(c))
    ACTORS["life-b"].lifecycle="dormant"
    check("dormant crew is not dead",not R.allDead(c))
    ACTORS["life-b"]=nil
    check("missing authoritative crew record is not death",not R.allDead(c))
    ACTORS["life-b"]={uid="life-b",lifecycle="dead"}
    check("all authoritative deaths hide interaction before next director tick",not R.visible(c))
    check("known and map omit dead parked caravan immediately",D.knownTable()[car.id]==nil and #D.markerTable()==0)
    check("forged interaction with dead caravan rejected",A.Interact.caravanOf({vehicleId=car.id})==nil)
    local releases=0
    A.Spawn.releaseCar=function(id,tag)
        releases=releases+1
        return id==car.id and tag==c.id
    end
    car.occupied=true
    check("dead parked crew cleanup executes even with a human aboard",R.tick(c,CLOCK))
    check("occupied defeat hidden but retained safely",c.state=="defeated" and L.get(c.id)==c and releases==0)
    check("occupied wreck does not consume active caravan capacity",L.count()==0)
    check("player occupied car and persistent ownership remain untouched",A.vehicleTag(car)==c.id and getVehicleById(car.id)==car)
    car.occupied=false
    R.tick(c,CLOCK+2100)
    check("cleanup after player exit removes only active bookkeeping",L.get(c.id)==nil and releases==1)
    check("loot vehicle survives defeat and loses caravan tag",getVehicleById(car.id)==car and A.vehicleTag(car)==nil)
    local previousId=c.id
    c=L.create({state="fighting",vehicleIds={car.id},actorUids={"life-a"},x=100,y=100})
    A.tagVehicle(car,"foreign-caravan",1)
    R.tick(c,CLOCK+4000)
    check("recycled vehicle ID cannot release another caravan",releases==1 and A.vehicleTag(car)=="foreign-caravan")
    check("combat death also retires terminal ledger without deletion",L.get(c.id)==nil and getVehicleById(car.id)==car)
    c=L.create({state="rendered",vehicleIds={car.id},actorUids={"life-a"},x=100,y=100})
    A.tagVehicle(car,c.id,1)
    isServer=function() return false end
    isClient=function() return true end
    check("client cannot authoritatively retire dead caravan",not R.tick(c,CLOCK+5000) and c.state=="rendered")
    isServer,isClient=saved.server,saved.client
    check("legacy stranded marker is hidden",not R.visible({state="stranded",actorUids={}}))
    check("offline never-spawned crew remains valid",R.visible({state="offline",actorUids={}}))
    local closed=0
    A.Client.stock={[car.id]={},[999999]={}}
    A.Client.window={vehicleId=car.id,onClose=function() closed=closed+1 A.Client.window=nil end}
    A.Convoy.setKnown({})
    check("full state removal closes stale trade window",closed==1)
    check("full state removal drops stale stock without inventory mutation",next(A.Client.stock)==nil)
    local oldOpen,reopened=A.Client.openTrade,0
    A.Client.openTrade=function() reopened=reopened+1 end
    A.Client.receive(A.MODULE,"stock",{vehicleId=car.id,rows={}})
    check("late stock response cannot reopen a dead caravan",reopened==0 and A.Client.stock[car.id]==nil)
    check("late cargo response cannot reopen a dead contact panel",not A.Details.receive("cargoView",{vehicleId=car.id,cargo={}}))
    A.Client.openTrade=oldOpen
    local _,rows=A.Details.rows("cargoView",{cargo={{name="Bandage",type="Base.Bandage",count=7}}})
    check("cargo detail preserves actual aggregate quantity and item type",rows[1].value=="x7" and rows[1].type=="Base.Bandage")
    _,rows=A.Details.rows("cargoView",{cargo={}})
    check("empty physical cargo has explicit visible feedback",#rows==1 and type(rows[1].label)=="string")
    c=L.create({state="rendered",vehicleIds={},actorUids={"life-a","life-b"}})
    ACTORS["life-b"].lifecycle="active"
    check("surviving second NPC becomes interaction leader",A.Interact.leaderActor(c)==ACTORS["life-b"])
    L.store,L.reloadPending=saved.store,saved.pending
    A.Spawn.releaseCar=saved.release
    A.Convoy.known=saved.known
    A.Client.stock,A.Client.window=saved.stock,saved.window
    ACTORS["life-a"],ACTORS["life-b"]=nil,nil
    A.tagVehicle(car,nil,nil)
end
