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

    -- 0.6.3 performance regressions: fastScene cache (no zombie-list scan, shared tiles),
    -- impulse suppression, frame-spike dt clamp, bounding-box zombie filter, unloaded tryRender guard.
    local modDataCalls = 0
    local oldZombies = ZOMBIES
    ZOMBIES = {}
    for idx = 1, 500 do
        local zx = 300 + (idx % 50)
        ZOMBIES[idx] = {
            getX = function() return zx end,
            getY = function() return 300 end,
            getZ = function() return 0 end,
            isDead = function() modDataCalls = modDataCalls + 1 return false end,
            getModData = function() modDataCalls = modDataCalls + 1 return {} end,
        }
    end
    local savedWatchdog = p.Watchdog
    local savedControl = p.DrivingControl
    local savedDrive = p.DrivingDemoClient.drive
    local npcShell = newShell("perf-npc", "f_army")
    npcShell.x, npcShell.y = 104, 102.5
    p.Watchdog = { bindings = { ["perf-npc"] = { shell = npcShell } } }
    p.DrivingRoute.dimensions = function() return 0.9, 2.2 end
    local impulseCalls = 0
    p.DrivingControl = {
        apply = function(s, h, ax, ay, alpha, imp)
            imp(s.vehicle, 0, 0, ax, ay, 10)
            imp(s.vehicle, 1, 0, 0, 1, 5)
            imp(s.vehicle, -1, 0, 0, -1, 5)
        end,
    }
    local observedDt = nil
    p.DrivingDemoClient.drive = function(s) observedDt = (A.now() - s.last) / 1000 end
    C.hooksInstalled = nil
    C.bodyCache, C.tileCache = nil, {}
    for _, k in ipairs({ "DrivingEscape.tick", "DrivingRoute.scene", "DrivingRecovery.driveStall",
            "DrivingEntry.walked", "DrivingControl.apply", "DrivingDemoClient.drive" }) do
        A.wrapped[k] = nil
    end
    C.installHooks()
    local fast1 = p.DrivingRoute.scene(c1, {})
    local fast2 = p.DrivingRoute.scene(c2, {})
    check("fastScene skips getZombieList when Watchdog.bindings is present", modDataCalls == 0, modDataCalls)
    check("fastScene shares squares and edges cache across convoy cars in 250ms window",
        fast1.squares == fast2.squares and fast1.edges == fast2.edges)
    check("fastScene includes nearby active A-Life NPCs and excludes same-convoy cars", (function()
        local hasNpc, hasSameConvoy = false, false
        for _, b in ipairs(fast1.bodies) do
            if b.label == "A-Life NPC" then hasNpc = true end
            if b.label == "vehicle" and math.abs(b.x - 195) < 1 then hasSameConvoy = true end
        end
        return hasNpc and not hasSameConvoy
    end)())

    -- Bounding-box pre-filter in Threats.scan and Spawn.zombiesNear
    local threatRes = A.Threats.scan({ { x = 100, y = 100, vehicle = c1 } })
    local nearCount = A.Spawn.zombiesNear(100, 100, 18)
    check("Threats.scan and Spawn.zombiesNear skip getModData/isDead on far zombies outside bounding box",
        modDataCalls == 0 and threatRes.near == 0 and nearCount == 0, modDataCalls)

    -- Impulse suppression: parked/coasting = 0 impulses, straight accel = 1 impulse, turn = 3 impulses
    local rawImpulse = function() impulseCalls = impulseCalls + 1 end
    p.DrivingControl.apply({ vehicle = c1, phase = "seated", targetSpeed = 0 }, 0, 0.2, 0, 0.001, rawImpulse)
    check("parked caravan car suppresses idle impulses", impulseCalls == 0, impulseCalls)
    p.DrivingControl.apply({ vehicle = c1, phase = "driving", targetSpeed = 8 }, 0, 0.005, 0.005, 0.001, rawImpulse)
    check("coasting caravan car suppresses micro impulses", impulseCalls == 0, impulseCalls)
    p.DrivingControl.apply({ vehicle = c1, phase = "driving", targetSpeed = 8 }, 0, 2.0, 0, 0.001, rawImpulse)
    check("straight-accelerating caravan car applies only 1 linear impulse instead of 3", impulseCalls == 1, impulseCalls)
    impulseCalls = 0
    p.DrivingControl.apply({ vehicle = c1, phase = "driving", targetSpeed = 8 }, 0, 2.0, 0, 0.25, rawImpulse)
    check("turning caravan car applies all 3 impulses", impulseCalls == 3, impulseCalls)

    -- Frame-spike dt clamp in DrivingDemoClient.drive
    local lagSession = { vehicle = c1, last = CLOCK - 800 }
    p.DrivingDemoClient.drive(lagSession)
    check("DrivingDemoClient.drive clamps frame spike dt to 0.05s for caravan cars",
        observedDt ~= nil and math.abs(observedDt - 0.05) < 0.001, observedDt)

    -- Unloaded spawn area fast-fail without renderFailures penalty
    local unCaravan = {
        id = "unloaded-probe", state = "offline", x = 600, y = 100,
        vehicles = { "Base.CarNormal" }, crew = { "f_army_p1", "f_army_p2" },
        goals = { { x = 650, y = 100 } }, goalIndex = 1, renderFailures = 0, nextRenderAtMs = 0,
    }
    local oldRadius, oldMaxR, oldMaxC = A.settings.renderRadius, A.Director.maxRendered, A.Director.maxCars
    A.settings.renderRadius = 700
    A.Director.maxRendered, A.Director.maxCars = 99, 99
    A.Director.renderCooldownUntilMs = 0
    local tryOk = A.Director.tryRender(unCaravan, { { x = 20, y = 100, key = "ivan", player = PLAYER } }, CLOCK)
    check("tryRender defers unloaded spawn area without incrementing renderFailures",
        tryOk == false and unCaravan.renderFailures == 0 and unCaravan.nextRenderAtMs == CLOCK + 3000)
    A.settings.renderRadius, A.Director.maxRendered, A.Director.maxCars = oldRadius, oldMaxR, oldMaxC

    -- Tuning budget fields
    local tuned = A.Spawn.applyTuning({}, 35)
    check("applyTuning sets lighter scanMs/nodesPerTick/searchBudgetMs/maxNodes",
        tuned.scanMs == 150 and tuned.nodesPerTick == 16 and tuned.searchBudgetMs == 2 and tuned.maxNodes == 2400)

    ZOMBIES = oldZombies
    p.DrivingRoute.dimensions = nil
    p.Watchdog = savedWatchdog
    p.DrivingControl = savedControl
    p.DrivingDemoClient.drive = savedDrive
    C.known = oldKnown2
    p.DrivingEscape, p.DrivingRoute.scene, p.DrivingRecovery, p.DrivingEntry = savedEscape, savedScene, savedStall, savedWalked
end
