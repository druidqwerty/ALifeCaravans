-- A-Life: Caravans - bootstrap. Installs everything once Project A-Life is
-- loaded (OnGameStart / OnServerStarted, with an OnTick fallback), polls the
-- host's Sandbox page every 2 s, runs the director (world owner) and the convoy
-- tick (driving side), routes client commands, and prints counters every few minutes.

require "ALifeCaravans/00_ALC_Core"
require "ALifeCaravans/01_ALC_Lines"
require "ALifeCaravans/02_ALC_Vehicles"
require "ALifeCaravans/03_ALC_Roads"
require "ALifeCaravans/04_ALC_Convoy"
require "ALifeCaravans/05_ALC_Trade"
require "ALifeCaravans/ALC_Ledger"
require "ALifeCaravans/ALC_Spawn"
require "ALifeCaravans/ALC_Director"
require "ALifeCaravans/ALC_Interact"

local A = ALifeCaravans
local B = { installed = false, tries = 0, settingsAtMs = 0, minute = 0, lastReport = nil }
A.Boot = B

function B.install()
    if B.installed then return true end
    local p = ProjectALife
    if type(p) ~= "table" or p.DrivingDemo == nil or p.VehicleArrivals == nil or p.Speech == nil then
        B.tries = B.tries + 1
        if B.tries == 1 then A.log("Project A-Life not loaded yet, waiting") end
        return false
    end
    B.installed = true
    A.refreshSettings()
    local ok, err = pcall(function()
        if A.authority() then
            A.Spawn.install()
            A.Interact.install()
            A.Ledger.open()
        end
    end)
    if not ok then
        A.fail("install", err)
        return true
    end
    A.log("v" .. A.VERSION .. " installed (" .. A.side() .. ")" .. (A.settings.enabled and "" or ", disabled in sandbox"))
    return true
end

function B.tick()
    if not B.installed then return end
    local now = A.now()
    if now >= B.settingsAtMs then
        B.settingsAtMs = now + 2000
        pcall(A.refreshSettings)
    end
    if A.authority() then
        local ok, err = pcall(A.Director.tick)
        if not ok then A.fail("director", err) end
    end
    if A.drivingSide() then
        local ok, err = pcall(A.Convoy.tick)
        if not ok then A.fail("convoy", err) end
    end
end

function B.report()
    if not B.installed then return end
    B.minute = B.minute + 1
    if B.minute % 5 ~= 0 then return end
    local current = A.counters()
    if current == B.lastReport then return end
    B.lastReport = current
    A.log(current)
    if A.settings.debug and A.authority() then
        for _, line in ipairs(A.Director.describe()) do A.log(line) end
    end
end

function B.onClientCommand(module, command, player, args)
    if module ~= A.MODULE or not B.installed or not A.authority() then return end
    local ok, err = pcall(A.Interact.command, player, command, args)
    if not ok then A.fail("command " .. tostring(command), err) end
end

function B.onHorn(character, vehicle, pressed)
    if not B.installed then return end
    pcall(A.Interact.onHorn, character, vehicle, pressed)
end

local function add(name, callback)
    local event = type(Events) == "table" and Events[name] or nil
    if event ~= nil and type(event.Add) == "function" then event.Add(callback) end
end

local function remove(name, callback)
    local event = type(Events) == "table" and Events[name] or nil
    if event ~= nil and type(event.Remove) == "function" then pcall(event.Remove, callback) end
end

if not A.bootRegistered then
    A.bootRegistered = true
    add("OnGameStart", function() pcall(B.install) end)
    add("OnServerStarted", function() pcall(B.install) end)
    local retry
    retry = function()
        if not B.installed and B.tries <= 900 then pcall(B.install) end
        if B.installed or B.tries > 900 then remove("OnTick", retry) end
    end
    add("OnTick", retry)
    add("OnTick", B.tick)
    add("EveryOneMinute", function() pcall(B.report) end)
    add("OnClientCommand", B.onClientCommand)
    add("OnVehicleHorn", B.onHorn)
end

return B
