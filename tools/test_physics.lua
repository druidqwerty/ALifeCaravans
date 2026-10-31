return function(check)
    local A = ALifeCaravans
    local saved = {client=isClient,server=isServer,player=getSpecificPlayer,bridge=ALCNativeReleaseBrake,
        known=A.Convoy.known,session=A.Convoy.sessionFor,members=ProjectALife.DrivingDemo.members,
        acquire=ALCNativeAcquireSP,release=ALCNativeReleaseSP,spVehicles=A.Physics.spVehicles,
        drivingRiders=ProjectALife.DrivingRiders}
    local entry, calls = {}, 0
    local v = {id=991,force=80,localPhysics=true,speed=0,engine=true,owner=37}
    local driver = {data={ProjectALifeUID="brake-driver",ProjectALifeGeneration=1}}
    local rider = {data={ProjectALifeUID="brake-rider",ProjectALifeGeneration=1}}
    local function body(n)
        function n:getVehicle() return self.vehicle end
        function n:isDead() return self.dead==true end
        function n:getModData() return self.data end
        n.vehicle=v
    end
    body(driver); body(rider)
    v.seats={[0]=driver,[1]=rider}
    function v:getId() return self.id end
    function v:getBrakingForce() return self.force end
    function v:setBrakingForce(f) self.force=f end
    function v:isLocalPhysicSim() return self.localPhysics end
    function v:getCurrentSpeedKmHour() return self.speed end
    function v:isEngineRunning() return self.engine end
    function v:getDriver() return self.seats[0] end
    function v:getCharacter(i) return self.seats[i] end
    function v:getMaxPassengers() return 2 end
    function v:getNetPlayerId() return self.owner end
    function v:getController() return self end
    local s={vehicle=v,npc=driver,phase="driving",entryComplete=true,boarded=true,uid="brake-driver",generation=1}
    local m={npc=rider,seat=1,boarded=true,uid="brake-rider",generation=1}
    A.Convoy.known={[991]=entry}
    A.Convoy.sessionFor=function() return s end
    ProjectALife.DrivingDemo.members=function() return {s,m} end
    isClient=function() return true end
    isServer=function() return false end
    getSpecificPlayer=function() return {getOnlineID=function() return 37 end} end
    ALCNativeReleaseBrake=function(vehicle)
        assert(vehicle==v and v.force==0)
        calls=calls+1
        return true
    end
    local function attempt() s.alcBrakeReleased=nil return A.Physics.prepare(s,entry) end
    check("verified local NPC drive clears native park brake", attempt() and calls==1 and v.force==80)
    check("same drive does not repeatedly alter controller", not A.Physics.prepare(s,entry) and calls==1)
    entry.halted=true; check("halt never releases brakes", not attempt()); entry.halted=nil
    s.braking=true; check("braking session untouched", not attempt()); s.braking=nil
    s.entryComplete=false; check("incomplete boarding untouched", not attempt()); s.entryComplete=true
    m.boarded=false; check("unboarded passenger blocks release", not attempt()); m.boarded=true
    rider.data.ProjectALifeGeneration=2
    check("stale passenger generation blocks release", not attempt())
    rider.data.ProjectALifeGeneration=1
    rider.vehicle=nil; check("passenger must really be seated", not attempt()); rider.vehicle=v
    v.localPhysics=false; check("remote physics never modified", not attempt()); v.localPhysics=true
    v.owner=99; check("different physics owner untouched", not attempt()); v.owner=37
    v.speed=4; check("moving vehicle never reset", not attempt()); v.speed=0
    v.engine=false; check("stopped engine untouched", not attempt()); v.engine=true
    v.seats[1]={__class="IsoPlayer"}; check("player passenger prevents reset", not attempt()); v.seats[1]=rider
    driver.__class="IsoPlayer"; check("player driver never controlled", not attempt()); driver.__class=nil
    A.Convoy.known={}; check("non-caravan vehicle untouched", not attempt()); A.Convoy.known={[991]=entry}
    A.Convoy.sessionFor=function() return {} end
    check("stale driving session untouched", not attempt()); A.Convoy.sessionFor=function() return s end
    isServer=function() return true end
    check("dedicated server never changes local physics", not attempt()); isServer=function() return false end
    local bridge=ALCNativeReleaseBrake; ALCNativeReleaseBrake=nil
    check("missing bridge does not fabricate success", not attempt()); ALCNativeReleaseBrake=bridge
    s.phase="seated"; s.alcBrakeReleased=true
    check("parked session rearms next drive without touching physics", not A.Physics.prepare(s,entry) and not s.alcBrakeReleased)
    s.phase="driving"
    ALCNativeReleaseBrake=function() error("test bridge error") end
    check("bridge failure restores brake specification", not attempt() and v.force==80 and s.alcBrakeError)
    ALCNativeReleaseBrake=bridge
    check("failed bridge not retried every tick", not attempt() and calls==1)
    -- Model SP's real engine discrepancy: Server/-1 means isLocalPhysicSim=false
    -- until the scoped adapter succeeds. Entry must be enabled before driving.
    local acquired, released, driveRequested = 0, 0, nil
    A.Physics.spVehicles={}
    entry.caravanId="physics-test"
    v.data={[A.MODDATA_ID]=entry.caravanId}
    function v:getModData() return self.data end
    function v:isSeatInstalled(seat) return seat>=0 and seat<2 end
    ALCNativeAcquireSP=function(car,npc,caravanId,uid,generation,allowed,driving)
        assert(car==v and npc==driver and caravanId==entry.caravanId and uid==s.uid and generation==s.generation)
        acquired=acquired+1
        driveRequested=driving
        v.localPhysics=true
        return true
    end
    ALCNativeReleaseSP=function(car)
        assert(car==v)
        released=released+1
        v.localPhysics=false
        return true
    end
    check("SP adapter cannot grant MP authority", not A.Physics.ensureSP(s,entry) and acquired==0)
    isClient=function() return false end
    isServer=function() return true end
    check("SP adapter cannot grant dedicated-server authority", not A.Physics.ensureSP(s,entry) and acquired==0)
    isServer=function() return false end
    s.phase,s.entryComplete,s.boarded,s.alcBrakeError="approach",false,false,nil
    m.boarded=false
    driver.vehicle,rider.vehicle=nil,nil
    v.seats,v.localPhysics={},false
    check("SP approaching crew gains local simulation before boarding", not A.Physics.prepare(s,entry)
        and acquired==1 and v.localPhysics and A.Physics.spVehicles[v]==s)
    check("SP approach does not wake a parked physical body", driveRequested==false)
    driver.data.ProjectALifeUID="wrong"
    check("SP adapter rejects stale actor UID and releases lease", not A.Physics.ensureSP(s,entry)
        and released==1 and not A.Physics.spVehicles[v])
    driver.data.ProjectALifeUID=s.uid
    rider.data.ProjectALifeGeneration=2
    check("SP adapter checks every passenger generation", not A.Physics.ensureSP(s,entry) and acquired==1)
    rider.data.ProjectALifeGeneration=1
    m.seat=0
    check("SP adapter refuses duplicate seat assignments", not A.Physics.ensureSP(s,entry)); m.seat=1
    m.npc=driver
    check("SP adapter refuses duplicate body assignments", not A.Physics.ensureSP(s,entry)); m.npc=rider
    m.seat=4
    check("SP adapter refuses out-of-range seats", not A.Physics.ensureSP(s,entry)); m.seat=1
    v.seats[0]={}
    check("SP adapter refuses a foreign driver", not A.Physics.ensureSP(s,entry)); v.seats[0]=nil
    rider.vehicle={}
    check("SP adapter never steals a rider from another car", not A.Physics.ensureSP(s,entry)); rider.vehicle=nil
    m.boarded=true
    check("SP adapter requires real seats for claimed boarded members", not A.Physics.ensureSP(s,entry)); m.boarded=false
    v.data[A.MODDATA_ID]="foreign"
    check("SP adapter requires authoritative caravan tag", not A.Physics.ensureSP(s,entry)); v.data[A.MODDATA_ID]=entry.caravanId
    A.Convoy.sessionFor=function() return {} end
    check("SP adapter rejects a stale session", not A.Physics.ensureSP(s,entry)); A.Convoy.sessionFor=function() return s end
    driver.dead=true
    check("SP adapter rejects a dead driver", not A.Physics.ensureSP(s,entry)); driver.dead=nil
    v.seats[1]={__class="IsoPlayer"}
    check("SP adapter does not control player-occupied vehicles", not A.Physics.ensureSP(s,entry)); v.seats[1]=nil
    ProjectALife.DrivingDemo.members=function() return {} end
    check("SP adapter requires nonempty crew", not A.Physics.ensureSP(s,entry))
    ProjectALife.DrivingDemo.members=function() return {s,m} end
    local acquire=ALCNativeAcquireSP
    ALCNativeAcquireSP=nil
    check("SP adapter missing native bridge leaves physics alone", not A.Physics.ensureSP(s,entry))
    ALCNativeAcquireSP=acquire
    check("valid SP session can reacquire after corrected identity", A.Physics.ensureSP(s,entry) and acquired==2)
    A.Convoy.known={}
    A.Physics.sweepSP()
    check("known-car removal releases SP lease", not A.Physics.spVehicles[v] and not v.localPhysics)
    A.Convoy.known={[991]=entry}
    A.Physics.ensureSP(s,entry)
    A.Convoy.sessionFor=function() return {} end
    A.Physics.sweepSP()
    check("session replacement releases SP lease", not A.Physics.spVehicles[v] and not v.localPhysics)
    A.Convoy.sessionFor=function() return s end
    local passenger={__class="IsoPlayer",getVehicle=function() return v end}
    function v:getMaxPassengers() return 3 end
    function v:isSeatInstalled(seat) return seat>=0 and seat<3 end
    v.seats[2]=passenger
    ProjectALife.DrivingRiders={allowed=function() return false end}
    check("uninvited passenger blocks SP adapter", not A.Physics.ensureSP(s,entry))
    ProjectALife.DrivingRiders.allowed=function() return true end
    check("invited unreserved player passenger permits SP NPC drive", A.Physics.ensureSP(s,entry))
    A.Physics.sweepSP()
    check("SP sweep preserves lease with approved hitchhiker", A.Physics.spVehicles[v]==s)
    v.seats[0]=passenger
    check("rider permission never allows player driver control", not A.Physics.ensureSP(s,entry)); v.seats[0]=nil
    s.phase,s.entryComplete,s.boarded="driving",true,true
    m.boarded=true
    driver.vehicle,rider.vehicle=v,v
    v.seats[0],v.seats[1]=driver,rider
    local riderBrake=false
    ALCNativeReleaseBrake=function(car,allowed) riderBrake=car==v and allowed==true return riderBrake end
    check("invited hitchhiker permits parked-brake release", attempt() and riderBrake and v.force==80)
    check("SP real seated driving crew requests vanilla wake", driveRequested==true)
    entry.halted=true; A.Physics.ensureSP(s,entry)
    check("SP halted crew does not wake physics", driveRequested==false); entry.halted=nil
    s.braking=true; A.Physics.ensureSP(s,entry)
    check("SP braking crew does not wake physics", driveRequested==false); s.braking=nil
    s.exitRequested=true; A.Physics.ensureSP(s,entry)
    check("SP exiting crew does not wake physics", driveRequested==false); s.exitRequested=nil
    m.boarded=false; A.Physics.ensureSP(s,entry)
    check("SP incomplete crew does not wake physics", driveRequested==false); m.boarded=true
    v.seats[0]=passenger
    check("invited hitchhiker cannot take NPC driver seat", not attempt()); v.seats[0]=driver
    v.seats[2]=nil
    ALCNativeReleaseBrake=bridge
    ProjectALife.DrivingRiders=saved.drivingRiders
    ALCNativeAcquireSP=function() error("native SP unavailable") end
    check("native SP error fails closed", not A.Physics.ensureSP(s,entry) and s.alcSPError)
    ALCNativeAcquireSP=acquire
    local before=acquired
    check("native SP exception is latched per session", not A.Physics.ensureSP(s,entry) and acquired==before)
    ALCNativeAcquireSP,ALCNativeReleaseSP=saved.acquire,saved.release
    A.Physics.spVehicles=saved.spVehicles
    isClient,isServer,getSpecificPlayer,ALCNativeReleaseBrake=saved.client,saved.server,saved.player,saved.bridge
    A.Convoy.known,A.Convoy.sessionFor=saved.known,saved.session
    ProjectALife.DrivingDemo.members=saved.members
end
