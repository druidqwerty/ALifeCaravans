-- TEST ONLY: two isolated clients; server companion orchestrates the scenario.
assert(isClient(),"MP client only")
require "Vehicles/ISUI/ISVehicleMenu"
require "TimedActions/ISTimedActionQueue"
local A,P=ALifeCaravans,ProjectALife
local T={phase="wait"}
ALCJointClient=T
local function report(command,args)
    sendClientCommand(getSpecificPlayer(0),"ALCJoint",command,args or {})
end
local function log(s) print("[ALC_JointClient] "..s) end
Events.OnServerCommand.Add(function(module,command,args)
    if module~="ALCJoint" then return end
    if command=="setup" then
        T.id,T.cid,T.primary=args.id,args.cid,args.primary
        T.phase,T.at="load",getTimestampMs()
        if T.primary then SendCommandToServer('/teleportplayer observer "admin"') end
    elseif command=="reopen" then T.phase,T.at="reopen",getTimestampMs()
    elseif command=="dead" then T.phase,T.at="dead",getTimestampMs()
    elseif command=="exit" then
        if T.primary then ISVehicleMenu.onExit(getSpecificPlayer(0)) end
        T.phase,T.at="exit",getTimestampMs()
    elseif command=="finish" then
        T.done=true
        log("RESULT PASS replicated lifecycle, windows and original car preserved")
        local w=getFileWriter("ALC_JointClient_result.txt",true,false)
        w:writeln("PASS replicated lifecycle, real windows, original car, normal passenger exit; primary="..tostring(T.primary))
        w:close()
    end
end)
local function open()
    assert(A.Style.openContact(T.id,0),"contact failed")
    A.Client.send("trade",{vehicleId=T.id})
end
Events.OnTick.Add(function()
    if T.done or T.phase=="wait" then return end
    local now=getTimestampMs()
    if now-(T.tickAt or 0)<200 then return end
    T.tickAt=now
    local ok,why=pcall(function()
        assert(now-T.at<90000,"client phase timeout "..T.phase)
        local player=getSpecificPlayer(0)
        local car=getVehicleById(T.id)
        if T.phase=="load" then
            if not car or not A.Convoy.entry(T.id) or A.dist(player:getX(),player:getY(),car:getX(),car:getY())>14 then return end
            T.car=car
            assert(A.Map.markers[T.cid],"initial map marker missing")
            open()
            if T.primary then
                A.Client.send("ride",{vehicleId=T.id})
                T.phase="permission"
            else T.phase="windows" end
        elseif T.phase=="permission" then
            if P.DrivingRiders.allowed(T.id) and not P.DrivingDemoClient.pending[T.id] then
                local seat=P.DrivingRiders.seat(player,car)
                assert(seat and seat>0,"no passenger seat")
                P.DrivingDemoClient.ride(T.id,seat)
                T.seat,T.phase=seat,"boarding"
            end
        elseif T.phase=="boarding" then
            if player:getVehicle()==car and car:getSeat(player)==T.seat then
                T.phase="windows"
                log("VANILLA BOARD PASS seat="..T.seat)
            elseif not player:getVehicle() and not P.DrivingDemoClient.pending[T.id]
                and #ISTimedActionQueue.getTimedActionQueue(player).queue==0
                and now-(T.rideRetryAt or T.at)>2000 and (T.rideRetries or 0)<3 then
                -- Server/client speed and mode acknowledgements can cross.
                -- Repeat only the official request, never force a seat/action.
                local seat=P.DrivingRiders.seat(player,car,T.seat)
                if seat then
                    T.rideRetryAt,T.rideRetries=now,(T.rideRetries or 0)+1
                    P.DrivingDemoClient.ride(T.id,seat)
                end
            end
        elseif T.phase=="windows" then
            if A.Client.contact and A.Client.window then
                T.phase,T.at="holding",now
                report("ready")
                log("READY primary="..tostring(T.primary))
            end
        elseif T.phase=="reopen" then
            if not T.primary and A.dist(player:getX(),player:getY(),car:getX(),car:getY())>12 then
                if #ISTimedActionQueue.getTimedActionQueue(player).queue==0 then
                    local sq=getCell():getGridSquare(math.floor(car:getX()+6),math.floor(car:getY()+6),0)
                    assert(sq,"observer walk destination unloaded")
                    ISTimedActionQueue.add(ISWalkToTimedAction:new(player,sq))
                end
                return
            end
            open(); T.phase="review"
        elseif T.phase=="review" then
            if A.Client.contact and A.Client.window then
                T.phase,T.at="holding",now
                report("review")
                log("REOPEN PASS both actual windows")
            end
        elseif T.phase=="dead" then
            if A.Convoy.entry(T.id) or A.Map.markers[T.cid] or A.Client.contact or A.Client.window then return end
            assert(car and car==T.car,"original physical car lost")
            if T.primary then assert(player:getVehicle()==car and car:getSeat(player)==T.seat,"passenger detached by crew death") end
            -- getPlayerContextMenu can be uninitialized on a fresh observer
            -- who has never opened RMB. Use a real standalone vanilla menu.
            local context=ISContextMenu:new(0,0,1,1,1.5)
            context:initialise()
            assert(A.Client.fill(0,context,{},true)~=true,"dead-only car advertises actions")
            report("cleared")
            T.phase,T.at="holding",now
            log("DEATH PASS marker/menu/windows cleared; original vehicle and player seat retained")
        elseif T.phase=="exit" then
            if not player:getVehicle() then
                report("exited")
                T.phase,T.at="holding",now
                log("EXIT PASS")
            end
        end
    end)
    if not ok then T.done=true; report("failure",{why=tostring(why)}); log("RESULT FAIL "..tostring(why)) end
end)
log("observer installed")
