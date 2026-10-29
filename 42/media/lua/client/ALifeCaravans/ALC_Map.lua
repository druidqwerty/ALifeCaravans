-- A-Life: Caravans - map markers (client). Every caravan (in the ledger or on
-- the road) is drawn on the vanilla world map and on the minimap: a coloured
-- square by kind, a heading tick, a label with the callsign. Positions arrive
-- with the "state" command every few seconds and are interpolated so the dots
-- move smoothly. Drawn after the map's own render, in the map's coordinates
-- (mapAPI:worldToUIX/Y), the same way A-Life's squad overlay does it.

require "ALifeCaravans/00_ALC_Core"
require "ALifeCaravans/01_ALC_Lines"

local A = ALifeCaravans
local M = { markers = {}, order = {}, installed = false, options = { worldMap = true, minimap = true, labels = true }, intervalMs = 4000 }
A.Map = M

M.colors = {
    trade = { 0.96, 0.72, 0.28 }, convoy = { 0.55, 0.72, 0.40 }, patrol = { 0.38, 0.58, 0.96 },
    rescue = { 0.96, 0.40, 0.40 }, raid = { 0.82, 0.22, 0.22 }, unknown = { 0.8, 0.8, 0.8 },
}

-- New marker list from the server: keep the previous position for interpolation.
function M.setMarkers(list)
    local now = A.now()
    local fresh, order = {}, {}
    for _, marker in ipairs(list or {}) do
        local previous = M.markers[marker.id]
        local entry = {
            id = marker.id, name = marker.name, callsign = marker.callsign, kind = marker.kind, state = marker.state,
            halted = marker.halted, dest = marker.dest, cars = marker.cars, heading = tonumber(marker.heading) or 0,
            x1 = tonumber(marker.x) or 0, y1 = tonumber(marker.y) or 0, t1 = now,
        }
        if previous ~= nil then
            local px, py = M.positionOf(previous, now)
            entry.x0, entry.y0, entry.t0 = px, py, now
        else
            entry.x0, entry.y0, entry.t0 = entry.x1, entry.y1, now
        end
        fresh[marker.id] = entry
        order[#order + 1] = marker.id
    end
    table.sort(order)
    M.markers, M.order = fresh, order
    M.receivedAtMs = now
end

function M.positionOf(marker, now)
    local span = M.intervalMs
    local t = math.max(0, math.min(1, (now - (marker.t0 or now)) / span))
    return A.lerp(marker.x0 or marker.x1, marker.x1, t), A.lerp(marker.y0 or marker.y1, marker.y1, t)
end

function M.colorOf(kind)
    return M.colors[tostring(kind)] or M.colors.unknown
end

local function kindLabel(kind)
    return A.Lines.ui("kind_" .. tostring(kind), tostring(kind))
end

-- Draw every marker on a map element with the given map API (world -> UI).
function M.drawOn(element, api, labels, size)
    if element == nil or api == nil or type(api.worldToUIX) ~= "function" then return 0 end
    local now = A.now()
    local half = size or 5
    local drawn = 0
    local width, height = element.width or 0, element.height or 0
    for _, id in ipairs(M.order) do
        local marker = M.markers[id]
        if marker ~= nil then
            local x, y = M.positionOf(marker, now)
            local sx, sy = api:worldToUIX(x, y), api:worldToUIY(x, y)
            if sx >= -20 and sy >= -20 and sx <= width + 20 and sy <= height + 20 then
                sx, sy = math.floor(sx + 0.5), math.floor(sy + 0.5)
                local color = M.colorOf(marker.kind)
                local live = marker.state == "rendered" or marker.state == "rendering" or marker.state == "fighting"
                element:drawRect(sx - half - 1, sy - half - 1, half * 2 + 2, half * 2 + 2, 0.9, 0.05, 0.05, 0.05)
                element:drawRect(sx - half, sy - half, half * 2, half * 2, 0.95, color[1], color[2], color[3])
                if live then element:drawRectBorder(sx - half - 3, sy - half - 3, half * 2 + 6, half * 2 + 6, 0.9, 1, 1, 1) end
                if marker.halted then element:drawRect(sx - 1, sy - 1, 2, 2, 1, 0.05, 0.05, 0.05) end
                -- heading tick
                local hx, hy = math.cos(marker.heading), math.sin(marker.heading)
                for step = half + 2, half + 6 do
                    element:drawRect(sx + math.floor(hx * step + 0.5) - 1, sy + math.floor(hy * step + 0.5) - 1, 2, 2, 0.95, color[1], color[2], color[3])
                end
                if labels then
                    local text = tostring(marker.callsign or marker.name) .. " (" .. kindLabel(marker.kind) .. ")"
                    element:drawText(text, sx + half + 8, sy - 7, 0, 0, 0, 0.8, UIFont.Small)
                    element:drawText(text, sx + half + 7, sy - 8, 1, 1, 1, 1, UIFont.Small)
                end
                drawn = drawn + 1
            end
        end
    end
    return drawn
end

function M.install()
    if M.installed then return true end
    local ok1 = pcall(function() require "ISUI/Maps/ISWorldMap" end)
    local ok2 = pcall(function() require "ISUI/Maps/ISMiniMap" end)
    if type(ISWorldMap) == "table" and type(ISWorldMap.render) == "function" then
        local original = ISWorldMap.render
        ISWorldMap.render = function(self, ...)
            local result = original(self, ...)
            if M.options.worldMap and A.settings.markers then
                local okDraw, err = pcall(M.drawOn, self, self.mapAPI, M.options.labels, 5)
                if not okDraw then A.fail("map markers", err) M.options.worldMap = false end
            end
            return result
        end
        M.installed = true
    end
    if type(ISMiniMapInner) == "table" then
        local originalInner = ISMiniMapInner.render
        ISMiniMapInner.render = function(self, ...)
            local result
            if type(originalInner) == "function" then result = originalInner(self, ...) end
            if M.options.minimap and A.settings.markers then
                local okDraw, err = pcall(M.drawOn, self, self.mapAPI, false, 3)
                if not okDraw then A.fail("minimap markers", err) M.options.minimap = false end
            end
            return result
        end
        M.installed = true
    end
    if not M.installed then A.debug("map markers: no map UI to draw on", ok1, ok2) end
    return M.installed
end

return M
