-- v0.7.0 regression and content suite:
--   1. Crash guard stays active while braking/halted/seated and clears on exit (@melixrism)
--   2. Ballistics hits damage/kill seated NPCs through windows and trigger reactions (@farleymarley1)
--   3. Heavy tanks/armor & industrial vehicles filtered out by default (@TreeasaurusRex)
--   4. Distant pedestrians ignored beyond 14 tiles & brake-stall retry continues past 3 tries (@Orion, @MiX74P3)
--   5. Regional town economy, 5 Event Caravans, physical CaravanCargo + theft guard, and roadside field services
return function(check, newVehicle)
    local A = ALifeCaravans
    local V = A.Vehicles
    local F = A.Physics
    local C = A.Convoy
    local M = A.Market
    local E = A.Economy
    local K = A.Cargo
    local B = A.Ballistics
    local D = A.Director
    local I = A.Interact
    local L = A.Ledger

    -- 1. Heavy armor and industrial vehicle filtering (@TreeasaurusRex)
    A.settings.allowHeavyArmor = false
    V.scanned = {
        rows = {
            { name = "Base.CarNormal", seats = 4, mass = 1400, wheels = 4 },
            { name = "Base.M998", seats = 4, mass = 2600, wheels = 4 },
            { name = "Base.T90_Tank", seats = 3, mass = 46000, wheels = 6 },
            { name = "Base.BTR80_APC", seats = 8, mass = 13600, wheels = 8 },
            { name = "Base.Excavator_Heavy", seats = 2, mass = 9000, wheels = 4 },
        },
        byName = {},
    }
    for _, r in ipairs(V.scanned.rows) do V.scanned.byName[r.name] = r end
    check("tanks rejected by default for military", not V.allowedForClass("Base.T90_Tank", "military"))
    check("APC rejected by default for military", not V.allowedForClass("Base.BTR80_APC", "military"))
    check("excavators rejected by badPatterns", not V.valid("Base.Excavator_Heavy"))
    A.settings.allowHeavyArmor = true
    check("heavy armor allowed for military when setting enabled", V.allowedForClass("Base.T90_Tank", "military"))
    check("heavy armor still rejected for civilian/trade when enabled", not V.allowedForClass("Base.T90_Tank", "civilian") and not V.allowedForClass("Base.T90_Tank", "trade"))
    A.settings.allowHeavyArmor = false
    V.scan(true)
    check("elite bloc maps to police rather than military", V.classFor({ relations = { bloc = "elite" } }) == "police")

    -- 2. Crash guard stays active across DrivingEntry.seated->clear, releaseSP, and dead-occupant ejection (@melixrism / TilterWreck)
    local crashCar = newVehicle("Base.CarNormal", 140, 100)
    function crashCar:clearPassenger(seat) self.passengers[seat] = nil return true end
    local npcBody = {
        godMod = false, dead = false, knocked = true, vehicle = crashCar,
        isDead = function(self) return self.dead end,
        isGodMod = function(self) return self.godMod end,
        isKnockedDown = function(self) return self.knocked end,
        setKnockedDown = function(self, val) self.knocked = val == true end,
        getVehicle = function(self) return self.vehicle end,
        setVehicle = function(self, v) self.vehicle = v end,
        getBodyDamage = function() return nil end,
        setGodMod = function(self, val) self.godMod = val == true end,
        getModData = function() return { ProjectALifeUID = "npc_crash_1", ProjectALifeGeneration = 1 } end,
    }
    crashCar.passengers[0] = npcBody
    F.syncCrashGuard(crashCar, { { npc = npcBody, seat = 0, boarded = true } }, true)
    check("crash guard active while seated and clears knockdown state", npcBody.godMod == true and npcBody.knocked == false)

    -- Simulate ProjectALife DrivingEntry.seated(npc) calling DrivingEntry.clear(npc, true) while npc is still in crashCar
    ProjectALife.DrivingEntry = ProjectALife.DrivingEntry or {}
    ProjectALife.DrivingEntry.clear = ProjectALife.DrivingEntry.clear or function() end
    ProjectALife.DrivingEntry.seated = ProjectALife.DrivingEntry.seated or function(n) ProjectALife.DrivingEntry.clear(n, true) end
    C.hooksInstalled = false
    C.installHooks()
    ProjectALife.DrivingEntry.clear(npcBody, true)
    check("DrivingEntry.clear called while seated preserves crash guard", npcBody.godMod == true)
    npcBody.godMod = false
    ProjectALife.DrivingEntry.seated(npcBody)
    check("DrivingEntry.seated enforces crash guard on seated NPC", npcBody.godMod == true)

    -- Simulate F.releaseSP / F.syncCrashGuard(..., false) while NPC is still physically seated in crashCar
    F.syncCrashGuard(crashCar, { { npc = npcBody, seat = 0, boarded = true } }, false)
    check("releaseSP / syncCrashGuard(false) never strips crash guard while NPC remains in car", npcBody.godMod == true)

    -- Simulate TilterWreck debris killing one passenger inside crashCar while driver remains alive
    local deadPassenger = {
        godMod = true, dead = true, vehicle = crashCar,
        isDead = function(self) return self.dead end,
        isGodMod = function(self) return self.godMod end,
        getVehicle = function(self) return self.vehicle end,
        setVehicle = function(self, v) self.vehicle = v end,
        getBodyDamage = function() return nil end,
        setGodMod = function(self, val) self.godMod = val == true end,
    }
    crashCar.passengers[1] = deadPassenger
    F.syncVehicleOccupants(crashCar, true)
    check("dead bodiless passenger immediately ejected from seat and living driver keeps crash guard",
        crashCar:getCharacter(1) == nil and deadPassenger.vehicle == nil and deadPassenger.godMod == false and npcBody.godMod == true)

    -- Simulate OnTick cell vehicle guard (F.guardCellVehicles)
    npcBody.godMod = false
    F.nextCellGuardAt = 0
    F.guardCellVehicles()
    check("OnTick guardCellVehicles restores crash guard on seated bodiless occupant", npcBody.godMod == true)

    npcBody.vehicle = nil
    crashCar.passengers[0] = nil
    F.syncVehicleOccupants(crashCar, false)
    F.syncBodyCrashGuard(npcBody, crashCar, false)
    check("crash guard cleared once NPC leaves vehicle", npcBody.godMod == false)

    -- 3. Ballistics hits damage & kill seated NPCs through car windows (@farleymarley1)
    L.reset()
    local bCar = newVehicle("Base.PickUpTruck", 130, 100)
    local winCond = 100
    local doorPart = {
        getDoor = function() return { isOpen = function() return false end } end,
        findWindow = function()
            return {
                isDestroyed = function() return winCond <= 0 end,
                getCondition = function() return winCond end,
                setCondition = function(_, c) winCond = c end,
            }
        end,
    }
    bCar.getPassengerDoor = function(_, seat) return seat == 0 and doorPart or nil end
    ACTORS["b_hostile_1"] = { uid = "b_hostile_1", factionId = "f_raid", lifecycle = "active", generation = 1, revision = 1, memory = {} }
    local bShell = {
        uid = "b_hostile_1", generation = 1, x = 130, y = 100, z = 0, dead = false, health = 1.0, godMod = true, vehicle = bCar,
        getX = function(s) return s.x end, getY = function(s) return s.y end, getZ = function(s) return s.z end,
        isDead = function(s) return s.dead end, getVehicle = function(s) return s.vehicle end,
        getHealth = function(s) return s.health end, setHealth = function(s, h) s.health = h end,
        getBodyDamage = function() return nil end,
        setGodMod = function(s, v) s.godMod = v == true end,
        Kill = function(s) s.dead = true s.health = 0 ACTORS["b_hostile_1"].lifecycle = "dead" end,
        getModData = function() return { ProjectALifeUID = "b_hostile_1", ProjectALifeGeneration = 1, ProjectALifeOwned = true } end,
    }
    SHELLS["b_hostile_1"] = bShell
    bCar.passengers[0] = bShell
    local bCaravan = L.create({
        name = "Raider Squad", factionId = "f_raid", factionName = "Raider Squad", kind = "raid", class = "raider", hostile = true,
        vehicles = { "Base.PickUpTruck" }, crew = { "f_raid_p1" }, speedKmh = 35, route = { "townA", "townB" }, leg = 1, t = 0.2,
        x = 130, y = 100, state = "rendered", vehicleIds = { bCar:getId() }, actorUids = { "b_hostile_1" },
    })
    A.tagVehicle(bCar, bCaravan.id, 1)
    D.publish(true)
    PLAYER.x, PLAYER.y = 122, 100
    PLAYER.getDirectionAngle = function() return 0 end
    local aimedId = B.findAimedCaravanVehicle(PLAYER, { isRanged = function() return true end, getMaxRange = function() return 30 end, getMaxDamage = function() return 1.8 end })
    check("ballistics aim detector finds caravan vehicle in cone", aimedId == bCar:getId(), tostring(aimedId))
    B.lastShotAtMs = {}
    local okShot1, status1, rem1 = B.onShot(PLAYER, { vehicleId = bCar:getId(), damage = 1.6, ranged = true })
    check("first shot damages window and reduces seated NPC health", okShot1 and status1 == "damaged" and winCond < 100 and rem1 < 1.0, tostring(status1) .. "/" .. tostring(rem1))
    check("seated NPC retains crash guard while still alive in seat", bShell.godMod == true)
    check("shot triggers caravan combat reaction", bCaravan.state == "fighting")
    B.lastShotAtMs = {}
    local okShot2, status2 = B.onShot(PLAYER, { vehicleId = bCar:getId(), damage = 3.5, ranged = true })
    check("lethal shot kills seated NPC and clears crash guard", okShot2 and status2 == "killed" and bShell.dead == true and bShell.godMod == false, tostring(status2))

    -- 4. Distant pedestrian filter in C.fastScene (@MiX74P3 / @Orion)
    C.bodyCache = nil
    local leadCar = newVehicle("Base.CarNormal", 100, 100)
    SHELLS["far_ped"] = {
        uid = "far_ped", generation = 1, x = 135, y = 100, z = 0, dead = false,
        getX = function(s) return s.x end, getY = function(s) return s.y end, getZ = function(s) return s.z end,
        isDead = function() return false end, getVehicle = function() return nil end,
        getModData = function() return { ProjectALifeOwned = true, ProjectALifeUID = "far_ped" } end,
    }
    ProjectALife.Watchdog = { bindings = { { shell = SHELLS["far_ped"] } } }
    ProjectALife.DrivingRoute.dimensions = function() return 0.9, 2.1 end
    local fast = C.fastScene(leadCar, {}, leadCar:getId(), { caravanId = "c_test" })
    local farFound = false
    for _, b in ipairs(fast.bodies or {}) do
        if b.label == "A-Life NPC" and math.abs(b.x - 135) < 1 then farFound = true end
    end
    check("distant 35-tile pedestrian excluded from driving obstacle scene", not farFound)
    ProjectALife.Watchdog = nil

    -- 5. Regional town economy & Event Caravans & Cargo & Field Services
    A.settings.economyEnabled = true
    A.settings.caravanCargo = true
    A.settings.fieldServices = true
    local townA = E.ensureTown("townA")
    local townB = E.ensureTown("townB")
    townA.supplies.medical = 20
    townB.supplies.medical = 2
    local mSnap = E.marketFor(ProjectALife.RoadGraph, "townB")
    check("economy snapshot detects town shortage", mSnap ~= nil and mSnap.shortage == "medical" and mSnap.tiers.medical == "scarce")
    local baseBuy = A.Trade.buyPrice("Base.Bandage", "trade")
    local scarceBuy = A.Trade.buyPrice("Base.Bandage", "trade", { market = mSnap, favor = 0 })
    local scarceSell = A.Trade.sellPrice({ item = "Base.Bandage", value = 10 }, "trade", 0, { market = mSnap })
    check("caravan bound for medical shortage pays higher buy credit", scarceBuy > baseBuy and scarceBuy < scarceSell, scarceBuy .. " vs " .. baseBuy)

    local fairStock = M.stockForCaravan("trade", "trade_fair")
    check("trade_fair event caravan generates rich stock", #fairStock >= 5)

    local ecoCaravan = L.create({
        name = "Relief Traders", factionId = "f_army", factionName = "Relief Traders",
        kind = "rescue", class = "rescue", hostile = false, eventType = "medical_aid",
        vehicles = { "Base.StepVan" }, crew = { "f_army_p1", "f_army_p2" }, speedKmh = 35,
        route = { "townA", "townB" }, leg = 1, t = 0.5, x = 120, y = 100, trip = 1, trips = 0,
        state = "rendered", vehicleIds = {}, actorUids = { "u_med_1" }, stock = {},
    })
    ACTORS["u_med_1"] = { uid = "u_med_1", factionId = "f_army", lifecycle = "active", generation = 1, revision = 1, memory = {} }
    SHELLS["u_med_1"] = {
        uid = "u_med_1", generation = 1, x = 120, y = 100, z = 0, dead = false,
        getX = function(s) return s.x end, getY = function(s) return s.y end, getZ = function(s) return s.z end,
        isDead = function() return false end,
        getModData = function() return { ProjectALifeUID = "u_med_1", ProjectALifeGeneration = 1 } end,
    }
    D.refreshStock(ecoCaravan)
    E.prepareTrip(ProjectALife.RoadGraph, ecoCaravan)
    check("prepareTrip attaches market and medical shipment", ecoCaravan.market ~= nil and ecoCaravan.market.shortage == "medical")

    -- Populate physical trunk cargo and test theft detection
    local van = newVehicle("Base.StepVan", 120, 100)
    local trunkItems = {}
    local trunkInv = {
        AddItem = function(_, fullType)
            local item = {
                type = fullType,
                getFullType = function() return fullType end,
                getDisplayName = function() return fullType end,
            }
            trunkItems[#trunkItems + 1] = item
            return item
        end,
        Remove = function(_, target)
            for i = #trunkItems, 1, -1 do
                if trunkItems[i] == target then table.remove(trunkItems, i) break end
            end
        end,
        getItems = function()
            return {
                size = function() return #trunkItems end,
                get = function(_, idx) return trunkItems[idx + 1] end,
            }
        end,
    }
    local trunkPart = { getItemContainer = function() return trunkInv end }
    van.getPartById = function(_, partId)
        if partId == "TruckBed" or partId == "Trunk" then return trunkPart end
        if partId == "GasTank" then return { getContainerContentAmount = function() return 0.2 end, getContainerCapacity = function() return 40 end, setContainerContentAmount = function(_, v) van.fuel = v end } end
        if partId == "Engine" then return { getCondition = function() return 40 end, setCondition = function(_, v) van.engineCond = v end } end
        return nil
    end
    A.tagVehicle(van, ecoCaravan.id, 1)
    ecoCaravan.vehicleIds = { van:getId() }
    local popCount = K.populateCar(van, ecoCaravan, 1)
    check("physical trunk cargo populated on spawn", popCount > 0 and trunkInv:getItems():size() == popCount, tostring(popCount))
    PLAYER.x, PLAYER.y = 121, 100
    trunkInv:Remove(trunkInv:getItems():get(0))
    local lostBefore = A.metrics.lostCargo or 0
    local theftDetected = K.checkTheft(ecoCaravan, { { id = van:getId(), x = 120, y = 100, vehicle = van } }, D.playerRows())
    check("unauthorized trunk looting detected and penalized", theftDetected == true and (A.metrics.lostCargo or 0) > lostBefore)
    ecoCaravan.angry = nil
    STANCE.f_army = "friendly"

    -- Test roadside repair assistance, field first aid, supply donation, vehicle service, and road intel
    local pinv = PLAYER:getInventory()
    ecoCaravan.halted = true
    ecoCaravan.haltReason = "roadside_inspection"
    pinv:AddItem("Base.Wrench")
    local cashBefore = pinv:getCountTypeRecurse("Base.Money")
    local repOk = K.assistRepair(ecoCaravan, PLAYER, van:getId())
    check("roadside repair assistance pays cash, adds favor, and resumes inspection halt", repOk == true and pinv:getCountTypeRecurse("Base.Money") > cashBefore and ecoCaravan.halted == nil)

    ecoCaravan.halted = true
    local bandBefore = pinv:getCountTypeRecurse("Base.Bandage")
    local aidOk = K.fieldFirstAid(ecoCaravan, PLAYER, van:getId())
    check("field first aid treats friendly player and provides bandages", aidOk == true and pinv:getCountTypeRecurse("Base.Bandage") >= bandBefore + 2)

    pinv:AddItem("Base.TinnedBeans")
    local favBefore = L.favor("ivan", "f_army")
    local donOk = K.donateSupplies(ecoCaravan, PLAYER, van:getId())
    check("supply donation consumes food/meds and boosts faction favor", donOk == true and L.favor("ivan", "f_army") >= favBefore + 2)

    local playerCar = newVehicle("Base.CarNormal", 124, 100)
    local pFuel = 5
    playerCar.getPartById = function(_, id)
        if id == "GasTank" then
            return {
                getContainerCapacity = function() return 40 end,
                getContainerContentAmount = function() return pFuel end,
                setContainerContentAmount = function(_, v) pFuel = v end,
            }
        end
        return nil
    end
    local vsOk = K.servicePlayerVehicle(ecoCaravan, PLAYER, van:getId())
    check("roadside vehicle service tops up player's nearby car fuel", vsOk == true and pFuel > 5, tostring(pFuel))

    local intelOk = K.requestIntel(ecoCaravan, PLAYER, van:getId())
    check("road intel service succeeds", intelOk == true)

    -- Arrival settlement into destination town economy
    local medBefore = townB.supplies.medical
    local settled, added = E.settleArrival(ProjectALife.RoadGraph, ecoCaravan)
    check("arrival settles remaining cargo into destination town supply once", settled == true and added > 0 and townB.supplies.medical > medBefore)
    local settledDup = E.settleArrival(ProjectALife.RoadGraph, ecoCaravan)
    check("duplicate arrival settlement is idempotent", settledDup == false)

    -- 6. v0.7.2: Armored KI5 vehicle spawn chance & TrophyVehicleCondition post-defeat wear (@PriestSmokey)
    V.scanned = {
        rows = {
            { name = "Base.92amgeneralM998", seats = 4, mass = 3500, wheels = 4 },
            { name = "Base.StepVan_SWAT_Armored", seats = 6, mass = 4800, wheels = 4 },
            { name = "Base.PickUpTruck", seats = 2, mass = 2100, wheels = 4 },
            { name = "Base.OffRoad", seats = 2, mass = 1900, wheels = 4 },
            { name = "Base.CarNormal", seats = 4, mass = 1600, wheels = 4 },
        },
        byName = {},
    }
    for _, r in ipairs(V.scanned.rows) do V.scanned.byName[r.name] = r end
    check("KI5 M998 and SWAT Armored recognized as armored vehicles", V.isArmoredVehicle("Base.92amgeneralM998", 3500) and V.isArmoredVehicle("Base.StepVan_SWAT_Armored", 4800))
    check("ordinary pickup and sedan are not classified as armored", not V.isArmoredVehicle("Base.PickUpTruck", 2100) and not V.isArmoredVehicle("Base.CarNormal", 1600))
    A.settings.armoredVehicleChance = 0
    check("ArmoredVehicleChance=0 blocks armored vehicles in allowedForClass", not V.allowedForClass("Base.92amgeneralM998", "military") and V.allowedForClass("Base.PickUpTruck", "military"))
    local pickedZero = V.pick("military", 0.05)
    check("ArmoredVehicleChance=0 picks unarmored fallback for military convoy", pickedZero ~= nil and not V.isArmoredVehicle(pickedZero, 2000), tostring(pickedZero))
    A.settings.armoredVehicleChance = 100
    check("ArmoredVehicleChance=100 allows armored vehicles", V.allowedForClass("Base.92amgeneralM998", "military"))
    A.settings.armoredVehicleChance = 25
    V.scan(true)

    -- TrophyVehicleCondition post-defeat wear on armored KI5 car
    A.settings.trophyVehicleCondition = 40
    local ki5Car = newVehicle("Base.92amgeneralM998", 140, 100)
    local partConds = { Engine = 100, Battery = 100, TireFrontLeft = 95, DoorFrontLeft = 90 }
    local partIds = { "Engine", "Battery", "TireFrontLeft", "DoorFrontLeft" }
    local batDelta = 1.0
    local tankFuel = 50.0
    ki5Car.getScript = function() return { getFullName = function() return "Base.92amgeneralM998" end } end
    ki5Car.getPartCount = function() return #partIds end
    ki5Car.getPartByIndex = function(_, idx)
        local pid = partIds[idx + 1]
        return {
            getId = function() return pid end,
            getCondition = function() return partConds[pid] end,
            setCondition = function(_, c) partConds[pid] = c end,
            getInventoryItem = function()
                return {
                    setCondition = function(_, c) partConds[pid] = c end,
                    getUsedDelta = function() return batDelta end,
                    setUsedDelta = function(_, d) batDelta = d end,
                }
            end,
        }
    end
    ki5Car.getPartById = function(_, pid)
        if pid == "GasTank" then
            return {
                getContainerCapacity = function() return 60.0 end,
                getContainerContentAmount = function() return tankFuel end,
                setContainerContentAmount = function(_, f) tankFuel = f end,
            }
        end
        return nil
    end
    local wore = A.Lifecycle.applyDefeatWear(ki5Car, ecoCaravan)
    check("applyDefeatWear degrades defeated armored car parts and fuel below TrophyVehicleCondition cap",
        wore == true and partConds.Engine <= 30 and partConds.TireFrontLeft <= 30 and tankFuel <= 15.0 and batDelta <= 0.35,
        string.format("eng=%s tire=%s fuel=%s", tostring(partConds.Engine), tostring(partConds.TireFrontLeft), tostring(tankFuel)))
    local woreAgain = A.Lifecycle.applyDefeatWear(ki5Car, ecoCaravan)
    check("applyDefeatWear is idempotent per vehicle", woreAgain == false)

    -- 7. v0.7.2: Multi-vehicle convoy per-car crew ownership & formation boarding guard (@PriestSmokey)
    local convCar1 = newVehicle("Base.PickUpTruck", 150, 100)
    local convCar2 = newVehicle("Base.VanSeats", 142, 100)
    for _, u in ipairs({ "c1_drv", "c1_pas", "c2_drv", "c2_pas" }) do
        ACTORS[u] = { uid = u, factionId = "f_army", lifecycle = "active", generation = 1, revision = 1, memory = {} }
        local sx = (u == "c1_drv" or u == "c1_pas") and 150 or 142
        SHELLS[u] = {
            uid = u, generation = 1, x = sx, y = 100, z = 0, dead = false, vehicle = nil,
            getX = function(s) return s.x end, getY = function(s) return s.y end, getZ = function(s) return s.z end,
            isDead = function(s) return s.dead end, getVehicle = function(s) return s.vehicle end,
            getModData = function() return { ProjectALifeUID = u, ProjectALifeGeneration = 1, ProjectALifeOwned = true } end,
        }
    end
    local multiCaravan = L.create({
        name = "Two Car Convoy", factionId = "f_army", factionName = "Two Car Convoy",
        kind = "convoy", class = "military", hostile = false,
        vehicles = { "Base.PickUpTruck", "Base.VanSeats" }, crew = { "p1", "p2", "p3", "p4" },
        speedKmh = 35, route = { "townA", "townB" }, leg = 1, t = 0.3, x = 150, y = 100,
        goals = { { x = 220, y = 100 }, { x = 260, y = 100 } }, goalIndex = 1,
        state = "rendered", vehicleIds = { convCar1:getId(), convCar2:getId() },
        actorUids = { "c1_drv", "c1_pas", "c2_drv", "c2_pas" },
    })
    A.tagVehicle(convCar1, multiCaravan.id, 1)
    A.tagVehicle(convCar2, multiCaravan.id, 2)
    A.Spawn.rememberCarCrew(multiCaravan, convCar1:getId(), { { uid = "c1_drv" }, { uid = "c1_pas" } })
    A.Spawn.rememberCarCrew(multiCaravan, convCar2:getId(), { { uid = "c2_drv" }, { uid = "c2_pas" } })
    -- Even when Car 2 recrews alone with 4 seats while Car 1's crew is on foot, Car 2 must NOT steal Car 1's crew!
    local reserved = {}
    local okRecrew2, count2 = A.Spawn.recrew(multiCaravan, convCar2:getId(), { { x = 160, y = 100 }, { x = 190, y = 100 } }, 4, reserved)
    check("Car 2 recrews only its own 2 crew members and never steals Car 1's crew",
        okRecrew2 == true and count2 == 2 and reserved["c2_drv"] == true and reserved["c2_pas"] == true
        and not reserved["c1_drv"] and not reserved["c1_pas"], tostring(count2))
    local okRecrew1, count1 = A.Spawn.recrew(multiCaravan, convCar1:getId(), { { x = 165, y = 100 }, { x = 195, y = 100 } }, 4, reserved)
    check("Car 1 retains and recrews its own 2 crew members without being left behind",
        okRecrew1 == true and count1 == 2 and reserved["c1_drv"] == true and reserved["c1_pas"] == true, tostring(count1))

    -- Formation speed holds 0 while another car in the same convoy is boarding/exiting
    local grp = {
        { id = convCar1:getId(), entry = { speedKmh = 35 }, s = { phase = "approach" }, x = 150, y = 100, index = 1 },
        { id = convCar2:getId(), entry = { speedKmh = 35 }, s = { phase = "driving" }, x = 130, y = 100, index = 2 },
    }
    local fCruise, _, fFactor = C.formationSpeed(grp, 2)
    check("follower car holds speed=0 while lead car crew is boarding/exiting", fCruise == 0 and fFactor == 0)

    -- VehicleRules.strike hook prevents caravan car from running over caravan NPC on foot
    local struck = false
    ProjectALife.VehicleRules = {
        strike = function() struck = true return true end,
    }
    C.hooksInstalled = false
    C.installHooks()
    C.known[convCar2:getId()] = { caravanId = multiCaravan.id, index = 2 }
    local hitRes = ProjectALife.VehicleRules.strike(SHELLS["c1_drv"], convCar2, 35, A.now())
    check("VehicleRules.strike hook blocks caravan car from killing caravan NPC on foot", hitRes == false and struck == false)

    -- Per-car dismount objective keeps Car 1 crew at Car 1 (150,100) and Car 2 crew at Car 2 (142,100)
    multiCaravan.state = "rendered"
    multiCaravan.ambush = nil
    A.Spawn.dismount(multiCaravan, { x = 142, y = 100 })
    local obj1 = ACTORS["c1_drv"].memory.arrivalObjective
    local obj2 = ACTORS["c2_drv"].memory.arrivalObjective
    check("non-combat dismount keeps Car 1 crew objective at Car 1 instead of walking to Car 2",
        obj1 ~= nil and math.abs(obj1.x - 150) < 0.1 and obj2 ~= nil and math.abs(obj2.x - 142) < 0.1,
        string.format("obj1=%s obj2=%s", tostring(obj1 and obj1.x), tostring(obj2 and obj2.x)))
end
