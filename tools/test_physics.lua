return function(check)
    local A = ALifeCaravans
    local saved = {
        client = isClient, server = isServer, player = getSpecificPlayer,
        known = A.Convoy.known, session = A.Convoy.sessionFor, members = ProjectALife.DrivingDemo.members,
        spVehicles = A.Physics.spVehicles, spLeases = A.Physics.spLeases,
        drivingRiders = ProjectALife.DrivingRiders,
    }
    local entry, physicsUpdates = {}, 0
    local v = {
        id = 991, force = 80, localPhysics = true, speed = 0, engine = true, owner = 37,
        regulator = false, regulatorSpeed = 0, quality = 100, loudness = 90, power = 420,
        rpm = 950, stoplights = true, braking = true, square = {}, controller = {},
        physicsActive = false, chunkChecks = 0, wakeCalls = 0, chunksReady = true,
        x = 100, y = 100, z = 0,
    }
    function v.controller.park()
        if v.failPhysics then error("test physics error") end
        assert(v.force == 0, "park() must see zeroed brake")
        physicsUpdates = physicsUpdates + 1
    end
    local driver = { x = 101, y = 100, z = 0, onlineId = 14, data = { ProjectALifeUID = "brake-driver", ProjectALifeGeneration = 1 } }
    local rider = { x = 101, y = 101, z = 0, onlineId = 15, data = { ProjectALifeUID = "brake-rider", ProjectALifeGeneration = 1 } }
    local function body(n)
        function n:getVehicle() return self.vehicle end
        function n:isDead() return self.dead == true end
        function n:getModData() return self.data end
        function n:getOnlineID() return self.onlineId or -1 end
    function n:getBodyDamage() return self.bodyDamage end
    function n:getMoodles() return self.moodles end
    function n:setGodMod(g, force) self.godArgs = { g = g, force = force } end
        function n:getX() return self.x or 0 end
        function n:getY() return self.y or 0 end
        function n:getZ() return self.z or 0 end
        n.vehicle = v
    end
    driver.bodyDamage = nil  -- bodiless crew member, needs the crash guard
    rider.bodyDamage = {}
    body(driver); body(rider)
    v.seats = { [0] = driver, [1] = rider }
    function v:getId() return self.id end
    function v:getX() return self.x end
    function v:getY() return self.y end
    function v:getZ() return self.z end
    function v:getSquare() return self.square end
    function v:getBrakingForce() return self.force end
    function v:setBrakingForce(f) self.force = f end
    function v:isBraking() return self.braking end
    function v:setBraking(b) self.braking = b end
    function v:isRegulator() return self.regulator end
    function v:setRegulator(r) self.regulator = r end
    function v:getRegulatorSpeed() return self.regulatorSpeed end
    function v:setRegulatorSpeed(rs) self.regulatorSpeed = rs end
    function v:getEngineQuality() return self.quality end
    function v:getEngineLoudness() return self.loudness end
    function v:getEnginePower() return self.power end
    function v:setEngineFeature(q, l, p) self.quality, self.loudness, self.power = q, l, p end
    function v:getEngineSpeed() return self.rpm end
    function v:setEngineSpeed(r) self.rpm = r end
    function v:getStoplightsOn() return self.stoplights end
    function v:setStoplightsOn(on) self.stoplights = on end
    function v:isLocalPhysicSim() return self.localPhysics end
    function v:getCurrentSpeedKmHour() return self.speed end
    function v:isEngineRunning() return self.engine end
    function v:getDriver() return self.seats[0] end
    function v:getCharacter(i) return self.seats[i] end
    function v:getMaxPassengers() return 2 end
    function v:getNetPlayerId() return self.owner end
    function v:getController() return self.controller end
    function v:getVehicleTowing() return self.towing end
    function v:getVehicleTowedBy() return self.towed end
    function v:clearPassenger(seat) self.seats[seat] = nil return true end
    function v:enterRSync(seat, chr, veh) self.seats[seat] = chr chr.vehicle = veh return true end
    function v:setCharacterPosition() end
    local parkUpdates = 0
    function v:updatePhysics()
        if self.failPhysics then error("test physics error") end
        assert(self.seats[0] == nil or self.seats[0]:getMoodles() ~= nil, "bodiless driver must be unseated during updatePhysics")
        if self.regulator == false and self.regulatorSpeed == 0 then
            parkUpdates = parkUpdates + 1
            return
        end
        assert(self.force == 0 and self.power == 0 and self.regulator == true and self.regulatorSpeed > 0)
        physicsUpdates = physicsUpdates + 1
    end
    local s = { vehicle = v, npc = driver, phase = "driving", entryComplete = true, boarded = true, uid = "brake-driver", generation = 1 }
    local m = { npc = rider, seat = 1, boarded = true, uid = "brake-rider", generation = 1 }
    A.Convoy.known = { [991] = entry }
    A.Convoy.sessionFor = function() return s end
    ProjectALife.DrivingDemo.members = function() return { s, m } end
    isClient = function() return true end
    isServer = function() return false end
    getSpecificPlayer = function() return { getOnlineID = function() return 37 end } end
    local function attempt() s.alcBrakeReleased = nil return A.Physics.prepare(s, entry) end
    check("verified local NPC drive clears native park brake in pure Lua",
        attempt() and physicsUpdates == 1 and v.force == 80 and v.power == 420 and v.regulator == false and v.stoplights == true)
    v.isInvalidChunkAhead = function() return true end
    v.isInvalidChunkBehind = function() return true end
    check("unloaded distant chunk ahead/behind does not block local brake release",
        attempt() and physicsUpdates == 2)
    v.isInvalidChunkAhead, v.isInvalidChunkBehind = nil, nil
    physicsUpdates = 1
    check("same drive does not repeatedly alter controller", not A.Physics.prepare(s, entry) and physicsUpdates == 1)
    entry.halted = true; check("halt never releases brakes", not attempt()); entry.halted = nil
    s.braking = true; check("braking session untouched", not attempt()); s.braking = nil
    s.entryComplete = false; check("incomplete boarding untouched", not attempt()); s.entryComplete = true
    m.boarded = false; check("unboarded passenger blocks release", not attempt()); m.boarded = true
    rider.data.ProjectALifeGeneration = 2
    check("stale passenger generation blocks release", not attempt())
    rider.data.ProjectALifeGeneration = 1
    rider.vehicle = nil; check("passenger must really be seated", not attempt()); rider.vehicle = v
    v.localPhysics = false; check("remote physics never modified", not attempt()); v.localPhysics = true
    v.owner = 99; check("different physics owner untouched", not attempt()); v.owner = 37
    v.speed = 4; check("moving vehicle never reset", not attempt()); v.speed = 0
    v.engine = false; check("stopped engine untouched", not attempt()); v.engine = true
    v.seats[1] = { __class = "IsoPlayer" }; check("player passenger prevents reset", not attempt()); v.seats[1] = rider
    driver.__class = "IsoPlayer"; check("player driver never controlled", not attempt()); driver.__class = nil
    A.Convoy.known = {}; check("non-caravan vehicle untouched", not attempt()); A.Convoy.known = { [991] = entry }
    A.Convoy.sessionFor = function() return {} end
    check("stale driving session untouched", not attempt()); A.Convoy.sessionFor = function() return s end
    isServer = function() return true end
    check("dedicated server never changes local physics", not attempt()); isServer = function() return false end
    local savedUpdate = v.updatePhysics; v.updatePhysics = nil
    check("missing updatePhysics declines without latch", not attempt() and not s.alcBrakeError)
    v.updatePhysics = savedUpdate
    s.phase = "seated"; s.alcBrakeReleased = true
    check("parked session clears regulator gas state and rearms next drive",
        not A.Physics.prepare(s, entry) and not s.alcBrakeReleased and parkUpdates == 1 and v.seats[0] == driver)
    s.phase = "driving"
    v.failPhysics = true
    check("updatePhysics failure restores brake and engine specs",
        not attempt() and v.force == 80 and v.power == 420 and v.regulator == false and s.alcBrakeError)
    v.failPhysics = nil
    check("failed brake release not retried every tick", not attempt() and physicsUpdates == 1)

    -- Pure-Lua SP authorizationChanged + wakeSP checks
    local acquired, released = 0, 0
    A.Physics.spVehicles = {}
    A.Physics.spLeases = {}
    entry.caravanId = "physics-test"
    v.data = { [A.MODDATA_ID] = entry.caravanId }
    function v:getModData() return self.data end
    function v:isSeatInstalled(seat) return seat >= 0 and seat < 2 end
    function v:authorizationChanged(who)
        if self.failAuth then error("auth error") end
        if who ~= nil then
            acquired = acquired + 1
            self.localPhysics = true
            self.owner = who:getOnlineID()
        else
            released = released + 1
            self.localPhysics = false
            self.owner = -1
        end
    end
    function v:isPhysicsActive() return self.physicsActive end
    function v:checkSurroundingChunks()
        self.chunkChecks = self.chunkChecks + 1
        if not self.chunksReady then self.physicsActive = false end
    end
    function v:setPhysicsActive(wanted)
        self.wakeCalls = self.wakeCalls + 1
        self.physicsActive = wanted == true and self.chunksReady == true
    end
    check("SP adapter cannot grant MP authority", not A.Physics.ensureSP(s, entry) and acquired == 0)
    isClient = function() return false end
    isServer = function() return true end
    check("SP adapter cannot grant dedicated-server authority", not A.Physics.ensureSP(s, entry) and acquired == 0)
    isServer = function() return false end
    s.phase, s.entryComplete, s.boarded, s.alcBrakeError, s.boardPrepared = "approach", false, false, nil, true
    m.boarded = false
    driver.vehicle, rider.vehicle = nil, nil
    v.seats, v.localPhysics, v.owner = {}, false, -1
    check("SP approaching crew gains local simulation and resets premature boardPrepared",
        not A.Physics.prepare(s, entry) and acquired == 1 and v.localPhysics and A.Physics.spVehicles[v] == s and s.boardPrepared == nil)
    check("SP approach does not wake a parked physical body", v.wakeCalls == 0)
    driver.data.ProjectALifeUID = "wrong"
    check("SP adapter rejects stale actor UID and releases lease",
        not A.Physics.ensureSP(s, entry) and released == 1 and not A.Physics.spVehicles[v] and not v.localPhysics)
    driver.data.ProjectALifeUID = s.uid
    rider.data.ProjectALifeGeneration = 2
    check("SP adapter checks every passenger generation", not A.Physics.ensureSP(s, entry) and acquired == 1)
    rider.data.ProjectALifeGeneration = 1
    m.seat = 0
    check("SP adapter refuses duplicate seat assignments", not A.Physics.ensureSP(s, entry)); m.seat = 1
    m.npc = driver
    check("SP adapter refuses duplicate body assignments", not A.Physics.ensureSP(s, entry)); m.npc = rider
    m.seat = 4
    check("SP adapter refuses out-of-range seats", not A.Physics.ensureSP(s, entry)); m.seat = 1
    v.seats[0] = {}
    check("SP adapter refuses a foreign driver", not A.Physics.ensureSP(s, entry)); v.seats[0] = nil
    rider.vehicle = {}
    check("SP adapter never steals a rider from another car", not A.Physics.ensureSP(s, entry)); rider.vehicle = nil
    m.boarded = true
    check("SP adapter requires real seats for claimed boarded members", not A.Physics.ensureSP(s, entry)); m.boarded = false
    v.data[A.MODDATA_ID] = "foreign"
    check("SP adapter requires authoritative caravan tag", not A.Physics.ensureSP(s, entry)); v.data[A.MODDATA_ID] = entry.caravanId
    A.Convoy.sessionFor = function() return {} end
    check("SP adapter rejects a stale session", not A.Physics.ensureSP(s, entry)); A.Convoy.sessionFor = function() return s end
    driver.dead = true
    check("SP adapter rejects a dead driver", not A.Physics.ensureSP(s, entry)); driver.dead = nil
    v.seats[1] = { __class = "IsoPlayer" }
    check("SP adapter does not control player-occupied vehicles", not A.Physics.ensureSP(s, entry)); v.seats[1] = nil
    ProjectALife.DrivingDemo.members = function() return {} end
    check("SP adapter requires nonempty crew", not A.Physics.ensureSP(s, entry))
    ProjectALife.DrivingDemo.members = function() return { s, m } end
    local authFn = v.authorizationChanged; v.authorizationChanged = nil
    check("SP adapter missing authorizationChanged leaves physics alone", not A.Physics.ensureSP(s, entry))
    v.authorizationChanged = authFn
    check("valid SP session can reacquire after corrected identity", A.Physics.ensureSP(s, entry) and acquired == 2)
    A.Convoy.known = {}
    A.Physics.sweepSP()
    check("known-car removal releases SP lease", not A.Physics.spVehicles[v] and not v.localPhysics)
    A.Convoy.known = { [991] = entry }
    A.Physics.ensureSP(s, entry)
    A.Convoy.sessionFor = function() return {} end
    A.Physics.sweepSP()
    check("session replacement releases SP lease", not A.Physics.spVehicles[v] and not v.localPhysics)
    A.Convoy.sessionFor = function() return s end
    local passenger = { __class = "IsoPlayer", getVehicle = function() return v end }
    function v:getMaxPassengers() return 3 end
    function v:isSeatInstalled(seat) return seat >= 0 and seat < 3 end
    v.seats[2] = passenger
    ProjectALife.DrivingRiders = { allowed = function() return false end }
    check("uninvited passenger blocks SP adapter", not A.Physics.ensureSP(s, entry))
    ProjectALife.DrivingRiders.allowed = function() return true end
    check("invited unreserved player passenger permits SP NPC drive", A.Physics.ensureSP(s, entry))
    A.Physics.sweepSP()
    check("SP sweep preserves lease with approved hitchhiker", A.Physics.spVehicles[v] == s)
    v.seats[0] = passenger
    check("rider permission never allows player driver control", not A.Physics.ensureSP(s, entry)); v.seats[0] = nil
    s.phase, s.entryComplete, s.boarded = "driving", true, true
    m.boarded = true
    driver.vehicle, rider.vehicle = v, v
    v.seats[0], v.seats[1] = driver, rider
    check("invited hitchhiker permits parked-brake release", attempt() and physicsUpdates == 2 and v.force == 80)
    check("SP real seated driving crew requests vanilla wake", v.physicsActive == true and v.wakeCalls >= 1)
    check("bodiless driver gets forced godMod crash guard while driving", driver.godArgs and driver.godArgs.g == true and driver.godArgs.force == true)
    check("embodied rider left without crash guard", rider.godArgs == nil)
    local wakes = v.wakeCalls
    A.Physics.ensureSP(s, entry)
    check("active driving body is not repeatedly reset", v.wakeCalls == wakes)
    entry.halted = true; A.Physics.ensureSP(s, entry)
    check("SP halted crew clears wake state", s.alcWokeSP == nil); entry.halted = nil
    s.braking = true; A.Physics.ensureSP(s, entry)
    check("SP braking crew does not wake physics", s.alcWokeSP == nil); s.braking = nil
    s.exitRequested = true; A.Physics.ensureSP(s, entry)
    check("SP exiting crew does not wake physics", s.alcWokeSP == nil); s.exitRequested = nil
    m.boarded = false; A.Physics.ensureSP(s, entry)
    check("SP incomplete crew does not wake physics", s.alcWokeSP == nil); m.boarded = true
    v.seats[0] = passenger
    check("invited hitchhiker cannot take NPC driver seat", not attempt()); v.seats[0] = driver
    v.seats[2] = nil
    ProjectALife.DrivingRiders = saved.drivingRiders
    v.localPhysics, v.owner, v.failAuth = false, -1, true
    check("SP authorization error fails closed", not A.Physics.ensureSP(s, entry) and s.alcSPError)
    v.failAuth = nil
    local before = acquired
    check("SP exception is latched per session", not A.Physics.ensureSP(s, entry) and acquired == before)

    A.Physics.spVehicles, A.Physics.spLeases = saved.spVehicles, saved.spLeases
    isClient, isServer, getSpecificPlayer = saved.client, saved.server, saved.player
    A.Convoy.known, A.Convoy.sessionFor = saved.known, saved.session
    ProjectALife.DrivingDemo.members = saved.members
end
