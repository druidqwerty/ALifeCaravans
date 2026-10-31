return function(check)
    local A = ALifeCaravans
    local saved = {client=isClient,server=isServer,player=getSpecificPlayer,bridge=ALCNativeReleaseBrake,
        known=A.Convoy.known,session=A.Convoy.sessionFor,members=ProjectALife.DrivingDemo.members}
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
    isClient,isServer,getSpecificPlayer,ALCNativeReleaseBrake=saved.client,saved.server,saved.player,saved.bridge
    A.Convoy.known,A.Convoy.sessionFor=saved.known,saved.session
    ProjectALife.DrivingDemo.members=saved.members
end
