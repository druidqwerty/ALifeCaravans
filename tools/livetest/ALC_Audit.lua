-- TEST ONLY. Install on the SP client OR MP server, never in the published mod.
-- Requires the sibling Reactive harness and a completed ALRLive SOS PASS.
if isClient() then return end
ALRLive = ALRLive or { once = {} }
if ALRLive.audit then return end
local T = { phase = "await_sos", at = getTimestampMs(), samples = {} }
ALRLive.audit = T
local function log(text) print("[ALC_Audit] " .. tostring(text)) end
local function stage(name, now) T.phase, T.at = name, now; log("STAGE " .. name) end
local function finish(ok, reason)
    T.phase, T.ok, T.reason = "done", ok, reason
    log("RESULT " .. (ok and "PASS " or "FAIL ") .. reason)
    local w = getFileWriter("ALC_Audit_result.txt", true, false)
    w:writeln((ok and "PASS " or "FAIL ") .. reason)
    w:writeln("scope=production hail/trade; inventory/UI; timed halt; observed spontaneous exit/reboard/depart")
    for _, row in ipairs(T.samples) do w:writeln(row) end
    w:close()
end
local function lead()
    for _, id in ipairs(T.c and T.c.vehicleIds or {}) do
        local car = getVehicleById(id)
        if car then return car end
    end
end
local function follow(player, car, now)
    if ALifeCaravans.dist(player:getX(), player:getY(), car:getX(), car:getY()) <= 13 then return true end
    if now - (T.moveAt or 0) < 3000 then return false end
    T.moveAt = now
    if isServer() then sendServerCommand(player, "ALRLiveMP", "teleport", { x = car:getX()+7, y = car:getY()+7 })
    else player:teleportTo(car:getX()+7, car:getY()+7, 0) end
    return false
end
local function count(player, item) return player:getInventory():getCountTypeRecurse(item) end
local function start(player, now)
    local sos = ALRLive.sos
    if not sos or sos.phase ~= "done" then return end
    local r = getFileReader("ALRLive_SOS_result.txt", false)
    local result = r and r:readLine() or nil
    if r then r:close() end
    if not result or result:sub(1,5) ~= "PASS " then return finish(false,"prior SOS did not pass: " .. tostring(result)) end
    T.c = sos.caravan
    if not T.c then return finish(false,"SOS fixture caravan missing") end
    if ALRLive.auditGoal then
        T.c.goals={ALRLive.auditGoal}; T.c.goalIndex=1; T.c.arrivals=0
        T.c.trip=(T.c.trip or 0)+1
        ALifeCaravans.Director.publish(true)
        log("fixture route extended to " .. ALRLive.auditGoal.x .. "," .. ALRLive.auditGoal.y)
    end
    log("version=" .. tostring(ALifeCaravans.VERSION) .. " caravan=" .. T.c.id)
    stage("hail", now)
end
local function hail(player, car, now)
    local A = ALifeCaravans
    if not follow(player,car,now) then return end
    if T.c.halted then A.Director.resume(T.c) end
    A.Interact.command(player,"hail",{vehicleId=car:getId()})
    if not T.c.halted then return finish(false,"production hail refused; stance=" .. A.Interact.stanceFor(T.c,player)) end
    stage("trade",now)
end
local function trade(player, car, now)
    local A = ALifeCaravans
    if now-T.at < 1500 or not follow(player,car,now) then return end
    -- A hail is a braking request, not an instantaneous physical stop. Opening
    -- the UI while the car is still rolling can correctly close it out of range.
    if not car:isStopped() then return end
    -- Controlled goods/payment in this throwaway world, actual production exchange.
    T.c.stock = {{item="Base.Bandage",name=A.Trade.name("Base.Bandage"),value=10,count=1}}
    local funded = A.Trade.exchange(player,{giveRows={},takeRows={{item="Base.Money",count=20}}})
    if not funded then return finish(false,"fixture currency creation failed") end
    T.moneyBefore,T.bandageBefore=count(player,"Base.Money"),count(player,"Base.Bandage")
    A.Interact.command(player,"trade",{vehicleId=car:getId()})
    A.Interact.command(player,"deal",{vehicleId=car:getId(),revision=T.c.stockRevision or 0,
        take={[1]=1},give={{type="Base.Money",count=20}}})
    if count(player,"Base.Money")~=T.moneyBefore-20 or count(player,"Base.Bandage")~=T.bandageBefore+1 then
        return finish(false,"production deal inventory counts mismatch")
    end
    local args={vehicleId=car:getId(),money=T.moneyBefore-20,bandages=T.bandageBefore+1}
    if isServer() then sendServerCommand(player,"ALCAudit","probe",args)
    elseif ALCAuditClient then ALCAuditClient.request(args)
    else return finish(false,"client audit extension missing") end
    log("SERVER TRADE PASS money -20 bandages +1")
    stage("ui",now)
end
local function ui(player, car, now)
    if not T.clientResult then return end
    if not T.clientResult.ok then return finish(false,"client probe: " .. tostring(T.clientResult.reason)) end
    ALifeCaravans.Director.halt(T.c,3,"audit_timed_stop")
    T.stopped={x=car:getX(),y=car:getY()}
    log("UI PASS " .. tostring(T.clientResult.reason))
    stage("halt",now)
end
local function halt(player, car, now)
    if now-T.at<1000 then return end
    if now-T.at<2500 then
        if not T.c.halted then return finish(false,"timed halt expired too early") end
        T.haltObserved=true
    end
    if T.c.halted then return end
    if not T.haltObserved then return finish(false,"halt was never observed") end
    T.resumeStart={x=car:getX(),y=car:getY()}
    stage("depart",now)
end
local function depart(player, car, now)
    local A=ALifeCaravans
    follow(player,car,now)
    local distance=A.dist(car:getX(),car:getY(),T.resumeStart.x,T.resumeStart.y)
    if distance<10 then return end
    if not car:getDriver() then return finish(false,"movement without actual driver") end
    log("TIMED STOP/DEPART PASS distance=" .. distance)
    T.exitStart={x=car:getX(),y=car:getY()}
    A.Spawn.dismount(T.c,{x=car:getX()+3,y=car:getY()+3})
    stage("reboard",now)
end
local function reboard(player, car, now)
    local A=ALifeCaravans
    follow(player,car,now)
    local foot,seated=0,0
    for _,row in ipairs(A.Spawn.survivors(T.c,car:getX(),car:getY(),100)) do
        if row.inCar==car then seated=seated+1 else foot=foot+1 end
    end
    if foot>0 and not car:getDriver() then T.sawExit=true end
    if T.sawExit and car:getDriver() and seated>=2 then
        T.reboardStart={x=car:getX(),y=car:getY()}
        log("REAL REBOARD PASS seated=" .. seated)
        stage("escape",now)
    end
end
local function escape(player, car, now)
    local A=ALifeCaravans
    follow(player,car,now)
    local distance=A.dist(car:getX(),car:getY(),T.reboardStart.x,T.reboardStart.y)
    if distance>=10 and car:getDriver() then finish(true,"hail/trade/UI/timed stop; actual on-foot crew reboarded and drove " .. string.format("%.2f",distance) .. " tiles") end
end
if isServer() then
    Events.OnClientCommand.Add(function(module,command,player,args)
        if module=="ALCAudit" and command=="probeResult" and player==ALRLive.player then T.clientResult=args end
    end)
end
Events.OnTick.Add(function()
    if T.phase=="done" then return end
    local now=getTimestampMs()
    if now-(T.tickAt or 0)<250 then return end
    T.tickAt=now
    local player=ALRLive.player or getSpecificPlayer(0)
    if not player then return end
    local ok,err=pcall(function()
        if T.phase=="await_sos" then return start(player,now) end
        local car=lead()
        if not car then return finish(false,"fixture vehicle lost at " .. T.phase) end
        if now-T.at>180000 then return finish(false,"timeout " .. T.phase .. " sawExit=" .. tostring(T.sawExit)) end
        if now-(T.sampleAt or 0)>2000 then
            T.sampleAt=now
            local _,s=ALifeCaravans.Spawn.sessionOf(car:getId())
            local row=string.format("%d,%s,%.2f,%.2f,driver=%s,session=%s,halted=%s",now,T.phase,car:getX(),car:getY(),
                tostring(car:getDriver()~=nil),tostring(s and s.phase),tostring(T.c.halted))
            T.samples[#T.samples+1]=row; log(row)
        end
        local handlers={hail=hail,trade=trade,ui=ui,halt=halt,depart=depart,reboard=reboard,escape=escape}
        handlers[T.phase](player,car,now)
    end)
    if not ok then finish(false,"scenario error " .. tostring(err)) end
end)
