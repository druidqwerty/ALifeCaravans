-- A-Life: Caravans - speech lines. Texts live in shared/Translate/<lang>/IG_UI.json
-- as IGUI_ALC_<situation>_<n>; a situation picks one of its `count` lines at random
-- and fills {dest}, {town}, {faction}, {item}, {price}, {name}, {leader} variables.
-- Lines are shown through A-Life's own Speech.say (same bubble, same multiplayer
-- mirroring). Radio lines (radio_<n>) go to A-Life's Knox County Radio.

require "ALifeCaravans/00_ALC_Core"

local A = ALifeCaravans
local L = { lastAtMs = {} }
A.Lines = L

L.catalog = {
    hail_ok = { count = 3 },
    hail_busy = { count = 2 },
    hail_refuse = { count = 2 },
    hail_hostile = { count = 2 },
    news = { count = 6 },
    news_dest = { count = 3 },
    trade_open = { count = 2 },
    trade_done = { count = 2 },
    trade_none = { count = 2 },
    trade_broke = { count = 2 },
    trade_sold = { count = 1 },
    trade_refuse = { count = 2 },
    ride_ok = { count = 2 },
    ride_refuse = { count = 2 },
    ride_full = { count = 1 },
    wait_ok = { count = 2 },
    wait_no = { count = 1 },
    farewell = { count = 3 },
    blocked = { count = 3 },
    threat_fold = { count = 2 },
    threat_fight = { count = 2 },
    threat_laugh = { count = 1 },
    toll_ask = { count = 2 },
    toll_paid = { count = 2 },
    toll_broke = { count = 1 },
    attacked = { count = 2 },
    flee = { count = 2 },
    arrive = { count = 2 },
    arrive_riders = { count = 2 },
    passing = { count = 3 },
    escort_ok = { count = 2 },
    escort_refuse = { count = 2 },
    escort_done = { count = 2 },
    escort_void = { count = 2 },
    escort_busy = { count = 1 },
    ambush_zombies = { count = 2 },
    ambush_raiders = { count = 2 },
    ambush_clear = { count = 2 },
    regroup = { count = 2 },
    driver_down = { count = 2 },
    abandon = { count = 2 },
    stuck = { count = 2 },
    radio = { count = 4 },
}

-- Every translation key the catalog needs (for the tests and the status).
function L.keys()
    local keys = {}
    for situation, entry in pairs(L.catalog) do
        for index = 1, entry.count do keys[#keys + 1] = "IGUI_ALC_" .. situation .. "_" .. index end
    end
    table.sort(keys)
    return keys
end

function L.render(text, vars)
    if type(text) ~= "string" then return nil end
    if type(vars) ~= "table" then return text end
    return (string.gsub(text, "{(%w+)}", function(name)
        local value = vars[name]
        if value == nil then return "{" .. name .. "}" end
        return tostring(value)
    end))
end

function L.text(situation, vars)
    local entry = L.catalog[situation]
    if entry == nil then return nil end
    local index = A.rand(entry.count) + 1
    local key = "IGUI_ALC_" .. situation .. "_" .. index
    local text = type(getText) == "function" and getText(key) or nil
    if type(text) ~= "string" or text == "" or text == key then return nil end
    return L.render(text, vars)
end

-- UI text (menus, notices): IGUI_ALC_ui_<id>, with the English fallback.
function L.ui(id, fallback, vars)
    local key = "IGUI_ALC_ui_" .. id
    local text = type(getText) == "function" and getText(key) or nil
    if type(text) ~= "string" or text == "" or text == key then text = fallback end
    return L.render(text, vars)
end

-- Say a line for `situation` through `shell` (the NPC body). False when quiet,
-- on cooldown, or when A-Life refused (dead, downed, hurt).
function L.say(shell, situation, options)
    options = type(options) == "table" and options or {}
    if shell == nil then return false end
    local now = A.now()
    local key = tostring(options.uid or tostring(shell)) .. ":" .. tostring(situation)
    if now < (L.lastAtMs[key] or 0) then return false end
    local text = L.text(situation, options.vars)
    if text == nil then return false end
    local speech = ProjectALife and ProjectALife.Speech
    if speech == nil or type(speech.say) ~= "function" then return false end
    -- no `face`: the speaker sits in a car, turning the body toward the player would look wrong
    local ok, shown = pcall(speech.say, shell, text, { gesture = false, earshot = options.earshot or 40, psex = options.psex })
    if not ok then
        A.fail("say", shown)
        return false
    end
    if shown == false and type(speech.display) == "function" then
        -- A-Life keeps a hurt NPC quiet; a caravan driver still answers.
        local uid, factionId
        if type(speech.variable) == "function" then
            local okUid, value = pcall(speech.variable, shell, "ALifeUID")
            if okUid then uid = value end
            local okFaction, faction = pcall(speech.variable, shell, "ALifeFactionId")
            if okFaction then factionId = faction end
        end
        local color = { 0.85, 0.85, 0.85 }
        if type(speech.colorFor) == "function" then
            local okColor, value = pcall(speech.colorFor, uid, factionId)
            if okColor and type(value) == "table" then color = value end
        end
        local okShow, result = pcall(speech.display, shell, text, color, "directed", uid)
        shown = okShow and result ~= false
    end
    if shown == false then return false end
    L.lastAtMs[key] = now + (tonumber(options.cooldownMs) or 4000)
    A.metrics.lines = A.metrics.lines + 1
    return true, text
end

return L
