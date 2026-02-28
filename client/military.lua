--[[
    client/military.lua — Military Convoy Client
    Free Trucking — QBX Framework

    Handles convoy escort NPC spawning, formation monitoring,
    breach detection, and escort AI behavior for military contracts.

    Section 26 of the Development Guide.
]]

-- ═══════════════════════════════════════════════════════════════
-- STATE
-- ═══════════════════════════════════════════════════════════════

local convoyActive     = false    -- convoy is currently active
local convoyLoadId     = nil      -- active load ID for this convoy
local convoyRoute      = nil      -- route waypoints from server

-- Escort vehicles and peds
local leadVehicle      = nil      -- lead escort vehicle handle
local trailVehicle     = nil      -- trail escort vehicle handle
local leadDriver       = nil      -- lead escort driver ped
local trailDriver      = nil      -- trail escort driver ped
local leadGunner       = nil      -- lead escort gunner ped
local trailGunner      = nil      -- trail escort gunner ped

-- Escort blips
local leadBlip         = nil
local trailBlip        = nil

-- Formation tracking
local playerStopped         = false     -- player vehicle is stationary
local playerStopTimer       = 0         -- GetGameTimer() when stop began
local escortsInvestigating  = false     -- escorts are checking on player
local leadDestroyed         = false
local trailDestroyed        = false
local unguardedTimer        = 0         -- GetGameTimer() when both escorts destroyed
local unguardedNotified     = false     -- player has been warned

-- Config references
local ESCORT_MODEL         = `patriot`         -- Military Patriot
local ESCORT_DRIVER_MODEL  = `s_m_y_marine_01` -- Military marine ped
local ESCORT_GUNNER_MODEL  = `s_m_y_marine_02` -- Military marine ped variant
local ESCORT_WEAPON        = `WEAPON_CARBINERIFLE`
local CONVOY_SPEED         = 25.0              -- m/s (~56 mph, fixed speed)
local FORMATION_CHECK_MS   = 1000              -- ms between formation checks
local BREACH_CHECK_MS      = 500               -- ms between breach checks
local PURSUE_MAX_DIST      = 500.0             -- meters from cargo before stopping pursuit
local INVESTIGATE_DELAY_MS = 60000             -- 60 seconds stopped before investigation
local UNGUARDED_DURATION   = 90000             -- 90 seconds unguarded window
local ESCORT_OFFSET_LEAD   = 25.0              -- meters ahead of player
local ESCORT_OFFSET_TRAIL  = 25.0              -- meters behind player

-- ═══════════════════════════════════════════════════════════════
-- VEHICLE AND PED SPAWNING
-- ═══════════════════════════════════════════════════════════════

--- Spawn a military escort vehicle with armed NPCs.
---@param coords vector3 Spawn position
---@param heading number Vehicle heading
---@param isLead boolean True for lead, false for trail
---@return number|nil vehicle Vehicle handle
---@return number|nil driver Driver ped handle
---@return number|nil gunner Gunner ped handle
local function SpawnEscortVehicle(coords, heading, isLead)
    lib.requestModel(ESCORT_MODEL)
    lib.requestModel(ESCORT_DRIVER_MODEL)
    lib.requestModel(ESCORT_GUNNER_MODEL)

    local vehicle = CreateVehicle(ESCORT_MODEL, coords.x, coords.y, coords.z, heading, true, false)
    if not DoesEntityExist(vehicle) then
        SetModelAsNoLongerNeeded(ESCORT_MODEL)
        SetModelAsNoLongerNeeded(ESCORT_DRIVER_MODEL)
        SetModelAsNoLongerNeeded(ESCORT_GUNNER_MODEL)
        return nil, nil, nil
    end

    -- Military appearance
    SetVehicleColours(vehicle, 69, 69)      -- matte dark green
    SetVehicleNumberPlateText(vehicle, isLead and 'MILESC1' or 'MILESC2')
    SetVehicleEngineOn(vehicle, true, true, false)
    SetEntityInvincible(vehicle, false)

    -- Spawn driver
    local driver = CreatePedInsideVehicle(vehicle, 4, ESCORT_DRIVER_MODEL, -1, true, false)
    if DoesEntityExist(driver) then
        SetPedArmour(driver, 200)
        SetPedAccuracy(driver, 70)
        SetPedCombatAbility(driver, 2)       -- professional
        SetPedCombatRange(driver, 2)         -- far
        SetPedCombatAttributes(driver, 46, true)
        SetPedCombatAttributes(driver, 5, true)  -- can fight armed peds on foot
        SetPedKeepTask(driver, true)
        GiveWeaponToPed(driver, ESCORT_WEAPON, 500, false, true)
        SetBlockingOfNonTemporaryEvents(driver, true)
    end

    -- Spawn gunner (passenger seat)
    local gunner = CreatePedInsideVehicle(vehicle, 4, ESCORT_GUNNER_MODEL, 0, true, false)
    if DoesEntityExist(gunner) then
        SetPedArmour(gunner, 200)
        SetPedAccuracy(gunner, 80)
        SetPedCombatAbility(gunner, 2)
        SetPedCombatRange(gunner, 2)
        SetPedCombatAttributes(gunner, 46, true)
        SetPedCombatAttributes(gunner, 5, true)
        SetPedKeepTask(gunner, true)
        GiveWeaponToPed(gunner, ESCORT_WEAPON, 500, false, true)
        SetBlockingOfNonTemporaryEvents(gunner, true)
    end

    SetModelAsNoLongerNeeded(ESCORT_MODEL)
    SetModelAsNoLongerNeeded(ESCORT_DRIVER_MODEL)
    SetModelAsNoLongerNeeded(ESCORT_GUNNER_MODEL)

    return vehicle, driver, gunner
end

--- Create a military blip for an escort vehicle.
---@param entity number Entity handle
---@param label string Blip label
---@return number blip Blip handle
local function CreateEscortBlip(entity, label)
    local blip = AddBlipForEntity(entity)
    SetBlipSprite(blip, 530)       -- military icon
    SetBlipColour(blip, 69)        -- dark green
    SetBlipScale(blip, 0.8)
    SetBlipAsShortRange(blip, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(label)
    EndTextCommandSetBlipName(blip)
    return blip
end

--- Remove a blip safely.
---@param blip number|nil Blip handle
---@return nil
local function RemoveBlipSafe(blip)
    if blip and DoesBlipExist(blip) then
        RemoveBlip(blip)
    end
    return nil
end

-- ═══════════════════════════════════════════════════════════════
-- ESCORT AI BEHAVIOR
-- ═══════════════════════════════════════════════════════════════

--- Task lead escort to drive ahead of the player's vehicle.
local function TaskLeadEscort()
    if not leadVehicle or not DoesEntityExist(leadVehicle) then return end
    if not leadDriver or not DoesEntityExist(leadDriver) then return end

    local playerVeh = cache.vehicle
    if not playerVeh or not DoesEntityExist(playerVeh) then return end

    local playerCoords = GetEntityCoords(playerVeh)
    local playerHeading = GetEntityHeading(playerVeh)
    local headingRad = math.rad(playerHeading)

    -- Calculate position ahead of player
    local targetX = playerCoords.x - math.sin(headingRad) * ESCORT_OFFSET_LEAD
    local targetY = playerCoords.y + math.cos(headingRad) * ESCORT_OFFSET_LEAD

    TaskVehicleDriveToCoordLongrange(leadDriver, leadVehicle, targetX, targetY, playerCoords.z,
        CONVOY_SPEED, 786468, 10.0)
end

--- Task trail escort to follow behind the player's vehicle.
local function TaskTrailEscort()
    if not trailVehicle or not DoesEntityExist(trailVehicle) then return end
    if not trailDriver or not DoesEntityExist(trailDriver) then return end

    local playerVeh = cache.vehicle
    if not playerVeh or not DoesEntityExist(playerVeh) then return end

    local playerCoords = GetEntityCoords(playerVeh)
    local playerHeading = GetEntityHeading(playerVeh)
    local headingRad = math.rad(playerHeading)

    -- Calculate position behind player
    local targetX = playerCoords.x + math.sin(headingRad) * ESCORT_OFFSET_TRAIL
    local targetY = playerCoords.y - math.cos(headingRad) * ESCORT_OFFSET_TRAIL

    TaskVehicleDriveToCoordLongrange(trailDriver, trailVehicle, targetX, targetY, playerCoords.z,
        CONVOY_SPEED, 786468, 10.0)
end

--- Task escorts to investigate player's stopped position.
local function TaskEscortsInvestigate()
    if escortsInvestigating then return end
    escortsInvestigating = true

    local playerCoords = GetEntityCoords(cache.ped)

    -- Lead drives to player
    if leadVehicle and DoesEntityExist(leadVehicle) and leadDriver and DoesEntityExist(leadDriver) then
        TaskVehicleDriveToCoordLongrange(leadDriver, leadVehicle, playerCoords.x + 5.0, playerCoords.y,
            playerCoords.z, CONVOY_SPEED * 0.6, 786468, 5.0)
    end

    -- Trail drives to player
    if trailVehicle and DoesEntityExist(trailVehicle) and trailDriver and DoesEntityExist(trailDriver) then
        TaskVehicleDriveToCoordLongrange(trailDriver, trailVehicle, playerCoords.x - 5.0, playerCoords.y,
            playerCoords.z, CONVOY_SPEED * 0.6, 786468, 5.0)
    end

    lib.notify({
        title       = 'Military Convoy',
        description = 'Escort is checking on you. Keep moving.',
        type        = 'warning',
        duration    = 5000,
    })
end

--- Task escort NPCs to engage a hostile target.
---@param targetPed number Target ped handle
local function TaskEscortsEngage(targetPed)
    if not targetPed or not DoesEntityExist(targetPed) then return end

    local cargoCoords = GetEntityCoords(cache.vehicle or cache.ped)

    -- Helper: engage if within pursue range
    local function EngageIfInRange(escortPed, escortVeh)
        if not escortPed or not DoesEntityExist(escortPed) then return end
        if not escortVeh or not DoesEntityExist(escortVeh) then return end

        local escortCoords = GetEntityCoords(escortVeh)
        local distToCargo = #(escortCoords - cargoCoords)

        if distToCargo <= PURSUE_MAX_DIST then
            TaskCombatPed(escortPed, targetPed, 0, 16)
        end
    end

    -- Lead crew engages
    EngageIfInRange(leadDriver, leadVehicle)
    EngageIfInRange(leadGunner, leadVehicle)

    -- Trail crew engages
    EngageIfInRange(trailDriver, trailVehicle)
    EngageIfInRange(trailGunner, trailVehicle)
end

-- ═══════════════════════════════════════════════════════════════
-- VEHICLE DESTRUCTION MONITORING
-- ═══════════════════════════════════════════════════════════════

--- Check if an escort vehicle is destroyed.
---@param vehicle number Vehicle handle
---@return boolean destroyed
local function IsEscortDestroyed(vehicle)
    if not vehicle or not DoesEntityExist(vehicle) then return true end
    return IsEntityDead(vehicle) or GetVehicleEngineHealth(vehicle) <= 0
end

-- ═══════════════════════════════════════════════════════════════
-- BREACH DETECTION
-- ═══════════════════════════════════════════════════════════════

--- Detect hostile actions near the convoy (gunfire, explosions).
---@return boolean breachDetected
---@return vector3|nil breachCoords
local function DetectBreach()
    local playerCoords = GetEntityCoords(cache.ped)

    -- Check for nearby explosions (monitor damage events on convoy vehicles)
    if leadVehicle and DoesEntityExist(leadVehicle) then
        if HasEntityBeenDamagedByAnyPed(leadVehicle) or HasEntityBeenDamagedByAnyObject(leadVehicle) then
            ClearEntityLastDamageEntity(leadVehicle)
            return true, GetEntityCoords(leadVehicle)
        end
    end

    if trailVehicle and DoesEntityExist(trailVehicle) then
        if HasEntityBeenDamagedByAnyPed(trailVehicle) or HasEntityBeenDamagedByAnyObject(trailVehicle) then
            ClearEntityLastDamageEntity(trailVehicle)
            return true, GetEntityCoords(trailVehicle)
        end
    end

    -- Check player's cargo vehicle for attacks
    local playerVeh = cache.vehicle
    if playerVeh and DoesEntityExist(playerVeh) then
        if HasEntityBeenDamagedByAnyPed(playerVeh) then
            -- Exclude self-damage
            local attacker = GetPedSourceOfDeath(cache.ped)
            if attacker and attacker ~= cache.ped then
                ClearEntityLastDamageEntity(playerVeh)
                return true, playerCoords
            end
        end
    end

    -- Check for shooting near convoy (any ped shooting within 100m)
    local shootingPed, _ = GetClosestPed(playerCoords.x, playerCoords.y, playerCoords.z, 100.0, true, true, false, false, -1)
    if shootingPed and DoesEntityExist(shootingPed) and shootingPed ~= cache.ped then
        if IsPedShooting(shootingPed) then
            return true, GetEntityCoords(shootingPed)
        end
    end

    return false, nil
end

-- ═══════════════════════════════════════════════════════════════
-- CONVOY MONITORING THREADS
-- ═══════════════════════════════════════════════════════════════

--- Formation monitoring thread: keeps escorts in formation,
--- handles stop investigation, and manages destroy states.
local function StartFormationMonitor()
    CreateThread(function()
        while convoyActive do
            Wait(FORMATION_CHECK_MS)

            if not convoyActive then break end

            -- Check escort vehicle status
            if not leadDestroyed and IsEscortDestroyed(leadVehicle) then
                leadDestroyed = true
                leadBlip = RemoveBlipSafe(leadBlip)
                lib.notify({
                    title       = 'Military Convoy',
                    description = 'Lead escort destroyed!',
                    type        = 'error',
                    duration    = 5000,
                })
            end

            if not trailDestroyed and IsEscortDestroyed(trailVehicle) then
                trailDestroyed = true
                trailBlip = RemoveBlipSafe(trailBlip)
                lib.notify({
                    title       = 'Military Convoy',
                    description = 'Trail escort destroyed!',
                    type        = 'error',
                    duration    = 5000,
                })
            end

            -- Both escorts destroyed: start unguarded timer
            if leadDestroyed and trailDestroyed then
                if unguardedTimer == 0 then
                    unguardedTimer = GetGameTimer()
                end

                if not unguardedNotified then
                    unguardedNotified = true
                    lib.notify({
                        title       = 'Military Convoy',
                        description = 'Both escorts neutralized. Cargo unguarded for 90 seconds.',
                        type        = 'error',
                        duration    = 8000,
                    })
                    TriggerServerEvent('trucking:server:escortDestroyed', convoyLoadId)
                end

                -- Check if unguarded window has expired
                if GetElapsed(unguardedTimer) >= UNGUARDED_DURATION then
                    TriggerServerEvent('trucking:server:militaryLongCon', convoyLoadId)
                end

                goto continueFormation
            end

            -- Player movement detection
            local playerVeh = cache.vehicle
            if playerVeh and DoesEntityExist(playerVeh) then
                local speed = GetEntitySpeed(playerVeh)

                if speed < 1.0 then
                    -- Vehicle is stationary
                    if not playerStopped then
                        playerStopped = true
                        playerStopTimer = GetGameTimer()
                    end

                    -- Check if stopped long enough for investigation
                    local stopDuration = GetElapsed(playerStopTimer)
                    if stopDuration >= INVESTIGATE_DELAY_MS and not escortsInvestigating then
                        TaskEscortsInvestigate()
                    end
                else
                    -- Player is moving
                    if playerStopped then
                        playerStopped = false
                        playerStopTimer = 0
                        escortsInvestigating = false
                    end

                    -- Update escort formations
                    if not leadDestroyed then TaskLeadEscort() end
                    if not trailDestroyed then TaskTrailEscort() end
                end
            end

            ::continueFormation::
        end
    end)
end

--- Breach detection thread: monitors for hostile actions near the convoy.
local function StartBreachMonitor()
    CreateThread(function()
        while convoyActive do
            Wait(BREACH_CHECK_MS)

            if not convoyActive then break end

            local breachDetected, breachCoords = DetectBreach()

            if breachDetected and breachCoords then
                -- Report breach to server
                TriggerServerEvent('trucking:server:militaryBreachDetected', convoyLoadId, breachCoords)

                -- Task escorts to engage hostiles
                local nearbyPeds = {}
                local playerCoords = GetEntityCoords(cache.ped)

                -- Find hostile peds in range
                for _, ped in ipairs(GetGamePool('CPed')) do
                    if DoesEntityExist(ped) and not IsPedAPlayer(ped) then
                        local pedCoords = GetEntityCoords(ped)
                        local dist = #(pedCoords - playerCoords)

                        -- Skip our own escort peds
                        if ped ~= leadDriver and ped ~= leadGunner
                           and ped ~= trailDriver and ped ~= trailGunner then
                            if dist < 150.0 and (IsPedShooting(ped) or IsPedInMeleeCombat(ped)) then
                                nearbyPeds[#nearbyPeds + 1] = ped
                            end
                        end
                    end
                end

                -- Engage first hostile found (others handled by combat AI)
                for _, hostilePed in ipairs(nearbyPeds) do
                    TaskEscortsEngage(hostilePed)
                    break
                end

                -- Also check for player attackers
                for _, player in ipairs(GetActivePlayers()) do
                    local otherPed = GetPlayerPed(player)
                    if otherPed ~= cache.ped and DoesEntityExist(otherPed) then
                        if IsPedShooting(otherPed) then
                            local dist = #(GetEntityCoords(otherPed) - playerCoords)
                            if dist < 200.0 then
                                TaskEscortsEngage(otherPed)
                            end
                        end
                    end
                end

                -- Rate limit breach reports (don't spam server)
                Wait(5000)
            end
        end
    end)
end

-- ═══════════════════════════════════════════════════════════════
-- CONVOY LIFECYCLE
-- ═══════════════════════════════════════════════════════════════

--- Start a military convoy with escort vehicles.
---@param loadId number Active load ID
---@param routeData table Route waypoints and metadata
local function StartConvoy(loadId, routeData)
    if convoyActive then return end

    convoyLoadId = loadId
    convoyRoute  = routeData
    convoyActive = true

    -- Reset state
    playerStopped        = false
    playerStopTimer      = 0
    escortsInvestigating = false
    leadDestroyed        = false
    trailDestroyed       = false
    unguardedTimer       = 0
    unguardedNotified    = false

    -- Get player vehicle position for escort spawn
    local playerVeh = cache.vehicle
    if not playerVeh or not DoesEntityExist(playerVeh) then
        lib.notify({
            title       = 'Military Convoy',
            description = 'You must be in your cargo vehicle to start the convoy.',
            type        = 'error',
        })
        convoyActive = false
        return
    end

    local playerCoords = GetEntityCoords(playerVeh)
    local playerHeading = GetEntityHeading(playerVeh)
    local headingRad = math.rad(playerHeading)

    -- Spawn lead escort (ahead of player)
    local leadX = playerCoords.x - math.sin(headingRad) * ESCORT_OFFSET_LEAD
    local leadY = playerCoords.y + math.cos(headingRad) * ESCORT_OFFSET_LEAD
    local leadCoords = vector3(leadX, leadY, playerCoords.z)

    leadVehicle, leadDriver, leadGunner = SpawnEscortVehicle(leadCoords, playerHeading, true)

    -- Spawn trail escort (behind player)
    local trailX = playerCoords.x + math.sin(headingRad) * ESCORT_OFFSET_TRAIL
    local trailY = playerCoords.y - math.cos(headingRad) * ESCORT_OFFSET_TRAIL
    local trailCoords = vector3(trailX, trailY, playerCoords.z)

    trailVehicle, trailDriver, trailGunner = SpawnEscortVehicle(trailCoords, playerHeading, false)

    -- Create blips
    if leadVehicle and DoesEntityExist(leadVehicle) then
        leadBlip = CreateEscortBlip(leadVehicle, 'Lead Escort')
    end

    if trailVehicle and DoesEntityExist(trailVehicle) then
        trailBlip = CreateEscortBlip(trailVehicle, 'Trail Escort')
    end

    -- Start monitoring threads
    StartFormationMonitor()
    StartBreachMonitor()

    -- Initial formation tasks
    TaskLeadEscort()
    TaskTrailEscort()

    lib.notify({
        title       = 'Military Convoy',
        description = 'Convoy formed. Lead and trail escorts active. Maintain speed.',
        type        = 'success',
        duration    = 6000,
    })
end

--- Stop and clean up the convoy.
local function StopConvoy()
    convoyActive = false

    -- Remove blips
    leadBlip  = RemoveBlipSafe(leadBlip)
    trailBlip = RemoveBlipSafe(trailBlip)

    -- Delete escort peds
    local function DeletePedSafe(ped)
        if ped and DoesEntityExist(ped) then
            DeleteEntity(ped)
        end
    end

    DeletePedSafe(leadDriver)
    DeletePedSafe(leadGunner)
    DeletePedSafe(trailDriver)
    DeletePedSafe(trailGunner)

    leadDriver  = nil
    leadGunner  = nil
    trailDriver = nil
    trailGunner = nil

    -- Delete escort vehicles
    local function DeleteVehicleSafe(veh)
        if veh and DoesEntityExist(veh) then
            DeleteEntity(veh)
        end
    end

    DeleteVehicleSafe(leadVehicle)
    DeleteVehicleSafe(trailVehicle)

    leadVehicle  = nil
    trailVehicle = nil

    -- Reset state
    convoyLoadId         = nil
    convoyRoute          = nil
    playerStopped        = false
    playerStopTimer      = 0
    escortsInvestigating = false
    leadDestroyed        = false
    trailDestroyed       = false
    unguardedTimer       = 0
    unguardedNotified    = false
end

-- ═══════════════════════════════════════════════════════════════
-- SERVER EVENTS
-- ═══════════════════════════════════════════════════════════════

--- Server requests convoy start.
RegisterNetEvent('trucking:client:startMilitaryConvoy', function(data)
    if not data or not data.loadId then return end
    StartConvoy(data.loadId, data.route)
end)

--- Server requests convoy stop (delivery complete, failed, etc).
RegisterNetEvent('trucking:client:stopMilitaryConvoy', function()
    StopConvoy()
end)

--- Server notifies convoy delivery complete.
RegisterNetEvent('trucking:client:militaryDeliveryComplete', function(data)
    StopConvoy()

    if data and data.payout then
        lib.notify({
            title       = 'Military Contract',
            description = string.format('Contract complete. Payout: %s', FormatMoney(data.payout)),
            type        = 'success',
            duration    = 8000,
        })
    end
end)

--- Server notifies military contract failed.
RegisterNetEvent('trucking:client:militaryContractFailed', function(reason)
    StopConvoy()

    lib.notify({
        title       = 'Military Contract',
        description = reason or 'Contract terminated.',
        type        = 'error',
        duration    = 6000,
    })
end)

--- Server requests spawning the military convoy escort
RegisterNetEvent('trucking:client:spawnMilitaryConvoy', function(data)
    if not data or not data.loadId then return end
    StartConvoy(data.loadId, data.route)
end)

--- Server requests despawning the military convoy
RegisterNetEvent('trucking:client:despawnMilitaryConvoy', function()
    StopConvoy()
end)

--- Server notifies escorts to investigate player position
RegisterNetEvent('trucking:client:escortsInvestigate', function()
    TaskEscortsInvestigate()
end)

-- ═══════════════════════════════════════════════════════════════
-- CLEANUP
-- ═══════════════════════════════════════════════════════════════

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    StopConvoy()
end)

RegisterNetEvent('qbx_core:client:onLogout', function()
    StopConvoy()
end)
