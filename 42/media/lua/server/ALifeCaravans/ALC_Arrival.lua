-- Original factory for our convoy requests, using the installed game's public
-- spawn API and A-Life's vehicle preparation. Kahlua '%' is signed remainder:
-- a southbound negative angle must not become a missing direction-table key.
require "ALifeCaravans/00_ALC_Core"
local A = ALifeCaravans
local V = {}
A.Arrival = V

function V.direction(dx,dy)
    local turns = A.atan2(-dy,dx)/(2*math.pi)
    turns = turns-math.floor(turns)
    return (math.floor(turns*8+0.5)+6)%8
end

function V.create(script,site,requestId)
    local point=site and site.route and site.route[1]
    if not point then return nil,"no initial road waypoint" end
    local square=getCell():getGridSquare(math.floor(site.x),math.floor(site.y),site.z or 0)
    if not square then return nil,"spawn square unloaded" end
    local direction=IsoDirections.fromIndex(V.direction(point.x-site.x,point.y-site.y))
    local car=addVehicleDebug(script,direction,-1,square)
    if not car then return nil,"vehicle spawn refused" end
    local seats={}
    local ok,why=pcall(function()
        local p=ProjectALife
        p.VehicleArrivalVehicle.condition(car,ZombRand)
        for seat=0,math.min(15,car:getMaxPassengers()-1) do
            if car:isSeatInstalled(seat) and p.DrivingEntry.point(car,seat) then seats[#seats+1]=seat end
        end
        if seats[1]~=0 then error("no usable driver door") end
        car:getModData().ProjectALifeVehicleArrival=requestId
        local vector=car:getForwardVector(Vector3f.new())
        local obstacle=p.DrivingRoute.scan(car,A.atan2(vector:z(),vector:x()),0,nil,0)
        if obstacle then error("spawn blocked: "..tostring(obstacle.reason)) end
    end)
    if not ok then ProjectALife.VehicleArrivalVehicle.remove(car) return nil,tostring(why) end
    return car,seats
end

return V
