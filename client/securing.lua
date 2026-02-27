--[[
    client/securing.lua — Cargo Securing Interactions
    Free Trucking — QBX Framework

    Responsibilities:
    - Sequential strap point interactions for flatbed and oversized loads
    - Standard flatbed (T1-02): 3 strap points x 4 seconds each
    - Oversized (T2-05): 4 strap points x 4 seconds + wheel chock check
    - Each point uses lib.progressBar hold interaction with animation
    - Points complete sequentially (next available after current completes)
    - Report each strap completion to server
    - GPS not set until all points complete
    - Visual markers at strap point locations on vehicle
    - Provide Start/Stop lifecycle management

    Authority model:
    - Client manages interaction flow and animations
    - Server validates strap completions and updates BOL/active load
    - Skipping results in BOL flagged as cargo not secured
]]

-- ─────────────────────────────────────────────
-- STATE
-- ─────────────────────────────────────────────
local securingActive = false
local currentStrapPoint = 0
local totalStrapPoints = 0
local allStrapsComplete = false
local needsWheelChock = false
local wheelChockComplete = false
local strapMarkers = {}
local securingBolId = nil

--- Strap point offset positions relative to trailer.
--- These define where each strap point marker appears on the vehicle.
--- Offsets are relative to the vehicle/trailer entity position.
local FLATBED_STRAP_OFFSETS = {
    vector3(0.0, 3.0, 0.8),    -- front strap
    vector3(0.0, 0.0, 0.8),    -- center strap
    vector3(0.0, -3.0, 0.8),   -- rear strap
}

local OVERSIZED_STRAP_OFFSETS = {
    vector3(-1.2, 3.5, 0.8),   -- front-left strap
    vector3(1.2, 3.5, 0.8),    -- front-right strap
    vector3(-1.2, -3.0, 0.8),  -- rear-left strap
    vector3(1.2, -3.0, 0.8),   -- rear-right strap
}

local WHEEL_CHOCK_OFFSET = vector3(0.0, -4.5, 0.2) -- behind trailer rear

-- ─────────────────────────────────────────────
-- STRAP POINT MARKERS
-- ─────────────────────────────────────────────

--- Draw markers at each strap point location on the trailer.
--- Active point is highlighted green, completed points are blue,
--- future points are grey.
---@param vehicle number The trailer entity handle
---@param offsets table Array of vector3 offsets
local function DrawStrapMarkers(vehicle, offsets)
    if not vehicle or vehicle == 0 then return end
    if not DoesEntityExist(vehicle) then return end

    for i, offset in ipairs(offsets) do
        local worldPos = GetOffsetFromEntityInWorldCoords(vehicle, offset.x, offset.y, offset.z)

        local r, g, b, a
        if i <= currentStrapPoint then
            -- Completed: blue
            r, g, b, a = 0, 100, 255, 180
        elseif i == currentStrapPoint + 1 then
            -- Active/next: green pulsing
            r, g, b, a = 0, 255, 100, 200
        else
            -- Future: grey
            r, g, b, a = 150, 150, 150, 100
        end

        DrawMarker(
            1,                  -- type: cylinder
            worldPos.x, worldPos.y, worldPos.z - 0.5,
            0.0, 0.0, 0.0,     -- direction
            0.0, 0.0, 0.0,     -- rotation
            0.5, 0.5, 1.0,     -- scale
            r, g, b, a,
            false,              -- bobUpAndDown
            false,              -- faceCamera
            2,                  -- p19 (draw on entity)
            false,              -- rotate
            nil, nil,           -- textureDict, textureName
            false               -- drawOnEnts
        )
    end

    -- Wheel chock marker (for oversized only)
    if needsWheelChock and not wheelChockComplete then
        local chockPos = GetOffsetFromEntityInWorldCoords(vehicle,
            WHEEL_CHOCK_OFFSET.x, WHEEL_CHOCK_OFFSET.y, WHEEL_CHOCK_OFFSET.z)

        local cr, cg, cb, ca
        if currentStrapPoint >= totalStrapPoints then
            -- All straps done, chock is next: yellow
            cr, cg, cb, ca = 255, 200, 0, 200
        else
            -- Not yet available: grey
            cr, cg, cb, ca = 150, 150, 150, 80
        end

        DrawMarker(
            1,
            chockPos.x, chockPos.y, chockPos.z,
            0.0, 0.0, 0.0,
            0.0, 0.0, 0.0,
            0.4, 0.4, 0.4,
            cr, cg, cb, ca,
            false, false, 2, false,
            nil, nil, false
        )
    end
end

-- ─────────────────────────────────────────────
-- STRAP INTERACTION
-- ─────────────────────────────────────────────

--- Perform a single strap point interaction.
--- Uses lib.progressBar with hold behavior and an animation.
---@param pointNumber number The strap point index (1-based)
---@param vehicle number The trailer entity
---@param offsets table The strap point offsets array
---@return boolean success True if the strap was completed
local function DoStrapPoint(pointNumber, vehicle, offsets)
    if not vehicle or vehicle == 0 then return false end
    if not DoesEntityExist(vehicle) then return false end

    -- Walk player to the strap point
    local offset = offsets[pointNumber]
    if not offset then return false end

    local targetPos = GetOffsetFromEntityInWorldCoords(vehicle, offset.x, offset.y, offset.z)
    local playerPos = GetEntityCoords(PlayerPedId())
    local dist = #(playerPos - targetPos)

    -- Check proximity — player must be near the strap point
    if dist > 3.0 then
        lib.notify({
            title = 'Cargo Securing',
            description = 'Move closer to strap point #' .. pointNumber,
            type = 'inform',
        })
        return false
    end

    local strapDuration = Config.StrapDurationMs or 4000

    local success = lib.progressBar({
        duration = strapDuration,
        label = 'Securing strap point ' .. pointNumber .. '/' .. totalStrapPoints,
        useWhileDead = false,
        canCancel = true,
        disable = {
            move = true,
            car = true,
            combat = true,
        },
        anim = {
            dict = 'anim@heists@ornate_bank@hack',
            clip = 'hack_enter',
            flag = 49,
        },
    })

    if success then
        currentStrapPoint = pointNumber
        TriggerServerEvent('trucking:server:strapComplete', securingBolId, pointNumber)

        lib.notify({
            title = 'Strap Secured',
            description = 'Point ' .. pointNumber .. '/' .. totalStrapPoints .. ' secured.',
            type = 'success',
            duration = 3000,
        })

        -- Play confirmation sound
        PlaySoundFrontend(-1, 'Hack_Success', 'DLC_HEIST_BIOLAB_PREP_HACKING_SOUNDS', true)
        return true
    else
        lib.notify({
            title = 'Strap Cancelled',
            description = 'Strap point ' .. pointNumber .. ' was not secured.',
            type = 'warning',
        })
        return false
    end
end

--- Perform the wheel chock check interaction (oversized loads only).
---@param vehicle number The trailer entity
---@return boolean success
local function DoWheelChock(vehicle)
    if not vehicle or vehicle == 0 then return false end

    local chockPos = GetOffsetFromEntityInWorldCoords(vehicle,
        WHEEL_CHOCK_OFFSET.x, WHEEL_CHOCK_OFFSET.y, WHEEL_CHOCK_OFFSET.z)
    local playerPos = GetEntityCoords(PlayerPedId())
    local dist = #(playerPos - chockPos)

    if dist > 3.0 then
        lib.notify({
            title = 'Cargo Securing',
            description = 'Move closer to the wheel chock position.',
            type = 'inform',
        })
        return false
    end

    local success = lib.progressBar({
        duration = Config.StrapDurationMs or 4000,
        label = 'Installing wheel chocks',
        useWhileDead = false,
        canCancel = true,
        disable = {
            move = true,
            car = true,
            combat = true,
        },
        anim = {
            dict = 'anim@heists@ornate_bank@hack',
            clip = 'hack_enter',
            flag = 49,
        },
    })

    if success then
        wheelChockComplete = true
        TriggerServerEvent('trucking:server:wheelChockComplete', securingBolId)

        lib.notify({
            title = 'Wheel Chocks Installed',
            description = 'All securing points complete.',
            type = 'success',
            duration = 3000,
        })
        return true
    else
        lib.notify({
            title = 'Wheel Chock Cancelled',
            description = 'Wheel chock installation was interrupted.',
            type = 'warning',
        })
        return false
    end
end

-- ─────────────────────────────────────────────
-- MAIN SECURING SEQUENCE
-- ─────────────────────────────────────────────

--- Run the full cargo securing sequence for the current load.
--- Prompts the player through each strap point sequentially,
--- then the wheel chock if applicable.
---@param activeLoad table The active load data
---@param vehicle number The trailer/vehicle entity
local function RunSecuringSequence(activeLoad, vehicle)
    if not activeLoad or not vehicle or vehicle == 0 then return end

    securingBolId = activeLoad.bol_id
    local isOversized = activeLoad.cargo_type == 'oversized'
        or activeLoad.cargo_type == 'oversized_heavy'
    local offsets

    if isOversized then
        totalStrapPoints = Config.OversizedStrapPoints or 4
        offsets = OVERSIZED_STRAP_OFFSETS
        needsWheelChock = true
    else
        totalStrapPoints = Config.FlatbedStrapPoints or 3
        offsets = FLATBED_STRAP_OFFSETS
        needsWheelChock = false
    end

    currentStrapPoint = 0
    allStrapsComplete = false
    wheelChockComplete = false

    lib.notify({
        title = 'Cargo Securing Required',
        description = totalStrapPoints .. ' strap points to secure.'
            .. (needsWheelChock and ' Wheel chock required.' or '')
            .. '\nApproach each green marker.',
        type = 'inform',
        duration = 8000,
    })

    -- Marker drawing thread
    local markerActive = true
    CreateThread(function()
        while markerActive and securingActive do
            if DoesEntityExist(vehicle) then
                DrawStrapMarkers(vehicle, offsets)
            end
            Wait(0)
        end
    end)

    -- TextUI prompt thread
    local textUIActive = false
    CreateThread(function()
        while markerActive and securingActive do
            if not allStrapsComplete then
                local nextPoint = currentStrapPoint + 1
                if nextPoint <= totalStrapPoints then
                    local offset = offsets[nextPoint]
                    if offset and DoesEntityExist(vehicle) then
                        local targetPos = GetOffsetFromEntityInWorldCoords(vehicle,
                            offset.x, offset.y, offset.z)
                        local playerPos = GetEntityCoords(PlayerPedId())
                        local dist = #(playerPos - targetPos)
                        if dist <= 3.0 then
                            if not textUIActive then
                                textUIActive = true
                                lib.showTextUI('[E] Secure strap point #' .. nextPoint, {
                                    position = 'right-center',
                                    icon = 'link',
                                })
                            end
                        else
                            if textUIActive then
                                textUIActive = false
                                lib.hideTextUI()
                            end
                        end
                    end
                elseif needsWheelChock and not wheelChockComplete then
                    local chockPos = GetOffsetFromEntityInWorldCoords(vehicle,
                        WHEEL_CHOCK_OFFSET.x, WHEEL_CHOCK_OFFSET.y, WHEEL_CHOCK_OFFSET.z)
                    local playerPos = GetEntityCoords(PlayerPedId())
                    local dist = #(playerPos - chockPos)
                    if dist <= 3.0 then
                        if not textUIActive then
                            textUIActive = true
                            lib.showTextUI('[E] Install wheel chock', {
                                position = 'right-center',
                                icon = 'cog',
                            })
                        end
                    else
                        if textUIActive then
                            textUIActive = false
                            lib.hideTextUI()
                        end
                    end
                end
            end
            Wait(200)
        end
        if textUIActive then
            lib.hideTextUI()
        end
    end)

    -- Input handling thread
    CreateThread(function()
        while securingActive and not allStrapsComplete do
            Wait(0)
            if IsControlJustReleased(0, 38) then -- E key
                local nextPoint = currentStrapPoint + 1
                if nextPoint <= totalStrapPoints then
                    local success = DoStrapPoint(nextPoint, vehicle, offsets)
                    if not success then
                        -- Player cancelled or was too far, try again
                    end
                elseif needsWheelChock and not wheelChockComplete then
                    DoWheelChock(vehicle)
                end

                -- Check completion
                if currentStrapPoint >= totalStrapPoints
                    and (not needsWheelChock or wheelChockComplete) then
                    allStrapsComplete = true
                end
            end
        end

        -- All securing complete
        markerActive = false

        if allStrapsComplete then
            TriggerServerEvent('trucking:server:cargoFullySecured', securingBolId)

            lib.notify({
                title = 'Cargo Secured',
                description = 'All securing points complete. GPS destination set.',
                type = 'success',
                duration = 5000,
            })

            PlaySoundFrontend(-1, 'Mission_Pass_Notify', 'DLC_HEISTS_GENERAL_FRONTEND_SOUNDS', true)

            -- Signal that GPS can now be set
            TriggerEvent('trucking:client:securingComplete')
        end

        securingActive = false
    end)
end

-- ─────────────────────────────────────────────
-- LIFECYCLE MANAGEMENT
-- ─────────────────────────────────────────────

--- Start the cargo securing process for the current load.
--- Determines if the load requires securing (flatbed or oversized)
--- and initiates the interaction sequence.
---@param activeLoad table The active load data from server
function StartCargoSecuring(activeLoad)
    if securingActive then return end
    if not activeLoad then return end

    -- Determine if this load needs securing
    local requiresSecuring = activeLoad.cargo_type == 'oversized'
        or activeLoad.cargo_type == 'oversized_heavy'
        or activeLoad.cargo_type == 'building_materials'
        or activeLoad.requires_securing

    if not requiresSecuring then return end

    securingActive = true

    -- Find the player's vehicle or attached trailer
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if not vehicle or vehicle == 0 then
        -- Player might be standing outside near the trailer
        vehicle = GetVehiclePedIsIn(ped, true) -- last vehicle
    end

    -- Try to find attached trailer
    local trailer = nil
    if vehicle and vehicle ~= 0 then
        local hasTrailer, trailerEntity = GetVehicleTrailerVehicle(vehicle)
        if hasTrailer and trailerEntity ~= 0 then
            trailer = trailerEntity
        end
    end

    -- Use trailer if available, otherwise use vehicle
    local targetVehicle = trailer or vehicle
    if not targetVehicle or targetVehicle == 0 then
        lib.notify({
            title = 'Cargo Securing',
            description = 'No vehicle or trailer found nearby.',
            type = 'error',
        })
        securingActive = false
        return
    end

    RunSecuringSequence(activeLoad, targetVehicle)
end

--- Stop the cargo securing process and clean up.
--- If called before completion, the cargo is flagged as not secured.
function StopCargoSecuring()
    if not securingActive then return end

    securingActive = false
    allStrapsComplete = false
    currentStrapPoint = 0
    totalStrapPoints = 0
    needsWheelChock = false
    wheelChockComplete = false
    securingBolId = nil

    lib.hideTextUI()
end

--- Check if cargo securing is complete for the current load.
---@return boolean secured
function IsCargoSecured()
    return allStrapsComplete
end

--- Check if cargo securing is currently in progress.
---@return boolean active
function IsSecuringActive()
    return securingActive
end

-- ─────────────────────────────────────────────
-- EVENT LISTENERS
-- ─────────────────────────────────────────────

--- Server confirms cargo secured status (e.g., after reconnect restore).
RegisterNetEvent('trucking:client:cargoSecuredConfirm', function(data)
    if not data then return end
    if data.secured then
        allStrapsComplete = true
        securingActive = false
    end
end)

--- Stop all monitoring on state cleanup.
AddEventHandler('trucking:client:stopAllMonitoring', function()
    StopCargoSecuring()
end)

-- ─────────────────────────────────────────────
-- RESOURCE CLEANUP
-- ─────────────────────────────────────────────
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    StopCargoSecuring()
end)
