return function(check)
    local V=ALifeCaravans.Arrival
    local cases={{1,0,6},{1,-1,7},{0,-1,0},{-1,-1,1},{-1,0,2},{-1,1,3},{0,1,4},{1,1,5}}
    for _,c in ipairs(cases) do
        check("spawn heading octant "..c[3],V.direction(c[1],c[2])==c[3])
    end
    local oldSpawn,oldDirections,oldVector=addVehicleDebug,IsoDirections,Vector3f
    local p=ProjectALife
    local oldEntry,oldCondition,oldScan,oldRemove=p.DrivingEntry,p.VehicleArrivalVehicle.condition,p.DrivingRoute.scan,p.VehicleArrivalVehicle.remove
    local data,removed,heading={},0,nil
    local car={getMaxPassengers=function() return 2 end,isSeatInstalled=function() return true end,
        getModData=function() return data end,getForwardVector=function() return {x=function() return 0 end,z=function() return 1 end} end}
    addVehicleDebug=function(_,dir) heading=dir return car end
    IsoDirections={fromIndex=function(i) assert(i>=0 and i<=7) return i end}
    Vector3f={new=function() return {} end}
    p.DrivingEntry={point=function() return {} end}
    p.VehicleArrivalVehicle.condition=function() end
    p.VehicleArrivalVehicle.remove=function(v) if v==car then removed=removed+1 end end
    p.DrivingRoute.scan=function() return nil end
    local made,seats=V.create("Base.CarNormal",{x=100,y=100,route={{x=100,y=120}}},"test-heading")
    check("southbound factory creates a usable tagged car",made==car and heading==4 and seats[1]==0 and data.ProjectALifeVehicleArrival=="test-heading")
    p.DrivingRoute.scan=function() return {reason="solid obstacle"} end
    made=V.create("Base.CarNormal",{x=100,y=100,route={{x=100,y=120}}},"test-blocked")
    check("blocked factory car removed before crew allocation",made==nil and removed==1)
    addVehicleDebug,IsoDirections,Vector3f=oldSpawn,oldDirections,oldVector
    p.DrivingEntry,p.VehicleArrivalVehicle.condition,p.DrivingRoute.scan,p.VehicleArrivalVehicle.remove=oldEntry,oldCondition,oldScan,oldRemove
end
