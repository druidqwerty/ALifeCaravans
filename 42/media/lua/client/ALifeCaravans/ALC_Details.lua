require "ALifeCaravans/ALC_ContactWindow"
local A=ALifeCaravans
local L=A.Lines
local D={}
A.Details=D

function D.rows(kind,args)
    local rows={}
    if kind=="cargoView" then
        for _,row in ipairs(args.cargo or {}) do
            rows[#rows+1]={label=row.name or row.type or "?",value="x"..tostring(row.count or 1),type=row.type}
        end
        if #rows==0 then rows[1]={label=L.ui("cargo_empty","The cargo compartment is empty")} end
        return L.ui("panel_cargo","Inspect cargo"),rows
    end
    local fields={{"faction","detail_faction","Faction"},{"leader","detail_leader","Crew leader"},
        {"dest","detail_destination","Destination"},{"crew","detail_crew","Surviving crew"},
        {"vehicles","detail_vehicles","Vehicles"},{"speed","detail_speed","Cruise speed, km/h"},
        {"trip","detail_trip","Journey"},{"favor","detail_favor","Your faction favor"},
        {"stockCount","detail_stock","Stock entries"}}
    for _,field in ipairs(fields) do
        rows[#rows+1]={label=L.ui(field[2],field[3]),value=tostring(args[field[1]] or "-")}
    end
    return L.ui("panel_status","Detailed status"),rows
end

function D.receive(kind,args)
    if type(args)~="table" or not args.vehicleId or not A.Convoy.entry(args.vehicleId) then return false end
    local panel=A.Client.contact
    if not panel or panel.vehicleId~=args.vehicleId or panel.playerNum~=(args.playerNum or 0) then
        if not A.Style.openContact(args.vehicleId,args.playerNum or 0) then return false end
        panel=A.Client.contact
    end
    panel:showDetail(D.rows(kind,args))
    return true
end
return D
