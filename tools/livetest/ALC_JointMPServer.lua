-- TEST ONLY: run after the ordinary SOS/audit, two actual localhost clients.
assert(isServer(),"MP server only")
local A,P=ALifeCaravans,ProjectALife
local T={phase="wait",at=getTimestampMs(),ready={},review={},cleared={},exited={},samples={},zombies={}}
ALCJointServer=T
local function log(s) T.samples[#T.samples+1]=s print("[ALC_JointMP] "..s) end
local function finish(ok,why)
    T.done,T.ok=true,ok
    log("RESULT "..(ok and "PASS " or "FAIL ")..why)
    local w=getFileWriter("ALC_JointMP_result.txt",true,false)
    w:writeln((ok and "PASS " or "FAIL ")..why)
    for _,s in ipairs(T.samples) do w:writeln(s) end
    w:close()
end
local function send(command)
    for name,player in pairs(T.peers) do
        sendServerCommand(player,"ALCJoint",command,{id=T.id,cid=T.c.id,primary=name=="admin"})
    end
end
local function step(s,now) T.phase,T.at=s,now log("STAGE "..s) end
local function both(rows) return rows.admin and rows.observer end
Events.OnClientCommand.Add(function(module,command,player,args)
    if module~="ALCJoint" or T.done then return end
    local name=player:getUsername()
    if command=="failure" then finish(false,name..": "..tostring(args.why))
    elseif T[command] then T[command][name]=true; log(command.." "..name) end
end)
Events.OnTick.Add(function()
    if T.done then return end
    local now=getTimestampMs()
    if now-(T.tickAt or 0)<250 then return end
    T.tickAt=now
    local ok,why=pcall(function()
        if T.phase=="wait" then
            if not (ALRLive.audit and ALRLive.audit.ok) then return end
            T.peers=ALRLive.peers
            assert(T.peers.admin and T.peers.observer,"two real players required")
            T.c=ALRLive.audit.c; T.id=T.c.vehicleIds[1]; T.car=getVehicleById(T.id)
            assert(T.car and T.car:getDriver(),"audited original car missing")
            T.c.goals={{x=10588,y=10680}}; T.c.goalIndex=1; T.c.trip=(T.c.trip or 0)+1
            T.c.stock={{item="Base.Bandage",name=A.Trade.name("Base.Bandage"),value=10,count=4}}
            A.Director.halt(T.c,180,"wait"); A.Director.publish(true)
            do
                -- Deliberately test the partial-death binding, on any vehicle:
                -- original driver survives and the player takes a freed seat.
                local passenger=T.car:getCharacter(1)
                assert(passenger and instanceof(passenger,"IsoZombie"),"no fixture passenger")
                T.partialUid=passenger:getModData().ProjectALifeUID
                passenger:Kill(nil)
                step("partial",now)
            end
        elseif T.phase=="partial" then
            local actor=P.ActorRegistry.read(T.partialUid)
            if not actor or actor.lifecycle~="dead" or T.car:getCharacter(1) then return end
            assert(A.Lifecycle.visible(T.c),"partial crew death hid surviving driver")
            log("PARTIAL DEATH PASS original driver survives; passenger seat freed naturally")
            A.Director.halt(T.c,180,"wait"); A.Director.publish(true)
            send("setup"); step("clients",now)
        elseif T.phase=="clients" then
            if not both(T.ready) or math.abs(T.car:getCurrentSpeedKmHour())>1 then return end
            assert(T.peers.admin:getVehicle()==T.car,"server did not receive real passenger")
            local survivors=A.Spawn.survivors(T.c,T.car:getX(),T.car:getY(),80)
            assert(#survivors>=1,"no surviving crew before pressure")
            local target=T.car:getDriver() or survivors[1].npc
            T.x,T.y=T.car:getX(),T.car:getY()
            for _,off in ipairs({{2,0},{-2,1},{0,3}}) do
                local list=addZombiesInOutfit(math.floor(T.x+off[1]),math.floor(T.y+off[2]),0,1,nil,50)
                assert(list and list:size()>0,"threat spawn failed")
                local z=list:get(0); z:setTarget(target); z:pathToCharacter(target)
                T.zombies[#T.zombies+1]=z
            end
            step("escape",now)
        elseif T.phase=="escape" then
            if T.c.threatState=="escape" and not T.c.halted then T.responded=true end
            local distance=A.dist(T.x,T.y,T.car:getX(),T.car:getY())
            if distance>=8 and T.responded then
                log("ESCAPE PASS distance="..distance.." passengerSeat="..T.car:getSeat(T.peers.admin))
                for _,z in ipairs(T.zombies) do if not z:isDead() then z:Kill(nil) end end
                A.Director.halt(T.c,180,"wait")
                step("stop",now)
            end
        elseif T.phase=="stop" then
            if not T.car:isStopped() or now-T.at<3000 then return end
            send("reopen"); step("review",now)
        elseif T.phase=="review" then
            if not both(T.review) or now-T.at<20000 then return end
            local crew=A.Spawn.survivors(T.c,T.car:getX(),T.car:getY(),80)
            assert(#crew>=1,"crew died before deliberate final case")
            for _,row in ipairs(crew) do row.npc:Kill(nil) end
            step("deaths",now)
        elseif T.phase=="deaths" then
            if not A.Lifecycle.allDead(T.c) or T.c.state~="defeated" then return end
            assert(T.peers.admin:getVehicle()==T.car,"occupied player detached")
            assert(A.Ledger.get(T.c.id)==T.c and A.vehicleTag(T.car)==T.c.id,"occupied bookkeeping released early")
            assert(A.Interact.caravanOf({vehicleId=T.id})==nil,"defeated command accepted")
            send("dead"); step("replication",now)
        elseif T.phase=="replication" then
            if not both(T.cleared) then return end
            log("BOTH CLIENTS PASS markers/menus/windows cleared; actual passenger protected")
            send("exit"); step("exit",now)
        elseif T.phase=="exit" then
            if not both(T.exited) or T.peers.admin:getVehicle() or A.Ledger.get(T.c.id) then return end
            assert(getVehicleById(T.id)==T.car and A.vehicleTag(T.car)==nil,"loot car lost/tag retained")
            send("finish")
            finish(true,"two-client zombie departure, real passenger, replicated dead-crew cleanup, vanilla exit and original loot vehicle")
        end
        assert(now-T.at<150000,"server timeout "..T.phase)
    end)
    if not ok then finish(false,tostring(why)) end
end)
log("observer installed; waiting for ordinary audit")
