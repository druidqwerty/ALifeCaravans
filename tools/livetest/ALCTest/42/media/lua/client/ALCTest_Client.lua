-- A-Life: Caravans live-test driver (client, test only). Joins the test server from the main menu, clicks
-- through character creation, gives the player cash and god mode, then obeys the server-side driver:
-- teleport, enter/exit a caravan car, and reports its view of the caravan every 5 seconds.
local function log(msg) print("[ALCTest] " .. tostring(msg)) end

local cfg
local function readCfg()
    if cfg then return cfg end
    cfg = {}
    local r = getFileReader("ALCTest.txt", false)
    if not r then return cfg end
    local line = r:readLine()
    while line do
        local k, v = string.match(line, "^%s*([%w_]+)%s*=%s*(.-)%s*$")
        if k then cfg[k] = v end
        line = r:readLine()
    end
    r:close()
    return cfg
end

local once = {}
local function first(key)
    if once[key] then return false end
    once[key] = true
    return true
end

local menuStart
local function onMenuTick()
    local c = readCfg()
    if not c.ip then return end
    local now = getTimestampMs()
    menuStart = menuStart or now
    local ms = MainScreen and MainScreen.instance
    if ms and ms.charCreationProfession and ms.charCreationProfession:isVisible() then
        if first("prof") then
            log("character creation: profession -> next")
            ms.charCreationProfession:onOptionMouseDown({ internal = "NEXT" }, 0, 0)
        end
        return
    end
    if ms and ms.charCreationMain and ms.charCreationMain:isVisible() then
        if first("main") then
            log("character creation: appearance -> play")
            ms.charCreationMain:onOptionMouseDown({ internal = "NEXT" }, 0, 0)
        end
        return
    end
    if isClient() then return end
    if now - menuStart < 8000 then return end
    if not (ConnectToServer and ConnectToServer.instance) then return end
    if first("connect") then
        log("connecting to " .. c.ip .. ":" .. c.port .. " as " .. c.user)
        local dummy = { setVisible = function() end }
        ConnectToServer.instance:connect(dummy, "", c.user, c.pass, c.ip, "", c.port, "", false, true, 1)
    end
end

local ready, readyAt, lastStatus = false, nil, 0
local function send(command, args)
    local player = getSpecificPlayer(0)
    if player then sendClientCommand(player, "ALCTest", command, args or {}) end
end

local function status()
    local player = getSpecificPlayer(0)
    if not player then return end
    local A = ALifeCaravans
    local out = { x = math.floor(player:getX()), y = math.floor(player:getY()), sessions = {}, known = 0, markers = 0, window = false, errors = 0 }
    pcall(function()
        local vehicle = player:getVehicle()
        out.inVehicle = vehicle and vehicle:getId() or nil
    end)
    if A then
        out.errors = A.metrics and A.metrics.errors or 0
        for id in pairs(A.Convoy and A.Convoy.known or {}) do out.known = out.known + 1 end
        out.markers = A.Map and #A.Map.order or 0
        out.window = A.Client and A.Client.window ~= nil
        out.installed = A.Boot and A.Boot.installed or false
    end
    local client = ProjectALife and ProjectALife.DrivingDemoClient
    if client then
        for id, s in pairs(client.sessions or {}) do out.sessions[tostring(id)] = tostring(s.phase) .. (s.braking and "/brake" or "") end
    end
    send("status", out)
end

local lastBeat = 0
local function heartbeat(where)
    local now = getTimestampMs()
    if now - lastBeat < 10000 then return end
    lastBeat = now
    local player = getSpecificPlayer(0)
    log("alive(" .. where .. ") isClient=" .. tostring(isClient()) .. " isServer=" .. tostring(isServer())
        .. " player=" .. tostring(player ~= nil) .. (player and (" at " .. math.floor(player:getX()) .. "," .. math.floor(player:getY())) or ""))
end

local function onGameTick()
    heartbeat("tick")
    if not isClient() then return end
    local player = getSpecificPlayer(0)
    if not player then return end
    local now = getTimestampMs()
    if not ready then
        readyAt = readyAt or now
        if now - readyAt < 15000 then return end
        ready = true
        pcall(function()
            player:setGodMod(true)
            for _ = 1, 300 do player:getInventory():AddItem("Base.Money") end
            player:getInventory():AddItem("Base.Cigarettes")
            player:getInventory():AddItem("Base.Cigarettes")
        end)
        log("ready at " .. math.floor(player:getX()) .. "," .. math.floor(player:getY()))
        send("ready", { x = player:getX(), y = player:getY() })
        return
    end
    if now - lastStatus > 5000 then
        lastStatus = now
        pcall(status)
    end
end

local function onServerCommand(module, command, args)
    if module ~= "ALCTest" then return end
    local player = getSpecificPlayer(0)
    if not player then return end
    local ok, err = pcall(function()
        if command == "teleport" then
            player:setX(args.x) player:setY(args.y) player:setZ(0)
            player:setLx(args.x) player:setLy(args.y) player:setLz(0)
            log("teleported to " .. math.floor(args.x) .. "," .. math.floor(args.y))
        elseif command == "enter" then
            local car = getVehicleById(args.vehicleId)
            local R = ProjectALife and ProjectALife.DrivingRiders
            if car and R and R.enter then
                R.enter(player, car, args.seat or 1)
                log("enter requested: car " .. tostring(args.vehicleId) .. " seat " .. tostring(args.seat or 1))
            else
                log("enter failed: no car or riders API")
            end
        elseif command == "exit" then
            if ISVehicleMenu and ISVehicleMenu.onExit then ISVehicleMenu.onExit(player) end
            log("exit requested")
        elseif command == "status" then
            status()
        elseif command == "say" then
            log(tostring(args.text))
        end
    end)
    if not ok then log("command " .. tostring(command) .. " error: " .. tostring(err)) end
end

-- the main menu ticks on OnFETick (front end); OnTick only runs in a world
Events.OnFETick.Add(function()
    heartbeat("fe")
    local ok, err = pcall(onMenuTick)
    if not ok and first("feerr:" .. tostring(err)) then log("menu tick error: " .. tostring(err)) end
end)
Events.OnTick.Add(function()
    local ok, err = pcall(function()
        heartbeat("tick")
        if isClient() and getSpecificPlayer(0) then onGameTick() end
    end)
    if not ok and first("tickerr:" .. tostring(err)) then log("tick error: " .. tostring(err)) end
end)
Events.OnServerCommand.Add(onServerCommand)
log("client driver loaded")
