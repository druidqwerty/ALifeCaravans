return function(check,newVehicle)
    local A=ALifeCaravans
    local C=A.Convoy
    local oldKnown,oldClient=C.known,A.Client
    A.Client=nil
    C.known={[501]={caravanId="same",trip=1,goalIndex=5,arrivedSent=true,stuck={stage=3}}}
    C.setKnown({[501]={caravanId="same",trip=2,goalIndex=1}})
    check("new trip discards previous physical route",C.known[501].discardRoute==true)
    check("new trip resets old arrival cursor and stuck recovery",C.known[501].goalIndex==1 and not C.known[501].arrivedSent and not C.known[501].stuck)
    C.known[501].goalIndex=2
    C.setKnown({[501]={caravanId="same",trip=2,goalIndex=1}})
    check("same trip retains progress and pending route discard",C.known[501].goalIndex==2 and C.known[501].discardRoute)
    C.known,A.Client=oldKnown,oldClient
    local car=newVehicle("Base.CarNormal",100,100)
    local s={vehicle=car,route={{x=100.5,y=100},{x=104,y=100},{x=104.2,y=100},{x=110,y=100}}}
    local route=C.remainingRoute(s)
    check("restart removes reached endpoint and duplicate nearby waypoint",#route==2 and route[1].x==104 and route[2].x==110)
    check("route filtering does not mutate existing queue",#s.route==4)
    s.route={{x=100,y=100}}
    check("only old endpoint yields empty queue for a fresh scout",#C.remainingRoute(s)==0)
    local client=C.client()
    local start,session,departures=client.startDrive,client.sessions[car.id],client.departures
    client.sessions[car.id]={phase="seated",status="invalid waypoint"}
    client.departures={}
    client.startDrive=function() end
    check("silent upstream departure refusal is not a successful start",C.start(car.id,{},35)==false)
    client.startDrive=function() client.sessions[car.id].drivePending={} end
    check("queued MP departure is recognized",C.start(car.id,{},35)==true)
    client.startDrive,client.sessions[car.id],client.departures=start,session,departures
end
