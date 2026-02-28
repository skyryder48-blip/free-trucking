--[[
    client/cdl.lua — CDL Test and Tutorial NUI Triggers
    Free Trucking — QBX Framework

    Responsibilities:
    - Written test flow: NPC interaction -> open test NUI -> player answers
      10 questions -> submit -> server grades
    - CDL tutorial (Class A practical) with 5 stages:
        Stage 1: Pre-Trip Inspection (5 checkpoints, forgiving)
        Stage 2: Coupling (trailer coupling, seal, 3 strap points)
        Stage 3: City Navigation (LSIA -> Industrial, speed/signal/curb)
        Stage 4: Highway Run (Industrial -> Harmony, weight/window/HUD)
        Stage 5: Backing & Dock (5 attempts, BOL signing, $850 payout)
    - Stage progression tracking
    - Vehicle spawning for tutorial
    - Success/fail feedback per stage via lib.notify
    - On Stage 5 completion: server issues Class A CDL + $850 payout

    Authority model:
    - Client manages NUI triggers, stage progression UI, tutorial flow
    - Server grades tests, issues licenses, handles payouts
    - No payout or reputation logic runs here
]]

-- ─────────────────────────────────────────────
-- STATE
-- ─────────────────────────────────────────────
local cdlTestActive = false
local tutorialActive = false
local currentStage = 0
local totalStages = 5
local tutorialVehicle = nil
local tutorialTrailer = nil

--- LSDOT NPC location for written test interaction
local LSDOT_NPC_COORDS = vector3(-79.68, -249.32, 45.59)
local LSDOT_NPC_HEADING = 70.0
local LSDOT_NPC_MODEL = 's_m_m_scientist_01'
local lsdotNPC = nil
local lsdotBlip = nil
local nearLSDOT = false
local lsdotTextUIShowing = false

--- Tutorial start location (near LSIA cargo area)
local TUTORIAL_START_COORDS = vector3(-1025.73, -2728.07, 13.76)
local TUTORIAL_START_HEADING = 330.0

--- Tutorial route waypoints
local TUTORIAL_ROUTES = {
    -- Stage 3: City Navigation (LSIA -> Industrial)
    [3] = {
        start = vector3(-1025.73, -2728.07, 13.76),
        finish = vector3(790.96, -2160.0, 29.62),
        label = 'LSIA to Industrial District',
    },
    -- Stage 4: Highway Run (Industrial -> Route 1 Harmony)
    [4] = {
        start = vector3(790.96, -2160.0, 29.62),
        finish = vector3(1199.23, 2648.30, 37.78),
        label = 'Industrial to Harmony Truck Stop',
    },
}

--- Stage 5: Dock zone for backing practice
local DOCK_ZONE_COORDS = vector3(1199.23, 2648.30, 37.78)
local DOCK_ZONE_SIZE = vec3(8.0, 5.0, 3.0)
local DOCK_ZONE_HEADING = 45.0

--- Tutorial vehicle models
local TUTORIAL_TRUCK_MODEL = 'hauler'
local TUTORIAL_TRAILER_MODEL = 'trailers'

--- Pre-trip inspection checkpoints (Stage 1)
local PRE_TRIP_CHECKPOINTS = {
    { id = 'tires',      label = 'Checking tire pressure and tread',     duration = 3000, offset = vector3(-1.2, 2.5, -0.5) },
    { id = 'lights',     label = 'Testing marker and brake lights',      duration = 3000, offset = vector3(0.0, -3.5, 0.0) },
    { id = 'brakes',     label = 'Checking brake line pressure',         duration = 3000, offset = vector3(1.2, 1.0, -0.5) },
    { id = 'fluids',     label = 'Checking engine fluid levels',         duration = 3000, offset = vector3(0.0, 3.0, 0.5) },
    { id = 'coupling',   label = 'Verifying fifth-wheel coupling area',  duration = 3000, offset = vector3(0.0, -1.5, -0.3) },
}

--- Stage 2: Coupling strap points
local COUPLING_STRAP_POINTS = 3

--- Stage 3/4: Monitoring state
local navigationMonitoring = false
local speedViolations = 0
local curbViolations = 0
local stageCheckZone = nil

--- Stage 5: Backing attempts
local MAX_BACKING_ATTEMPTS = 5
local backingAttempts = 0
local backingDockZone = nil

-- ─────────────────────────────────────────────
-- NPC MANAGEMENT
-- ─────────────────────────────────────────────

--- Spawn the LSDOT NPC at the DMV building.
local function SpawnLSDOTNpc()
    if lsdotNPC and DoesEntityExist(lsdotNPC) then return end

    local model = joaat(LSDOT_NPC_MODEL)
    RequestModel(model)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(model) do
        Wait(100)
        if GetGameTimer() > timeout then return end
    end

    lsdotNPC = CreatePed(4, model, LSDOT_NPC_COORDS.x, LSDOT_NPC_COORDS.y,
        LSDOT_NPC_COORDS.z, LSDOT_NPC_HEADING, false, true)
    SetEntityAsMissionEntity(lsdotNPC, true, true)
    SetBlockingOfNonTemporaryEvents(lsdotNPC, true)
    SetPedFleeAttributes(lsdotNPC, 0, false)
    FreezeEntityPosition(lsdotNPC, true)
    SetEntityInvincible(lsdotNPC, true)
    SetModelAsNoLongerNeeded(model)
end

--- Create the LSDOT office blip on the minimap.
local function CreateLSDOTBlip()
    if lsdotBlip then return end
    lsdotBlip = AddBlipForCoord(LSDOT_NPC_COORDS.x, LSDOT_NPC_COORDS.y, LSDOT_NPC_COORDS.z)
    SetBlipSprite(lsdotBlip, 408) -- office/government building
    SetBlipDisplay(lsdotBlip, 4)
    SetBlipScale(lsdotBlip, 0.8)
    SetBlipColour(lsdotBlip, 3) -- blue
    SetBlipAsShortRange(lsdotBlip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName('LSDOT - CDL Office')
    EndTextCommandSetBlipName(lsdotBlip)
end

--- Remove the LSDOT NPC and blip.
local function RemoveLSDOTNpc()
    if lsdotNPC and DoesEntityExist(lsdotNPC) then
        DeleteEntity(lsdotNPC)
        lsdotNPC = nil
    end
    if lsdotBlip then
        RemoveBlip(lsdotBlip)
        lsdotBlip = nil
    end
end

-- ─────────────────────────────────────────────
-- WRITTEN TEST
-- ─────────────────────────────────────────────

--- Open the written test NUI. The NUI renders the question form;
--- player answers are submitted back via NUI callback.
---@param testType string 'class_b' or 'class_a'
local function OpenWrittenTest(testType)
    if cdlTestActive then return end
    cdlTestActive = true

    -- Request test questions from server
    TriggerServerEvent('trucking:server:startWrittenTest', testType)
end

--- NUI callback: test questions received from server, display them.
RegisterNetEvent('trucking:client:cdlTestQuestions', function(data)
    if not data or not data.questions then
        cdlTestActive = false
        return
    end

    SendNUIMessage({
        action = 'openCDLTest',
        data = {
            testType = data.testType,
            questions = data.questions,
            questionCount = #data.questions,
            passScore = Config.CDLWrittenTestPassScore or 80,
            fee = data.fee or 0,
        },
    })

    SetNuiFocus(true, true)
end)

--- NUI callback: player submits test answers.
RegisterNUICallback('trucking:submitCDLTest', function(data, cb)
    if not data or not data.answers then
        cb({ ok = false, error = 'No answers provided' })
        return
    end

    TriggerServerEvent('trucking:server:submitTestResults', data.testType, data.answers)
    cb({ ok = true })
end)

--- Server response: test result.
RegisterNetEvent('trucking:client:cdlTestResult', function(data)
    if not data then return end

    cdlTestActive = false
    SetNuiFocus(false, false)

    SendNUIMessage({
        action = 'cdlTestResult',
        data = data,
    })

    if data.passed then
        lib.notify({
            title = locale('cdl.written_test_title'),
            description = locale('cdl.written_test_passed'):format(data.score or 0)
                .. (data.practicalRequired and (' — ' .. locale('cdl.practical_now_available')) or ''),
            type = 'success',
            duration = 8000,
        })
    else
        lib.notify({
            title = locale('cdl.written_test_title'),
            description = locale('cdl.written_test_failed'):format(data.score or 0, data.attemptsRemaining or 0),
            type = 'error',
            duration = 8000,
        })

        -- Handle lockout
        if data.lockedOut then
            lib.notify({
                title = locale('cdl.office_title'),
                description = locale('cdl.max_attempts_locked'):format(Config.CDLWrittenLockoutMinutes or 60),
                type = 'error',
                duration = 10000,
            })
        end
    end
end)

--- Close test NUI via escape.
RegisterNUICallback('trucking:closeCDLTest', function(_, cb)
    cdlTestActive = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closeCDLTest' })
    cb({ ok = true })
end)

--- Player completes HAZMAT safety briefing (read all topics).
RegisterNUICallback('trucking:completeHAZMATBriefing', function(_, cb)
    cdlTestActive = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closeCDLTest' })
    TriggerServerEvent('trucking:server:completeHAZMATBriefing')
    cb({ ok = true })
end)

-- ─────────────────────────────────────────────
-- TUTORIAL VEHICLE MANAGEMENT
-- ─────────────────────────────────────────────

--- Spawn tutorial truck and trailer at the starting location.
---@return number|nil truck, number|nil trailer
local function SpawnTutorialVehicles()
    -- Load truck model
    local truckHash = joaat(TUTORIAL_TRUCK_MODEL)
    RequestModel(truckHash)
    local timeout = GetGameTimer() + 10000
    while not HasModelLoaded(truckHash) do
        Wait(100)
        if GetGameTimer() > timeout then return nil, nil end
    end

    -- Load trailer model
    local trailerHash = joaat(TUTORIAL_TRAILER_MODEL)
    RequestModel(trailerHash)
    timeout = GetGameTimer() + 10000
    while not HasModelLoaded(trailerHash) do
        Wait(100)
        if GetGameTimer() > timeout then return nil, nil end
    end

    -- Spawn truck
    local truck = CreateVehicle(truckHash, TUTORIAL_START_COORDS.x,
        TUTORIAL_START_COORDS.y, TUTORIAL_START_COORDS.z,
        TUTORIAL_START_HEADING, true, false)
    SetEntityAsMissionEntity(truck, true, true)
    SetVehicleEngineOn(truck, true, true, false)

    -- Spawn trailer nearby (behind truck)
    local trailerPos = GetOffsetFromEntityInWorldCoords(truck, 0.0, -12.0, 0.0)
    local trailer = CreateVehicle(trailerHash, trailerPos.x, trailerPos.y,
        trailerPos.z, TUTORIAL_START_HEADING, true, false)
    SetEntityAsMissionEntity(trailer, true, true)

    SetModelAsNoLongerNeeded(truckHash)
    SetModelAsNoLongerNeeded(trailerHash)

    return truck, trailer
end

--- Delete tutorial vehicles.
local function DeleteTutorialVehicles()
    if tutorialVehicle and DoesEntityExist(tutorialVehicle) then
        DeleteVehicle(tutorialVehicle)
        tutorialVehicle = nil
    end
    if tutorialTrailer and DoesEntityExist(tutorialTrailer) then
        DeleteVehicle(tutorialTrailer)
        tutorialTrailer = nil
    end
end

-- ─────────────────────────────────────────────
-- TUTORIAL STAGES
-- ─────────────────────────────────────────────

--- Stage 1: Pre-Trip Inspection
--- 5 inspection checkpoints around a parked truck. Forgiving, no failure.
local function RunStage1()
    currentStage = 1

    lib.notify({
        title = locale('cdl.tutorial_stage_title'):format(1),
        description = locale('cdl.stage1_desc'),
        type = 'inform',
        duration = 8000,
    })

    -- Put player near the truck
    local ped = PlayerPedId()
    if tutorialVehicle and DoesEntityExist(tutorialVehicle) then
        local truckPos = GetEntityCoords(tutorialVehicle)
        SetEntityCoords(ped, truckPos.x + 2.0, truckPos.y, truckPos.z, false, false, false, true)
    end

    for i, checkpoint in ipairs(PRE_TRIP_CHECKPOINTS) do
        if not tutorialActive then return false end

        lib.notify({
            title = locale('cdl.inspection_point'):format(i, #PRE_TRIP_CHECKPOINTS),
            description = checkpoint.label,
            type = 'inform',
            duration = 4000,
        })

        local success = lib.progressBar({
            duration = checkpoint.duration,
            label = checkpoint.label .. ' (' .. i .. '/' .. #PRE_TRIP_CHECKPOINTS .. ')',
            useWhileDead = false,
            canCancel = true,
            anim = {
                dict = 'mini@repair',
                clip = 'fixing_a_ped',
                flag = 49,
            },
        })

        if not success then
            lib.notify({
                title = locale('cdl.pre_trip_title'),
                description = locale('cdl.point_skipped_training'),
                type = 'inform',
            })
            -- Forgiving: continue even if cancelled
        end

        Wait(500)
    end

    lib.notify({
        title = locale('cdl.stage_complete'):format(1),
        description = locale('cdl.stage1_complete_desc'),
        type = 'success',
        duration = 5000,
    })

    TriggerServerEvent('trucking:server:completeTutorialStage', 1)
    return true
end

--- Stage 2: Coupling
--- Approach trailer, coupling zone interaction, seal application, 3 cargo strap points.
local function RunStage2()
    currentStage = 2

    lib.notify({
        title = locale('cdl.tutorial_stage_title'):format(2),
        description = locale('cdl.stage2_desc'),
        type = 'inform',
        duration = 8000,
    })

    -- Coupling zone interaction
    lib.notify({
        title = locale('cdl.step_title'):format(1),
        description = locale('cdl.back_up_to_couple'),
        type = 'inform',
        duration = 5000,
    })

    -- Wait for player to be in truck and near trailer
    local couplingComplete = false
    local couplingTimeout = GetGameTimer() + 120000 -- 2 min timeout
    local attempts = 0
    local MAX_COUPLING_ATTEMPTS = 5

    while not couplingComplete and tutorialActive do
        Wait(1000)
        if GetGameTimer() > couplingTimeout then
            lib.notify({
                title = locale('cdl.coupling_title'),
                description = locale('cdl.auto_coupling_timeout'),
                type = 'inform',
            })
            couplingComplete = true
            break
        end

        local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
        if vehicle and vehicle ~= 0 and tutorialTrailer and DoesEntityExist(tutorialTrailer) then
            local vehPos = GetEntityCoords(vehicle)
            local trailerPos = GetEntityCoords(tutorialTrailer)
            if #(vehPos - trailerPos) < 8.0 then
                -- Attempt coupling
                AttachVehicleToTrailer(vehicle, tutorialTrailer, 5.0)
                Wait(500)
                local hasTrailer, _ = GetVehicleTrailerVehicle(vehicle)
                if hasTrailer then
                    couplingComplete = true
                else
                    attempts = attempts + 1
                    if attempts >= MAX_COUPLING_ATTEMPTS then
                        lib.notify({
                            title = locale('cdl.coupling_title'),
                            description = locale('cdl.auto_coupling_training'),
                            type = 'inform',
                        })
                        couplingComplete = true
                    end
                end
            end
        end
    end

    if not tutorialActive then return false end

    lib.notify({
        title = locale('cdl.trailer_coupled'),
        description = locale('cdl.seal_the_trailer'),
        type = 'success',
    })

    -- Seal application
    local sealSuccess = lib.progressBar({
        duration = 3000,
        label = locale('cdl.applying_seal'),
        useWhileDead = false,
        canCancel = true,
        anim = {
            dict = 'anim@heists@ornate_bank@hack',
            clip = 'hack_enter',
            flag = 49,
        },
    })

    if sealSuccess then
        lib.notify({ title = locale('cdl.seal_applied'), description = locale('cdl.seal_number_recorded'), type = 'success' })
    end

    -- 3 strap points
    for i = 1, COUPLING_STRAP_POINTS do
        if not tutorialActive then return false end

        local strapSuccess = lib.progressBar({
            duration = 4000,
            label = locale('cdl.securing_strap'):format(i, COUPLING_STRAP_POINTS),
            useWhileDead = false,
            canCancel = true,
            anim = {
                dict = 'anim@heists@ornate_bank@hack',
                clip = 'hack_enter',
                flag = 49,
            },
        })

        if strapSuccess then
            lib.notify({
                title = locale('cdl.strap_point_secured_title'):format(i),
                description = locale('cdl.strap_point_complete'):format(i, COUPLING_STRAP_POINTS),
                type = 'success',
                duration = 2000,
            })
        end
        Wait(300)
    end

    lib.notify({
        title = locale('cdl.stage_complete'):format(2),
        description = locale('cdl.stage2_complete_desc'),
        type = 'success',
        duration = 5000,
    })

    TriggerServerEvent('trucking:server:completeTutorialStage', 2)
    return true
end

--- Stage 3: City Navigation
--- GPS route LSIA -> Industrial (~1.5 mi). Monitor speed, signals, curbs.
local function RunStage3()
    currentStage = 3
    local route = TUTORIAL_ROUTES[3]

    lib.notify({
        title = locale('cdl.tutorial_stage_title'):format(3),
        description = locale('cdl.stage3_desc'),
        type = 'inform',
        duration = 10000,
    })

    -- Set GPS to destination
    SetNewWaypoint(route.finish.x, route.finish.y)

    -- Start monitoring driving behavior
    navigationMonitoring = true
    speedViolations = 0
    curbViolations = 0

    -- Speed and driving monitoring thread
    CreateThread(function()
        while navigationMonitoring and tutorialActive do
            local ped = PlayerPedId()
            local vehicle = GetVehiclePedIsIn(ped, false)
            if vehicle and vehicle ~= 0 then
                local speed = GetEntitySpeed(vehicle) * 2.23694 -- to mph
                if speed > 50.0 then -- city speed limit
                    speedViolations = speedViolations + 1
                    if speedViolations % 10 == 1 then -- notify every ~5 seconds
                        lib.notify({
                            title = locale('cdl.speed_warning_title'),
                            description = locale('cdl.speed_warning_desc'),
                            type = 'warning',
                            duration = 3000,
                        })
                    end
                end
            end
            Wait(500)
        end
    end)

    -- Wait for player to reach destination
    local arrived = false
    while not arrived and tutorialActive do
        Wait(1000)
        local playerPos = GetEntityCoords(PlayerPedId())
        if #(playerPos - route.finish) < 25.0 then
            arrived = true
        end
    end

    navigationMonitoring = false

    if not tutorialActive then return false end

    if speedViolations > 20 then
        lib.notify({
            title = locale('cdl.stage3_note_title'),
            description = locale('cdl.stage3_note_desc'),
            type = 'warning',
            duration = 6000,
        })
    end

    lib.notify({
        title = locale('cdl.stage_complete'):format(3),
        description = locale('cdl.stage3_complete_desc'),
        type = 'success',
        duration = 5000,
    })

    TriggerServerEvent('trucking:server:completeTutorialStage', 3)
    return true
end

--- Stage 4: Highway Run
--- GPS route Industrial -> Route 1 Harmony (~4 mi). Weight, window, HUD intro.
local function RunStage4()
    currentStage = 4
    local route = TUTORIAL_ROUTES[4]

    lib.notify({
        title = locale('cdl.tutorial_stage_title'):format(4),
        description = locale('cdl.stage4_desc'),
        type = 'inform',
        duration = 10000,
    })

    -- Show weight/window HUD info via NUI
    SendNUIMessage({
        action = 'tutorialHUD',
        data = {
            stage = 4,
            weightMultiplier = 1.15,
            deliveryWindow = '25 minutes',
            distance = '4.0 mi',
        },
    })

    -- Set GPS to destination
    SetNewWaypoint(route.finish.x, route.finish.y)

    -- Wait for player to reach destination
    local arrived = false
    while not arrived and tutorialActive do
        Wait(1000)
        local playerPos = GetEntityCoords(PlayerPedId())
        if #(playerPos - route.finish) < 25.0 then
            arrived = true
        end
    end

    if not tutorialActive then return false end

    lib.notify({
        title = locale('cdl.stage_complete'):format(4),
        description = locale('cdl.stage4_complete_desc'),
        type = 'success',
        duration = 5000,
    })

    TriggerServerEvent('trucking:server:completeTutorialStage', 4)
    return true
end

--- Stage 5: Backing & Dock
--- 5 backing attempts into a dock zone. BOL signing. $850 payout.
local function RunStage5()
    currentStage = 5
    backingAttempts = 0

    lib.notify({
        title = locale('cdl.tutorial_stage_title'):format(5),
        description = locale('cdl.stage5_desc'):format(MAX_BACKING_ATTEMPTS),
        type = 'inform',
        duration = 10000,
    })

    -- Create dock zone
    local dockSuccess = false

    backingDockZone = lib.zones.box({
        coords = DOCK_ZONE_COORDS,
        size = DOCK_ZONE_SIZE,
        rotation = DOCK_ZONE_HEADING,
        debug = true, -- visible during tutorial
        onEnter = function()
            if tutorialActive and currentStage == 5 then
                dockSuccess = true
            end
        end,
    })

    -- Wait for player to back into dock zone or exhaust attempts
    while not dockSuccess and backingAttempts < MAX_BACKING_ATTEMPTS and tutorialActive do
        Wait(1000)

        -- Check if player is in vehicle
        local ped = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)
        if vehicle and vehicle ~= 0 then
            -- Check for trailer in zone
            local hasTrailer, trailer = GetVehicleTrailerVehicle(vehicle)
            if hasTrailer and trailer ~= 0 then
                local trailerPos = GetEntityCoords(trailer)
                if #(trailerPos - DOCK_ZONE_COORDS) < 5.0 then
                    dockSuccess = true
                end
            end
        end
    end

    -- Remove dock zone
    if backingDockZone and backingDockZone.remove then
        backingDockZone:remove()
        backingDockZone = nil
    end

    if not tutorialActive then return false end

    if dockSuccess then
        lib.notify({
            title = locale('cdl.docking_successful'),
            description = locale('cdl.docking_signing_bol'),
            type = 'success',
            duration = 5000,
        })

        -- BOL signing interaction
        local bolSuccess = lib.progressBar({
            duration = 3000,
            label = locale('cdl.signing_bol'),
            useWhileDead = false,
            canCancel = false,
            anim = {
                dict = 'mp_common',
                clip = 'givetake1_a',
                flag = 49,
            },
        })

        lib.notify({
            title = locale('cdl.stage5_complete_title'),
            description = locale('cdl.stage5_complete_desc'),
            type = 'success',
            duration = 10000,
        })

        PlaySoundFrontend(-1, 'Mission_Pass_Notify', 'DLC_HEISTS_GENERAL_FRONTEND_SOUNDS', true)

        -- Server issues CDL and payout
        TriggerServerEvent('trucking:server:tutorialComplete')
    else
        lib.notify({
            title = locale('cdl.docking_title'),
            description = locale('cdl.all_attempts_used'),
            type = 'warning',
            duration = 8000,
        })
        TriggerServerEvent('trucking:server:completeTutorialStage', 5, false)
    end

    TriggerServerEvent('trucking:server:completeTutorialStage', 5, dockSuccess)
    return dockSuccess
end

-- ─────────────────────────────────────────────
-- TUTORIAL ORCHESTRATION
-- ─────────────────────────────────────────────

--- Run the full CDL practical tutorial from Stage 1 through Stage 5.
local function RunFullTutorial()
    if tutorialActive then return end
    tutorialActive = true
    currentStage = 0

    lib.notify({
        title = locale('cdl.practical_exam_title'),
        description = locale('cdl.practical_exam_desc'),
        type = 'inform',
        duration = 10000,
    })

    -- Spawn tutorial vehicles
    tutorialVehicle, tutorialTrailer = SpawnTutorialVehicles()
    if not tutorialVehicle then
        lib.notify({
            title = locale('cdl.tutorial_title'),
            description = locale('cdl.spawn_failed'),
            type = 'error',
        })
        tutorialActive = false
        return
    end

    -- Set player into the truck
    local ped = PlayerPedId()
    TaskWarpPedIntoVehicle(ped, tutorialVehicle, -1)
    Wait(1000)

    -- Stage 1: Pre-Trip
    local s1 = RunStage1()
    if not tutorialActive then
        DeleteTutorialVehicles()
        return
    end
    Wait(2000)

    -- Stage 2: Coupling
    local s2 = RunStage2()
    if not tutorialActive then
        DeleteTutorialVehicles()
        return
    end
    Wait(2000)

    -- Stage 3: City Navigation
    local s3 = RunStage3()
    if not tutorialActive then
        DeleteTutorialVehicles()
        return
    end
    Wait(2000)

    -- Stage 4: Highway Run
    local s4 = RunStage4()
    if not tutorialActive then
        DeleteTutorialVehicles()
        return
    end
    Wait(2000)

    -- Stage 5: Backing & Dock
    local s5 = RunStage5()

    -- Cleanup tutorial vehicles
    DeleteTutorialVehicles()
    tutorialActive = false

    -- Clear any tutorial HUD elements
    SendNUIMessage({ action = 'tutorialHUD', data = { stage = 0 } })
end

-- ─────────────────────────────────────────────
-- NPC INTERACTION
-- ─────────────────────────────────────────────

--- Show the LSDOT NPC interaction menu.
local function ShowLSDOTMenu()
    lib.registerContext({
        id = 'lsdot_cdl_menu',
        title = locale('cdl.lsdot_menu_title'),
        options = {
            {
                title = locale('cdl.class_b_written_title'),
                description = locale('cdl.written_test_desc'):format(Config.CDLFees and Config.CDLFees.class_b or 500, 10, 80),
                icon = 'file-alt',
                onSelect = function()
                    OpenWrittenTest('class_b')
                end,
            },
            {
                title = locale('cdl.class_a_written_title'),
                description = locale('cdl.written_test_desc'):format(Config.CDLFees and Config.CDLFees.class_a or 1500, 10, 80),
                icon = 'file-alt',
                onSelect = function()
                    OpenWrittenTest('class_a')
                end,
            },
            {
                title = locale('cdl.class_a_practical_title'),
                description = locale('cdl.class_a_practical_desc'),
                icon = 'truck',
                onSelect = function()
                    RunFullTutorial()
                end,
            },
            {
                title = locale('cdl.tanker_endorsement_title'),
                description = locale('cdl.tanker_endorsement_desc'):format(Config.CDLFees and Config.CDLFees.tanker or 800, 15, 80),
                icon = 'gas-pump',
                onSelect = function()
                    OpenWrittenTest('tanker')
                end,
            },
            {
                title = locale('cdl.hazmat_endorsement_title'),
                description = locale('cdl.hazmat_endorsement_desc'):format(Config.CDLFees and Config.CDLFees.hazmat or 1200),
                icon = 'radiation',
                onSelect = function()
                    if cdlTestActive then return end
                    cdlTestActive = true
                    TriggerServerEvent('trucking:server:startHAZMATBriefing')
                end,
            },
        },
    })
    lib.showContext('lsdot_cdl_menu')
end

-- ─────────────────────────────────────────────
-- PROXIMITY DETECTION FOR NPC
-- ─────────────────────────────────────────────
CreateThread(function()
    -- Spawn NPC and blip on resource start
    Wait(2000)
    SpawnLSDOTNpc()
    CreateLSDOTBlip()

    -- Proximity check thread
    while true do
        Wait(500)
        if not IsPlayerLoggedIn() then
            Wait(2000)
            goto continue
        end

        local playerPos = GetEntityCoords(PlayerPedId())
        local dist = #(playerPos - LSDOT_NPC_COORDS)

        if dist < 3.0 then
            if not nearLSDOT then
                nearLSDOT = true
                if not lsdotTextUIShowing then
                    lsdotTextUIShowing = true
                    lib.showTextUI(locale('cdl.lsdot_prompt'), {
                        position = 'right-center',
                        icon = 'id-card',
                    })
                end
            end
        else
            if nearLSDOT then
                nearLSDOT = false
                if lsdotTextUIShowing then
                    lsdotTextUIShowing = false
                    lib.hideTextUI()
                end
            end
        end

        ::continue::
    end
end)

--- Keybind for LSDOT NPC interaction.
CreateThread(function()
    while true do
        Wait(0)
        if nearLSDOT and not cdlTestActive and not tutorialActive then
            if IsControlJustReleased(0, 38) then -- E key
                ShowLSDOTMenu()
            end
        else
            Wait(500)
        end
    end
end)

-- ─────────────────────────────────────────────
-- LIFECYCLE MANAGEMENT
-- ─────────────────────────────────────────────

--- Cancel the current tutorial (if running).
function CancelTutorial()
    if not tutorialActive then return end
    tutorialActive = false
    navigationMonitoring = false

    if backingDockZone and backingDockZone.remove then
        backingDockZone:remove()
        backingDockZone = nil
    end

    DeleteTutorialVehicles()

    SendNUIMessage({ action = 'tutorialHUD', data = { stage = 0 } })

    lib.notify({
        title = locale('cdl.tutorial_title'),
        description = locale('cdl.tutorial_cancelled'),
        type = 'inform',
    })
end

--- Get current tutorial stage.
---@return number stage Current stage number (0 if not in tutorial)
function GetCurrentTutorialStage()
    return tutorialActive and currentStage or 0
end

-- ─────────────────────────────────────────────
-- EVENT LISTENERS
-- ─────────────────────────────────────────────

--- Server confirms CDL issuance.
RegisterNetEvent('trucking:client:cdlIssued', function(data)
    if not data then return end
    lib.notify({
        title = locale('cdl.cdl_issued_title'),
        description = locale('cdl.cdl_issued_desc'):format(data.licenseType),
        type = 'success',
        duration = 8000,
    })
end)

--- Server confirms tutorial payout.
RegisterNetEvent('trucking:client:tutorialPayout', function(data)
    if not data then return end
    lib.notify({
        title = locale('cdl.tutorial_payout_title'),
        description = locale('cdl.tutorial_payout_desc'):format(data.amount or 850),
        type = 'success',
        duration = 8000,
    })
end)

--- Server sends credential/profile data (CDL status, licenses held)
RegisterNetEvent('trucking:client:credentials', function(data)
    if not data then return end
    SendNUIMessage({
        action = 'credentials',
        data = data,
    })
end)

--- Server confirms cert application result (endorsement applied)
RegisterNetEvent('trucking:client:certApplicationResult', function(data)
    if not data then return end
    if data.success then
        lib.notify({
            title = locale('cdl.certification_title'),
            description = locale('cdl.certification_added'):format(data.certType or locale('cdl.endorsement')),
            type = 'success',
            duration = 6000,
        })
    else
        lib.notify({
            title = locale('cdl.certification_failed_title'),
            description = data.reason or locale('cdl.application_not_approved'),
            type = 'error',
        })
    end
end)

--- Server starts the HAZMAT safety briefing
RegisterNetEvent('trucking:client:hazmatBriefingStarted', function(data)
    if not data then return end
    cdlTestActive = true
    SendNUIMessage({
        action = 'openHazmatBriefing',
        data = data,
    })
    SetNuiFocus(true, true)
end)

--- Server sends test results (grade/score)
RegisterNetEvent('trucking:client:testResults', function(data)
    if not data then return end
    cdlTestActive = false
    SetNuiFocus(false, false)
    SendNUIMessage({
        action = 'testResults',
        data = data,
    })
    local scorePct = (data.totalQuestions and data.totalQuestions > 0)
        and math.floor((data.score / data.totalQuestions) * 100)
        or 0
    if data.passed then
        lib.notify({
            title = locale('cdl.test_passed_title'),
            description = locale('cdl.test_passed_desc'):format(scorePct),
            type = 'success',
            duration = 8000,
        })
    else
        lib.notify({
            title = locale('cdl.test_failed_title'),
            description = locale('cdl.test_failed_desc'):format(scorePct),
            type = 'error',
            duration = 8000,
        })
    end
end)

--- Server reports test start failure (e.g. already licensed, locked out, insufficient funds)
RegisterNetEvent('trucking:client:cdlTestFailed', function(reason)
    cdlTestActive = false
    lib.notify({
        title = locale('cdl.cdl_test_title'),
        description = reason or locale('cdl.unable_to_start_test'),
        type = 'error',
    })
end)

--- Stop all monitoring on state cleanup.
AddEventHandler('trucking:client:stopAllMonitoring', function()
    CancelTutorial()
end)

-- ─────────────────────────────────────────────
-- RESOURCE CLEANUP
-- ─────────────────────────────────────────────
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    CancelTutorial()
    RemoveLSDOTNpc()

    if cdlTestActive then
        cdlTestActive = false
        SetNuiFocus(false, false)
    end

    if lsdotTextUIShowing then
        lib.hideTextUI()
        lsdotTextUIShowing = false
    end
end)
