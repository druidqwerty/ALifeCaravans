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

    -- 0.6.2 regressions: passed-goal skipping, perpendicular road scouting, tail compression,
    -- offline goal sync, non-backtracking trips, convoy scene filtering, escape/stall guards,
    -- and roadside dismount + resume reboarding.
    local gEntry = { goals = { { x = 100, y = 100 }, { x = 200, y = 100 }, { x = 300, y = 100 } }, goalIndex = 1 }
    local nextG, nextIdx = C.goalFor(gEntry, 135, 102)
    check("goalFor skips passed goal behind car even outside goalReach", nextIdx == 2 and nextG.x == 200)
    local multiEntry = {
        goals = {
            { x = 100, y = 100 }, { x = 155, y = 100 }, { x = 210, y = 100 },
            { x = 265, y = 100 }, { x = 320, y = 100 }, { x = 375, y = 100 },
        },
        goalIndex = 1,
    }
    local multiG, multiIdx = C.goalFor(multiEntry, 315, 104)
    check("goalFor advances across multiple passed intermediate goals to forward target",
        multiIdx == 6 and multiG.x == 375)

    local compressed = A.Roads.compress({
        { x = 100, y = 100 }, { x = 104, y = 100 }, { x = 108, y = 100 },
        { x = 112, y = 100 }, { x = 116, y = 100 }, { x = 120, y = 100 },
    }, 10, 14)
    check("compress merges short final tail stub instead of 4-tile pair",
        #compressed == 1 and compressed[1].x == 120)

    local scene = A.Roads.scene(PLAYER)
    local perpPoints = A.Roads.scout(scene, { x = 100, y = 100 }, { x = 100, y = 200 }, { maxPoints = 10, heading = 0 })
    check("scout follows perpendicular road when direct goal is off-road",
        #perpPoints >= 1 and A.dist(perpPoints[#perpPoints].x, perpPoints[#perpPoints].y, 100, 100) >= 12)
    local noUturnPoints = A.Roads.scout(scene, { x = 140, y = 100 }, { x = 60, y = 100 }, { maxPoints = 10, heading = 0 })
    check("scout does not U-turn across wide road when heading east",
        #noUturnPoints >= 1 and noUturnPoints[#noUturnPoints].x > 140)

    local G = ProjectALife.RoadGraph
    local offCaravan = {
        id = "offline-sync", route = { "townA", "townB" }, leg = 1, t = 0, speedKmh = 36,
        x = 20, y = 100, state = "offline",
    }
    offCaravan.goals = A.Director.goalsFor(G, offCaravan)
    local firstGoalX = offCaravan.goals[1].x
    A.Director.advance(G, offCaravan, 5, { { x = 1000, y = 100, key = "ivan" } })
    check("offline advance refreshes goals ahead of current position",
        offCaravan.x > firstGoalX and offCaravan.goals[1].x > offCaravan.x)

    local noBack = A.Director.planRoute(G, "townB", 2, "townA")
    check("planRoute avoids immediate U-turn back to previous town when another edge exists",
        noBack ~= nil and noBack[2] == "townC")

    -- Convoy hooks: Escape suppression, same-convoy obstacle filtering, clear-road stall guard
    local p = ProjectALife
    local savedEscape, savedScene, savedStall, savedWalked = p.DrivingEscape, p.DrivingRoute.scene, p.DrivingRecovery, p.DrivingEntry
    local escapeCalled = 0
    p.DrivingEscape = { tick = function(s) escapeCalled = escapeCalled + 1 s.cruiseSpeed = 99 end }
    p.DrivingRoute.scene = function(v)
        return { bodies = {
            { x = 195, y = 100.5, label = "vehicle", moving = true },
            { x = 150, y = 100.5, label = "vehicle", moving = false },
            { x = 100, y = 103.5, label = "player", moving = true },
        } }
    end
    local stallCalled = 0
    p.DrivingRecovery = { driveStall = function() stallCalled = stallCalled + 1 return true end }
    local walkedCalls = 0
    p.DrivingEntry = {
        walked = function() walkedCalls = walkedCalls + 1 return false, "cancelled/player_order_changed" end,
        walk = function(s, t) s.walkAction = { status = "running" } s.walkTarget = t end,
    }
    C.hooksInstalled = nil
    for _, k in ipairs({ "DrivingEscape.tick", "DrivingRoute.scene", "DrivingRecovery.driveStall", "DrivingEntry.walked" }) do
        A.wrapped[k] = nil
    end
    C.installHooks()
    local c1 = newVehicle("Base.CarNormal", 100, 100.5)
    local c2 = newVehicle("Base.CarNormal", 195, 100.5)
    A.tagVehicle(c1, "convoy-filter", 1)
    A.tagVehicle(c2, "convoy-filter", 2)
    local oldKnown2 = C.known
    C.known = {
        [c1.id] = { caravanId = "convoy-filter", index = 1 },
        [c2.id] = { caravanId = "convoy-filter", index = 2 },
    }
    local s1 = { vehicle = c1, cruiseSpeed = 4.5, started = CLOCK - 1000, phase = "approach",
        walkAction = { status = "cancelled", result = "player_order_changed" }, walkTarget = { x = 101, y = 100 } }
    p.DrivingEscape.tick(s1, CLOCK)
    check("DrivingEscape tick suppressed for caravan cars so formation cruiseSpeed survives",
        escapeCalled == 0 and s1.cruiseSpeed == 4.5)
    local filteredScene = p.DrivingRoute.scene(c1, {})
    check("DrivingRoute.scene filters same-convoy vehicles and keeps foreign vehicles",
        #filteredScene.bodies == 2 and filteredScene.bodies[1].x == 150)
    local nav = { obstacle = nil, driveProgress = { x = 100, y = 100, at = CLOCK - 1200 } }
    check("DrivingRecovery.driveStall ignores startup on clear road without obstacle",
        p.DrivingRecovery.driveStall(s1, nav, CLOCK) == false and stallCalled == 0 and nav.driveProgress == nil)
    local arrived, walkErr = p.DrivingEntry.walked(s1)
    check("DrivingEntry.walked retries cancelled approach walk instead of aborting boarding",
        arrived == false and walkErr == nil and s1.walkRetries == 1 and s1.walkAction.status == "running")
    C.known = oldKnown2
    p.DrivingEscape, p.DrivingRoute.scene, p.DrivingRecovery, p.DrivingEntry = savedEscape, savedScene, savedStall, savedWalked
end
