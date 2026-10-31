-- TEST ONLY. Install on the SP/MP client. Injectable with getFileReader/loadstring.
if isServer() then return end
if ALCAuditClient then return end
local C = { pending = nil }
ALCAuditClient = C
-- Test-only lifecycle observer: establish whether a window was never opened,
-- replaced, or closed by an actual caller. Does not create/keep a window alive.
local function traceClose()
    if type(getCurrentCoroutine) ~= "function" or type(getCallframeTop) ~= "function" then return end
    local co=getCurrentCoroutine()
    for i=getCallframeTop(co)-1,math.max(0,getCallframeTop(co)-9),-1 do
        local frame=getCoroutineCallframeStack(co,i)
        if frame then print("[ALC_UI_TRACE] caller=" .. tostring(getFilenameOfCallframe(frame)) .. ":" .. tostring(getLineNumber(frame))) end
    end
end
local function observeUI()
    local Cl=ALifeCaravans and ALifeCaravans.Client
    if not Cl or not ALCTradeWindow then return end
    if C.observedClient~=Cl then
        print("[ALC_UI_TRACE] client table changed; previous=" .. tostring(C.observedClient~=nil))
        C.observedClient=Cl
        local open=Cl.openTrade
        Cl.openTrade=function(id,playerNum)
            print("[ALC_UI_TRACE] open request id=" .. tostring(id) .. " player=" .. tostring(playerNum))
            local ok=open(id,playerNum)
            print("[ALC_UI_TRACE] open result=" .. tostring(ok) .. " window=" .. tostring(Cl.window~=nil)
                .. " globalSame=" .. tostring(ALifeCaravans.Client==Cl))
            return ok
        end
    end
    if ALCTradeWindow.onClose~=C.closeObserver then
        local close=ALCTradeWindow.onClose
        C.closeObserver=function(window,...)
            print("[ALC_UI_TRACE] close id=" .. tostring(window.vehicleId) .. " current=" .. tostring(Cl.window==window))
            traceClose()
            return close(window,...)
        end
        ALCTradeWindow.onClose=C.closeObserver
    end
    if C.lastWindow~=Cl.window then
        print("[ALC_UI_TRACE] window changed present=" .. tostring(Cl.window~=nil))
        C.lastWindow=Cl.window
    end
end
local function result(ok, why)
    local row={ok=ok,reason=why}
    print("[ALC_AuditClient] RESULT " .. (ok and "PASS " or "FAIL ") .. tostring(why))
    local w=getFileWriter("ALC_AuditClient_result.txt",true,false)
    w:writeln((ok and "PASS " or "FAIL ") .. tostring(why)); w:close()
    if isClient() then sendClientCommand(getSpecificPlayer(0),"ALCAudit","probeResult",row)
    elseif ALRLive and ALRLive.audit then ALRLive.audit.clientResult=row end
    C.pending=nil
end
function C.request(args)
    C.pending={args=args,at=getTimestampMs()}
    local Cl=ALifeCaravans and ALifeCaravans.Client
    print("[ALC_AuditClient] probe requested car=" .. tostring(args.vehicleId) .. " window=" .. tostring(Cl and Cl.window~=nil))
end
local function probe(player,args)
    local A=ALifeCaravans
    assert(A and A.Client,"Caravans client missing")
    assert(A.Client.stock[args.vehicleId],"stock command not delivered to client")
    assert(A.Client.window and A.Client.window.vehicleId==args.vehicleId,"real trade window did not open")
    local window=A.Client.window
    assert(window.sellList and window.giveList,"real trade window children missing")
    local context=ISContextMenu.get(player:getPlayerNum(),0,0)
    local before=#context.options
    A.Client.fill(player:getPlayerNum(),context,{},false)
    assert(#context.options>before,"empty-ground menu did not find nearby caravan")
    context:setVisible(false)
    local wasTest=ISWorldObjectContextMenu.Test
    ISWorldObjectContextMenu.Test=false
    A.Client.fill(player:getPlayerNum(),context,{},true)
    local controllerFound=ISWorldObjectContextMenu.Test==true
    ISWorldObjectContextMenu.Test=wasTest
    assert(controllerFound,"controller availability probe failed")
    -- Exercise real UI methods, without synthesizing a controller connection.
    window:onJoypadDirRight()
    assert(window.joyList==window.giveList,"controller offer column failed")
    if #window.giveList.items>0 then
        window.giveList.selected=1
        window:onJoypadDown(Joypad.AButton)
        assert(window.giveList.items[1].item.selected==1,"controller quantity selection failed")
    end
    window:onJoypadDown(Joypad.YButton)
    window:onJoypadDown(Joypad.BButton)
    assert(A.Client.window==nil,"controller close did not clean up window")
    return "client inventory matches authority; real trade UI; empty-ground menu; controller discovery/quantity/clear/close"
end
Events.OnServerCommand.Add(function(module,command,args)
    if module=="ALCAudit" and command=="probe" then C.request(args) end
end)
Events.OnTick.Add(function()
    observeUI()
    local pending=C.pending
    if not pending then return end
    local now=getTimestampMs()
    if now-(C.tickAt or 0)<250 then return end
    C.tickAt=now
    local player=getSpecificPlayer(0)
    if not player then return end
    local args=pending.args
    local inv=player:getInventory()
    local money,bandages=inv:getCountTypeRecurse("Base.Money"),inv:getCountTypeRecurse("Base.Bandage")
    if money~=args.money or bandages~=args.bandages then
        if now-pending.at>20000 then result(false,"replication mismatch money=" .. tostring(money) .. "/" .. tostring(args.money)
            .. " bandages=" .. tostring(bandages) .. "/" .. tostring(args.bandages)) end
        return
    end
    if now-pending.at<1500 then return end
    local ok,why=pcall(probe,player,args)
    result(ok,why)
end)
