-- TEST ONLY, SP. Inject after ordinary SOS/trade/reboarding audit.
assert(not isClient() and not isServer(),"SP probe only")
require "TimedActions/ISTimedActionQueue"
require "TimedActions/ISWalkToTimedAction"
local A,P=ALifeCaravans,ProjectALife
local player=getSpecificPlayer(0)
assert(ALRLive.audit and ALRLive.audit.ok,"ordinary audit must pass first")
assert(not ALRLive.threatLife,"probe already started")
local T={phase="park",at=getTimestampMs(),samples={},zombies={}}
ALRLive.threatLife=T
T.c=ALRLive.audit.c
T.id=T.c.vehicleIds[1]
T.car=getVehicleById(T.id)
assert(T.car and #T.c.actorUids>=2,"need original car with two crew")
local function log(s) print("[ALC_ThreatLife] "..s) T.samples[#T.samples+1]=s end
local function finish(ok,reason)
    T.done=true
    log("RESULT "..(ok and "PASS " or "FAIL ")..reason)
    local w=getFileWriter("ALC_ThreatLife_result.txt",true,false)
    for _,s in ipairs(T.samples) do w:writeln(s) end
    w:close()
end
local function step(name,now) T.phase,T.at=name,now log("STAGE "..name) end
local function visible()
    if A.Convoy.entry(T.id)==nil then return false end
    for _,m in ipairs(A.Director.markerTable()) do if m.id==T.c.id then return true end end
    return false
end
local function follow()
    if A.dist(player:getX(),player:getY(),T.car:getX(),T.car:getY())<=15 then return true end
    if #ISTimedActionQueue.getTimedActionQueue(player).queue==0 then
        local sq=getCell():getGridSquare(math.floor(T.car:getX()+6),math.floor(T.car:getY()+6),0)
        assert(sq,"test observer destination is unloaded")
        ISTimedActionQueue.add(ISWalkToTimedAction:new(player,sq))
    end
    return false
end
local function removeAttackers()
    for _,body in ipairs(T.zombies) do
        if not body:isDead() and not body:getModData().ProjectALifeUID then body:Kill(nil) end
    end
    T.zombies={}
end
T.c.goals={{x=10588,y=10680}}
T.c.goalIndex,T.c.arrivals,T.c.trip=1,0,(T.c.trip or 0)+1
T.c.ambush=nil
SandboxVars.ALifeCaravans.LivingWorld=true
A.refreshSettings()
A.Director.halt(T.c,120,"wait")

Events.OnTick.Add(function()
    if T.done then return end
    local now=getTimestampMs()
    if now-(T.tickAt or 0)<200 then return end
    T.tickAt=now
    local ok,err=pcall(function()
        assert(getVehicleById(T.id)==T.car,"original car deleted or replaced")
        if T.phase~="escape" and not follow() then
            assert(now-T.at<90000,"test observer walking timeout")
            return
        end
        if T.phase=="park" then
            if math.abs(T.car:getCurrentSpeedKmHour())>1 or now-T.at<3000 then return end
            assert(T.car:getDriver(),"no seated driver before pressure")
            T.x,T.y=T.car:getX(),T.car:getY()
            for _,off in ipairs({{2,0},{-2,1},{0,3}}) do
                local list=addZombiesInOutfit(math.floor(T.x+off[1]),math.floor(T.y+off[2]),0,1,nil,50)
                assert(list and list:size()>0,"no real threat spawned")
                local z=list:get(0)
                z:setTarget(T.car:getDriver())
                z:pathToCharacter(T.car:getDriver())
                T.zombies[#T.zombies+1]=z
            end
            step("escape",now)
        elseif T.phase=="escape" then
            if T.c.threatState=="escape" and not T.c.halted then T.responded=true end
            local distance=A.dist(T.x,T.y,T.car:getX(),T.car:getY())
            if now-(T.sampleAt or 0)>2000 then
                T.sampleAt=now
                log("escape distance="..distance.." halted="..tostring(T.c.halted).." driver="..tostring(T.car:getDriver()~=nil))
            end
            if distance>=8 and T.responded then
                log("ESCAPE PASS real movement="..distance.." elapsedMs="..(now-T.at))
                removeAttackers()
                A.Director.halt(T.c,120,"wait")
                step("partial",now)
            elseif now-T.at>90000 then error("escape timeout; responded="..tostring(T.responded)) end
        elseif T.phase=="partial" then
            if math.abs(T.car:getCurrentSpeedKmHour())>1 or now-T.at<3000 then return end
            local crew=A.Spawn.survivors(T.c,T.car:getX(),T.car:getY(),80)
            assert(#crew>=2,"crew lost before controlled death")
            T.killedUid=crew[1].uid
            crew[1].npc:Kill(nil)
            step("one_alive",now)
        elseif T.phase=="one_alive" then
            local actor=P.ActorRegistry.read(T.killedUid)
            if not actor or actor.lifecycle~="dead" then
                assert(now-T.at<10000,"first death not recorded") return
            end
            assert(visible(),"surviving crew incorrectly removed from map/menu")
            if now-T.at<3000 then return end
            log("PARTIAL DEATH PASS original survivor remains visible")
            -- Open both real owned windows before the last crew death.
            A.Style.openContact(T.id,0)
            A.Interact.command(player,"caravan_status",{vehicleId=T.id})
            assert(A.Client.contact and A.Client.contact.detail,"real status view did not open")
            assert(A.Client.contact.detailList.items[4].item.value=="1","status did not count surviving crew")
            A.Interact.command(player,"inspect_cargo",{vehicleId=T.id})
            assert(#A.Client.contact.detailList.items>=1,"cargo panel has no content or empty feedback")
            A.Client.contact:back()
            -- The preceding audit bought the last item; restock this test trader.
            T.c.stock={{item="Base.Bandage",name=A.Trade.name("Base.Bandage"),value=10,count=4}}
            A.Director.publish(true)
            A.Interact.command(player,"trade",{vehicleId=T.id})
            T.hadContact=A.Client.contact~=nil
            T.hadTrade=A.Client.window~=nil
            step("ui_review",now)
        elseif T.phase=="ui_review" then
            if now-T.at<20000 then return end
            for _,row in ipairs(A.Spawn.survivors(T.c,T.car:getX(),T.car:getY(),80)) do row.npc:Kill(nil) end
            step("all_dead",now)
        elseif T.phase=="all_dead" then
            if not A.Lifecycle.allDead(T.c) then assert(now-T.at<10000,"crew deaths not registered") return end
            if A.Ledger.get(T.c.id) or A.Convoy.entry(T.id) then
                assert(now-T.at<8000,"dead caravan still active") return
            end
            assert(not visible(),"dead caravan still mapped")
            assert(A.vehicleTag(T.car)==nil,"dead car still tagged")
            assert(T.hadContact and T.hadTrade,"real windows were not open before death")
            assert(not A.Client.contact and not A.Client.window,"stale real windows survived death")
            assert(A.Interact.caravanOf({vehicleId=T.id})==nil,"dead interaction still accepted")
            local ctx=ISContextMenu.get(0,0,0)
            assert(A.Client.fill(0,ctx,{},true)~=true,"dead-only car still advertises context actions")
            finish(true,"local zombie escape; partial crew survives; full death clears marker/menu/windows and preserves original loot car")
        end
        if now-T.at>150000 then error("phase timeout "..T.phase) end
    end)
    if not ok then removeAttackers() finish(false,tostring(err)) end
end)
log("START versions="..A.VERSION.."/"..ALifeReactive.VERSION.." car="..T.id)
