--[[
    client/interactions.lua — All NPC and World Interactions
    Free Trucking — QBX Framework

    Responsibilities:
    - Shipper NPC zones (lib.zones.sphere at each shipper coord)
    - Loading dock interaction (reefer temp confirm, BOL signing, departure)
    - Delivery NPC interaction (arrival confirmation, BOL review, payout display)
    - Pre-trip inspection (4 checkpoints, ~45 seconds total)
    - Cargo securing (flatbed/oversized strap points)
    - Manifest verification (lib.inputDialog)
    - Insurance purchase terminal interactions
    - Truck stop repair bay, board terminal
    - Weigh station interaction zone
    - All NPC conversations use ox_lib context menus styled with Bears palette
]]

-- ─────────────────────────────────────────────
-- LOCAL STATE
-- ─────────────────────────────────────────────
local shipperZones = {}
local truckStopZones = {}
local weighStationZones = {}
local insuranceZones = {}
local nearShipper = nil
local reeferConfirmed = false

-- ─────────────────────────────────────────────
-- SHIPPER NPC ZONES
-- ─────────────────────────────────────────────
--- Create interaction zones at every shipper location.
--- onEnter shows textUI prompt, interaction opens board/loads.
CreateThread(function()
    if not Shippers then
        -- Wait for shared config to load
        while not Shippers do Wait(500) end
    end

    for shipperId, shipper in pairs(Shippers) do
        if shipper.coords then
            local zone = lib.zones.sphere({
                coords = shipper.coords,
                radius = 3.0,
                debug = false,
                onEnter = function()
                    nearShipper = shipperId
                    lib.showTextUI('[E] Talk to ' .. (shipper.label or 'Shipper'), {
                        icon = 'fas fa-truck-loading',
                    })
                end,
                onExit = function()
                    nearShipper = nil
                    lib.hideTextUI()
                end,
                inside = function()
                    if IsControlJustReleased(0, 38) then -- E key
                        OpenShipperInteraction(shipperId, shipper)
                    end
                end,
            })
            shipperZones[shipperId] = zone
        end
    end
end)

--- Open shipper NPC context menu
---@param shipperId string Shipper identifier
---@param shipper table Shipper data from config
function OpenShipperInteraction(shipperId, shipper)
    if not IsPlayerLoggedIn() then return end

    local options = {
        {
            title = shipper.label or 'Shipper',
            description = 'Region: ' .. (shipper.region or 'unknown')
                .. ' | Tiers: ' .. (shipper.tier_range and (shipper.tier_range[1] .. '-' .. shipper.tier_range[2]) or '?'),
            disabled = true,
            icon = 'fas fa-building',
        },
        {
            title = 'View Available Loads',
            description = 'Browse loads from this shipper',
            icon = 'fas fa-clipboard-list',
            onSelect = function()
                TriggerServerEvent('trucking:server:openBoard', shipper.region, shipperId)
                if Config.UseStandaloneNUI then
                    OpenTruckingNUI()
                end
            end,
        },
    }

    -- If player has an active load from this shipper and is at_origin, show dock interaction
    if ActiveLoad and ActiveBOL and ActiveBOL.shipper_id == shipperId and ActiveLoad.status == 'at_origin' then
        table.insert(options, {
            title = 'Loading Dock',
            description = 'Proceed to loading dock for cargo',
            icon = 'fas fa-dolly',
            onSelect = function()
                OpenLoadingDockInteraction()
            end,
        })
    end

    lib.registerContext({
        id = 'trucking_shipper_' .. shipperId,
        title = shipper.label or 'Shipper',
        options = options,
    })
    lib.showContext('trucking_shipper_' .. shipperId)
end

-- ─────────────────────────────────────────────
-- LOADING DOCK INTERACTION
-- ─────────────────────────────────────────────
--- Context menu for loading dock: reefer temp confirm, BOL signing, departure.
function OpenLoadingDockInteraction()
    if not ActiveLoad or not ActiveBOL then return end
    reeferConfirmed = false

    local isReefer = ActiveBOL.temp_required_min ~= nil
    local isFlatbed = IsFlatbedCargo(ActiveBOL.cargo_type)
    local options = {}

    -- Step 1: Pre-trip inspection (if not completed)
    if not ActiveLoad.pre_trip_completed then
        table.insert(options, {
            title = 'Pre-Trip Inspection',
            description = 'Inspect vehicle before departure (~45 seconds)',
            icon = 'fas fa-search',
            onSelect = function()
                StartPreTripInspection()
            end,
        })
    else
        table.insert(options, {
            title = 'Pre-Trip Complete',
            description = 'Vehicle inspection passed',
            icon = 'fas fa-check-circle',
            disabled = true,
        })
    end

    -- Step 2: Reefer temperature confirmation (if applicable)
    if isReefer then
        table.insert(options, {
            title = '"Reefer set to ' .. ActiveBOL.temp_required_min .. '\194\176F?"',
            description = '',
            disabled = true,
            icon = 'fas fa-thermometer-half',
        })
        table.insert(options, {
            title = 'Confirm Temperature',
            description = 'Verify reefer unit is set to correct range',
            icon = 'fas fa-check',
            onSelect = function()
                reeferConfirmed = true
                TriggerServerEvent('trucking:server:confirmReeferTemp', ActiveLoad.bol_id)
                lib.notify({
                    title = 'Temperature Confirmed',
                    description = 'Reefer set to ' .. ActiveBOL.temp_required_min
                        .. '-' .. ActiveBOL.temp_required_max .. '\194\176F',
                    type = 'success',
                })
                -- Re-open dock interaction with updated state
                Wait(500)
                OpenLoadingDockInteraction()
            end,
        })
    end

    -- Step 3: Manifest verification
    if not ActiveLoad.manifest_verified then
        table.insert(options, {
            title = 'Verify Manifest',
            description = 'Cross-check cargo manifest details',
            icon = 'fas fa-file-alt',
            onSelect = function()
                StartManifestVerification()
            end,
        })
    else
        table.insert(options, {
            title = 'Manifest Verified',
            description = 'All cargo details confirmed',
            icon = 'fas fa-check-circle',
            disabled = true,
        })
    end

    -- Step 4: Cargo securing (flatbed/oversized only)
    if isFlatbed and not ActiveLoad.cargo_secured then
        table.insert(options, {
            title = 'Secure Cargo',
            description = 'Strap down flatbed cargo before departure',
            icon = 'fas fa-link',
            onSelect = function()
                StartCargoSecuring()
            end,
        })
    elseif isFlatbed and ActiveLoad.cargo_secured then
        table.insert(options, {
            title = 'Cargo Secured',
            description = 'All strap points fastened',
            icon = 'fas fa-check-circle',
            disabled = true,
        })
    end

    -- Step 5: Sign BOL and depart
    local canDepart = true
    local departDesc = 'Sign your Bill of Lading and depart'
    if isReefer and not reeferConfirmed and not ActiveLoad.temp_monitoring_active then
        canDepart = false
        departDesc = 'Must confirm reefer temperature first'
    end
    if isFlatbed and not ActiveLoad.cargo_secured then
        canDepart = false
        departDesc = 'Must secure cargo before departure'
    end

    table.insert(options, {
        title = 'Sign BOL & Depart',
        description = departDesc,
        icon = 'fas fa-signature',
        disabled = not canDepart,
        onSelect = function()
            TriggerServerEvent('trucking:server:signBOL', ActiveLoad.bol_id)
        end,
    })

    -- Step 6: Abandon load
    table.insert(options, {
        title = 'Abandon Load',
        description = 'Cancel this load (deposit may be forfeited)',
        icon = 'fas fa-times-circle',
        onSelect = function()
            local confirm = lib.alertDialog({
                header = 'Abandon Load?',
                content = 'Are you sure you want to abandon BOL #'
                    .. (ActiveBOL.bol_number or '?')
                    .. '?\n\nYour deposit of $' .. (ActiveLoad.deposit_posted or 0)
                    .. ' may be forfeited and your reputation will be impacted.',
                centered = true,
                cancel = true,
            })
            if confirm == 'confirm' then
                TriggerServerEvent('trucking:server:loadAbandoned', ActiveLoad.bol_id)
            end
        end,
    })

    lib.registerContext({
        id = 'trucking_loading_dock',
        title = 'Dock Supervisor \194\183 ' .. (ActiveBOL.shipper_name or 'Loading Dock'),
        options = options,
    })
    lib.showContext('trucking_loading_dock')
end

-- ─────────────────────────────────────────────
-- PRE-TRIP INSPECTION
-- ─────────────────────────────────────────────
--- Runs 4 sequential checkpoints: tires, lights, brakes, coupling/latch.
--- Each checkpoint is a 3-second progress bar. Total ~45 seconds with transitions.
function StartPreTripInspection()
    if not ActiveLoad then return end

    local checkpoints = {
        { label = 'Inspecting tires and wheel condition',    dict = 'amb@medic@standing@kneel@base', clip = 'base' },
        { label = 'Checking lights and signals',             dict = 'amb@medic@standing@tendtodead@base', clip = 'base' },
        { label = 'Testing brake system',                    dict = 'anim@heists@ornate_bank@hack', clip = 'hack_enter' },
        { label = 'Verifying coupling and latch mechanism',  dict = 'mini@repair', clip = 'fixing_a_ped' },
    }

    local allPassed = true

    for i, checkpoint in ipairs(checkpoints) do
        local success = lib.progressBar({
            duration = 3000,
            label = checkpoint.label .. ' (' .. i .. '/' .. #checkpoints .. ')',
            useWhileDead = false,
            canCancel = true,
            disable = {
                move = true,
                car = true,
                combat = true,
            },
            anim = {
                dict = checkpoint.dict,
                clip = checkpoint.clip,
                flag = 49,
            },
        })

        if not success then
            allPassed = false
            lib.notify({
                title = 'Pre-Trip Cancelled',
                description = 'Inspection was interrupted at checkpoint ' .. i,
                type = 'error',
            })
            break
        end

        -- Brief pause between checkpoints
        if i < #checkpoints then
            Wait(500)
        end
    end

    if allPassed then
        TriggerServerEvent('trucking:server:preTripComplete', ActiveLoad.bol_id)
        lib.notify({
            title = 'Pre-Trip Complete',
            description = 'Vehicle passed all 4 inspection checkpoints',
            type = 'success',
        })
    end
end

-- ─────────────────────────────────────────────
-- CARGO SECURING
-- ─────────────────────────────────────────────
--- Strap points for flatbed and oversized loads.
--- Each point is a 4-second hold interaction. Points must complete sequentially.
function StartCargoSecuring()
    if not ActiveLoad or not ActiveBOL then return end

    local totalPoints = GetStrapPointCount(ActiveBOL.cargo_type)
    local isOversized = IsOversizedCargo(ActiveBOL.cargo_type)

    for pointNumber = 1, totalPoints do
        local success = lib.progressBar({
            duration = Config.StrapDurationMs or 4000,
            label = 'Securing strap point ' .. pointNumber .. ' of ' .. totalPoints,
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

        if not success then
            lib.notify({
                title = 'Securing Interrupted',
                description = 'Strap point ' .. pointNumber .. ' was not completed',
                type = 'error',
            })
            return
        end

        TriggerServerEvent('trucking:server:strapComplete', ActiveLoad.bol_id, pointNumber)

        lib.notify({
            title = 'Strap Point ' .. pointNumber .. '/' .. totalPoints,
            description = 'Secured',
            type = 'success',
        })

        -- Brief pause between strap points
        if pointNumber < totalPoints then
            Wait(500)
        end
    end

    -- Wheel chock check for oversized wheeled equipment
    if isOversized then
        local chockSuccess = lib.progressBar({
            duration = 3000,
            label = 'Checking wheel chocks',
            useWhileDead = false,
            canCancel = true,
            disable = {
                move = true,
                car = true,
                combat = true,
            },
            anim = {
                dict = 'amb@medic@standing@kneel@base',
                clip = 'base',
                flag = 49,
            },
        })

        if not chockSuccess then
            lib.notify({
                title = 'Wheel Chock Check Interrupted',
                type = 'error',
            })
            return
        end
    end

    TriggerServerEvent('trucking:server:cargoSecured', ActiveLoad.bol_id)

    lib.notify({
        title = 'Cargo Secured',
        description = 'All ' .. totalPoints .. ' strap points fastened'
            .. (isOversized and ', wheel chocks verified' or ''),
        type = 'success',
    })
end

--- Get strap point count based on cargo type
---@param cargoType string
---@return number
function GetStrapPointCount(cargoType)
    if IsOversizedCargo(cargoType) then
        return Config.OversizedStrapPoints or 4
    end
    return Config.FlatbedStrapPoints or 3
end

--- Check if cargo requires flatbed securing
---@param cargoType string
---@return boolean
function IsFlatbedCargo(cargoType)
    if not cargoType then return false end
    local flatbedTypes = {
        building_materials = true,
        oversized = true,
        oversized_heavy = true,
    }
    return flatbedTypes[cargoType] == true
end

--- Check if cargo is oversized
---@param cargoType string
---@return boolean
function IsOversizedCargo(cargoType)
    if not cargoType then return false end
    return cargoType == 'oversized' or cargoType == 'oversized_heavy'
end

-- ─────────────────────────────────────────────
-- MANIFEST VERIFICATION
-- ─────────────────────────────────────────────
--- Input dialog for manifest data entry. Player cross-checks BOL details.
function StartManifestVerification()
    if not ActiveLoad or not ActiveBOL then return end

    local input = lib.inputDialog('Manifest Verification', {
        {
            type = 'input',
            label = 'BOL Number',
            description = 'Enter the BOL number from your paperwork',
            required = true,
            placeholder = 'e.g., 2041',
        },
        {
            type = 'input',
            label = 'Cargo Type',
            description = 'Confirm the cargo type listed',
            required = true,
            placeholder = 'e.g., Cold Chain',
        },
        {
            type = 'input',
            label = 'Destination',
            description = 'Confirm the delivery destination',
            required = true,
            placeholder = 'e.g., Humane Labs',
        },
    })

    if not input then
        lib.notify({
            title = 'Manifest Verification Cancelled',
            type = 'error',
        })
        return
    end

    -- Send to server for validation — server decides if manifest matches
    TriggerServerEvent('trucking:server:verifyManifest', ActiveLoad.bol_id, {
        bol_number = input[1],
        cargo_type = input[2],
        destination = input[3],
    })
end

--- Server response for manifest verification
RegisterNetEvent('trucking:client:manifestResult', function(data)
    if not data then return end
    if data.verified then
        lib.notify({
            title = 'Manifest Verified',
            description = 'All details match — compliance bonus applied',
            type = 'success',
        })
    else
        lib.notify({
            title = 'Manifest Discrepancy',
            description = data.reason or 'Details did not match BOL records',
            type = 'error',
        })
    end
end)

-- ─────────────────────────────────────────────
-- DELIVERY NPC INTERACTION
-- ─────────────────────────────────────────────
--- Called when player enters delivery zone and interacts with destination NPC.
function OpenDeliveryInteraction()
    if not ActiveLoad or not ActiveBOL then return end

    local integrity = ActiveLoad.cargo_integrity or 100
    local integrityColor = integrity >= 90 and 'green' or (integrity >= 50 and 'orange' or 'red')

    local options = {
        {
            title = 'BOL #' .. (ActiveBOL.bol_number or '?'),
            description = 'Cargo: ' .. (ActiveBOL.cargo_type or 'unknown')
                .. ' | Integrity: ' .. integrity .. '%',
            disabled = true,
            icon = 'fas fa-file-invoice',
        },
    }

    -- Show seal status
    if ActiveLoad.seal_status then
        local sealIcon = ActiveLoad.seal_status == 'sealed' and 'fas fa-lock' or 'fas fa-lock-open'
        local sealDesc = ActiveLoad.seal_status == 'sealed' and 'Seal intact' or 'SEAL BROKEN'
        table.insert(options, {
            title = 'Seal Status: ' .. ActiveLoad.seal_status:upper(),
            description = sealDesc,
            icon = sealIcon,
            disabled = true,
        })
    end

    -- Show temperature compliance for reefer
    if ActiveBOL.temp_required_min then
        local tempDesc = 'Current: ' .. (ActiveLoad.current_temp_f or '?') .. '\194\176F'
        if ActiveLoad.excursion_active then
            tempDesc = tempDesc .. ' [EXCURSION ACTIVE]'
        end
        table.insert(options, {
            title = 'Temperature Compliance',
            description = tempDesc,
            icon = 'fas fa-thermometer-half',
            disabled = true,
        })
    end

    -- Confirm delivery button
    if integrity >= (Config.IntegrityRejectionThreshold or 40) then
        table.insert(options, {
            title = 'Confirm Delivery',
            description = 'Hand over BOL and cargo to receiving dock',
            icon = 'fas fa-check-double',
            onSelect = function()
                TriggerServerEvent('trucking:server:loadDelivered', ActiveLoad.bol_id)
            end,
        })
    else
        table.insert(options, {
            title = 'Load Rejected',
            description = 'Cargo integrity is below ' .. (Config.IntegrityRejectionThreshold or 40)
                .. '% — receiver is refusing the shipment',
            icon = 'fas fa-ban',
            disabled = true,
        })
        table.insert(options, {
            title = 'Acknowledge Rejection',
            description = 'Accept that this load has been refused',
            icon = 'fas fa-times',
            onSelect = function()
                TriggerServerEvent('trucking:server:loadRejected', ActiveLoad.bol_id)
            end,
        })
    end

    lib.registerContext({
        id = 'trucking_delivery',
        title = 'Receiving Dock \194\183 ' .. (ActiveBOL.destination_label or 'Destination'),
        options = options,
    })
    lib.showContext('trucking_delivery')
end

-- ─────────────────────────────────────────────
-- INSURANCE PURCHASE TERMINAL
-- ─────────────────────────────────────────────
--- Insurance terminal locations: Vapid office and truck stop insurance terminals.
--- Defined in config; zones created on resource start.

--- Create insurance terminal zones
CreateThread(function()
    -- Wait for config
    while not Config do Wait(500) end

    -- Vapid Commercial Insurance offices
    local insuranceLocations = Config.InsuranceLocations or {
        { label = 'Vapid Commercial Insurance', coords = vector3(-157.0, -302.0, 40.0) },  -- placeholder
    }

    for i, loc in ipairs(insuranceLocations) do
        insuranceZones[i] = lib.zones.sphere({
            coords = loc.coords,
            radius = 2.5,
            debug = false,
            onEnter = function()
                lib.showTextUI('[E] ' .. loc.label, {
                    icon = 'fas fa-shield-alt',
                })
            end,
            onExit = function()
                lib.hideTextUI()
            end,
            inside = function()
                if IsControlJustReleased(0, 38) then -- E key
                    OpenInsuranceTerminal(loc)
                end
            end,
        })
    end
end)

--- Open insurance purchase context menu
---@param location table Location data with label
function OpenInsuranceTerminal(location)
    if not IsPlayerLoggedIn() then return end

    lib.registerContext({
        id = 'trucking_insurance',
        title = 'Insurance Agent \194\183 ' .. (location.label or 'Insurance'),
        options = {
            {
                title = '"Need coverage today?"',
                description = '',
                disabled = true,
                icon = 'fas fa-user-tie',
            },
            {
                title = 'Single Load Policy',
                description = '8% of load value — covers next accepted load only',
                icon = 'fas fa-file-contract',
                onSelect = function()
                    TriggerServerEvent('trucking:server:insurancePurchase', 'single_load')
                end,
            },
            {
                title = 'Day Policy',
                description = '$200-$1,800 by tier — all loads for 24 hours',
                icon = 'fas fa-calendar-day',
                onSelect = function()
                    OpenInsuranceTierSelect('day')
                end,
            },
            {
                title = 'Week Policy',
                description = '$1,000-$9,500 by tier — all loads for 7 days',
                icon = 'fas fa-calendar-week',
                onSelect = function()
                    OpenInsuranceTierSelect('week')
                end,
            },
            {
                title = 'File a Claim',
                description = 'File an insurance claim on a BOL from your inventory',
                icon = 'fas fa-file-medical',
                onSelect = function()
                    TriggerEvent('trucking:client:openClaimInteraction')
                end,
            },
            {
                title = 'Leave',
                icon = 'fas fa-door-open',
                onSelect = function()
                    lib.hideContext()
                end,
            },
        },
    })
    lib.showContext('trucking_insurance')
end

--- Tier selection for day/week insurance policies
---@param policyType string 'day' or 'week'
function OpenInsuranceTierSelect(policyType)
    local rates = policyType == 'day' and Economy.InsuranceDayRates or Economy.InsuranceWeekRates
    local label = policyType == 'day' and 'Day' or 'Week'

    if not rates then
        lib.notify({ title = 'Error', description = 'Rate data not available', type = 'error' })
        return
    end

    local options = {}
    for tier = 0, 3 do
        local cost = rates[tier]
        if cost then
            table.insert(options, {
                title = 'Tier ' .. tier .. ' Coverage — $' .. cost,
                description = label .. ' policy covering Tier ' .. tier .. ' and below',
                icon = 'fas fa-shield-alt',
                onSelect = function()
                    local confirm = lib.alertDialog({
                        header = 'Purchase ' .. label .. ' Policy?',
                        content = 'Tier ' .. tier .. ' coverage for $' .. cost
                            .. '\n\nThis will cover all loads Tier ' .. tier .. ' and below for '
                            .. (policyType == 'day' and '24 hours' or '7 days') .. '.',
                        centered = true,
                        cancel = true,
                    })
                    if confirm == 'confirm' then
                        TriggerServerEvent('trucking:server:insurancePurchase', policyType, tier)
                    end
                end,
            })
        end
    end

    table.insert(options, {
        title = 'Back',
        icon = 'fas fa-arrow-left',
        onSelect = function()
            OpenInsuranceTerminal({ label = 'Insurance' })
        end,
    })

    lib.registerContext({
        id = 'trucking_insurance_tier',
        title = 'Select Coverage Tier \194\183 ' .. label .. ' Policy',
        menu = 'trucking_insurance',
        options = options,
    })
    lib.showContext('trucking_insurance_tier')
end

-- ─────────────────────────────────────────────
-- TRUCK STOP INTERACTIONS
-- ─────────────────────────────────────────────
--- Truck stop zones created from config. Each stop may have repair bay, board terminal, etc.

CreateThread(function()
    while not Config do Wait(500) end

    local stops = Config.TruckStops or {}

    for i, stop in ipairs(stops) do
        -- Board terminal zone
        if stop.hasTerminal and stop.terminalCoords then
            truckStopZones['terminal_' .. i] = lib.zones.box({
                coords = stop.terminalCoords,
                size = vec3(2, 2, 2),
                rotation = stop.terminalHeading or 0,
                debug = false,
                onEnter = function()
                    lib.showTextUI('[E] Freight Board Terminal', {
                        icon = 'fas fa-desktop',
                    })
                end,
                onExit = function()
                    lib.hideTextUI()
                end,
                inside = function()
                    if IsControlJustReleased(0, 38) then -- E key
                        TriggerServerEvent('trucking:server:openBoard', GetPlayerRegion())
                        if Config.UseStandaloneNUI then
                            OpenTruckingNUI()
                        end
                    end
                end,
            })
        end

        -- Repair bay zone
        if stop.hasRepairBay and stop.repairCoords then
            truckStopZones['repair_' .. i] = lib.zones.sphere({
                coords = stop.repairCoords,
                radius = 3.0,
                debug = false,
                onEnter = function()
                    lib.showTextUI('[E] Repair Bay', {
                        icon = 'fas fa-wrench',
                    })
                end,
                onExit = function()
                    lib.hideTextUI()
                end,
                inside = function()
                    if IsControlJustReleased(0, 38) then -- E key
                        OpenRepairBay(stop)
                    end
                end,
            })
        end

        -- Insurance terminal at full service stops
        if stop.hasInsurance and stop.insuranceCoords then
            truckStopZones['insurance_' .. i] = lib.zones.sphere({
                coords = stop.insuranceCoords,
                radius = 2.5,
                debug = false,
                onEnter = function()
                    lib.showTextUI('[E] Insurance Terminal', {
                        icon = 'fas fa-shield-alt',
                    })
                end,
                onExit = function()
                    lib.hideTextUI()
                end,
                inside = function()
                    if IsControlJustReleased(0, 38) then -- E key
                        OpenInsuranceTerminal({ label = stop.label or 'Truck Stop Insurance' })
                    end
                end,
            })
        end
    end
end)

-- ─────────────────────────────────────────────
-- REPAIR BAY
-- ─────────────────────────────────────────────
--- Check vehicle health, calculate cost, run progress bar for repair.
---@param stop table Truck stop config data
function OpenRepairBay(stop)
    if not IsPlayerLoggedIn() then return end

    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)

    if vehicle == 0 then
        -- Check for nearby vehicle
        vehicle = GetVehiclePedIsIn(ped, true)
        if vehicle == 0 then
            lib.notify({
                title = 'No Vehicle',
                description = 'You must be in or near a vehicle to use the repair bay',
                type = 'error',
            })
            return
        end
    end

    local healthBody = GetVehicleBodyHealth(vehicle)
    local healthEngine = GetVehicleEngineHealth(vehicle)
    local overallHealth = (healthBody + healthEngine) / 2.0

    -- Already at repair cap (80%)
    if overallHealth >= 800.0 then
        lib.notify({
            title = 'Vehicle OK',
            description = 'Your vehicle does not need repair at this bay',
            type = 'inform',
        })
        return
    end

    -- Calculate cost: $200-$500 scaled to damage
    local damagePct = 1.0 - (overallHealth / 1000.0)
    local repairCost = math.floor(200 + (damagePct * 300))

    local confirm = lib.alertDialog({
        header = 'Repair Bay \194\183 ' .. (stop.label or 'Truck Stop'),
        content = 'Vehicle Health: **' .. math.floor(overallHealth / 10) .. '%**\n'
            .. 'Repair Cost: **$' .. repairCost .. '**\n\n'
            .. 'This will repair your vehicle to 80% health.\n'
            .. 'For full repair, visit a proper mechanic.',
        centered = true,
        cancel = true,
    })

    if confirm ~= 'confirm' then return end

    -- Request server to deduct money
    TriggerServerEvent('trucking:server:truckStopRepair', repairCost, GetVehicleNumberPlateText(vehicle))

    -- Wait for server confirmation before repairing
end

--- Server confirms repair payment — apply repair
RegisterNetEvent('trucking:client:repairApproved', function(plate)
    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if vehicle == 0 then vehicle = GetVehiclePedIsIn(PlayerPedId(), true) end
    if vehicle == 0 then return end

    -- Verify plate matches
    local currentPlate = GetVehicleNumberPlateText(vehicle)
    if currentPlate and plate and currentPlate:gsub('%s+', '') ~= plate:gsub('%s+', '') then return end

    local success = lib.progressBar({
        duration = 15000,
        label = 'Repairing vehicle...',
        useWhileDead = false,
        canCancel = true,
        disable = {
            move = true,
            car = true,
            combat = true,
        },
        anim = {
            dict = 'mini@repair',
            clip = 'fixing_a_ped',
            flag = 49,
        },
    })

    if success then
        -- Repair to 80% cap
        SetVehicleBodyHealth(vehicle, 800.0)
        SetVehicleEngineHealth(vehicle, 800.0)
        SetVehicleFixed(vehicle)
        -- Cap at 800 after SetVehicleFixed (which sets to 1000)
        SetVehicleBodyHealth(vehicle, 800.0)
        SetVehicleEngineHealth(vehicle, 800.0)

        lib.notify({
            title = 'Repair Complete',
            description = 'Vehicle repaired to 80% health',
            type = 'success',
        })
    else
        lib.notify({
            title = 'Repair Cancelled',
            type = 'error',
        })
        -- Refund will be handled by server timeout/cancel event
        TriggerServerEvent('trucking:server:truckStopRepairCancelled', plate)
    end
end)

-- ─────────────────────────────────────────────
-- WEIGH STATION INTERACTION
-- ─────────────────────────────────────────────
--- Create weigh station zones from config. Entering triggers NPC inspection.

CreateThread(function()
    while not Config do Wait(500) end

    local stations = Config.WeighStationLocations or {}

    for i, station in ipairs(stations) do
        weighStationZones[i] = lib.zones.sphere({
            coords = station.coords,
            radius = 8.0,
            debug = false,
            onEnter = function()
                if ActiveLoad then
                    lib.showTextUI('[E] Weigh Station \194\183 ' .. station.label, {
                        icon = 'fas fa-balance-scale',
                    })
                end
            end,
            onExit = function()
                lib.hideTextUI()
            end,
            inside = function()
                if ActiveLoad and IsControlJustReleased(0, 38) then -- E key
                    OpenWeighStationInteraction(station, i)
                end
            end,
        })
    end
end)

--- Weigh station NPC inspection interaction
---@param station table Station config data
---@param stationIndex number Station index
function OpenWeighStationInteraction(station, stationIndex)
    if not ActiveLoad or not ActiveBOL then return end

    -- Check if already stamped
    if ActiveLoad.weigh_station_stamped then
        lib.notify({
            title = 'Already Stamped',
            description = 'This load has already been weighed and stamped',
            type = 'inform',
        })
        return
    end

    local options = {
        {
            title = '"Pull onto the scale, driver."',
            description = '',
            disabled = true,
            icon = 'fas fa-user-shield',
        },
        {
            title = 'BOL #' .. (ActiveBOL.bol_number or '?'),
            description = 'Weight: ' .. (ActiveBOL.weight_lbs or 0) .. ' lbs'
                .. ' | Cargo: ' .. (ActiveBOL.cargo_type or 'unknown'),
            disabled = true,
            icon = 'fas fa-file-invoice',
        },
    }

    -- HAZMAT check
    if ActiveBOL.hazmat_class then
        table.insert(options, {
            title = 'HAZMAT Placard: Class ' .. ActiveBOL.hazmat_class,
            description = 'Inspector verifying placard matches BOL',
            disabled = true,
            icon = 'fas fa-radiation',
        })
    end

    -- Temperature check for cold chain
    if ActiveBOL.temp_required_min then
        table.insert(options, {
            title = 'Temperature Compliance',
            description = 'Range: ' .. ActiveBOL.temp_required_min .. '-'
                .. ActiveBOL.temp_required_max .. '\194\176F',
            disabled = true,
            icon = 'fas fa-thermometer-half',
        })
    end

    -- Submit for inspection
    table.insert(options, {
        title = 'Submit for Inspection',
        description = 'Weigh vehicle and receive stamp (+5% compliance bonus)',
        icon = 'fas fa-stamp',
        onSelect = function()
            local success = lib.progressBar({
                duration = 5000,
                label = 'Inspector reviewing documents...',
                useWhileDead = false,
                canCancel = false,
                disable = {
                    move = true,
                    car = true,
                    combat = true,
                },
            })

            if success then
                TriggerServerEvent('trucking:server:weighStationStamp',
                    ActiveLoad.bol_id,
                    station.label,
                    GetPlayerRegion()
                )
            end
        end,
    })

    table.insert(options, {
        title = 'Drive through',
        description = 'Skip the weigh station',
        icon = 'fas fa-road',
        onSelect = function()
            lib.hideContext()
        end,
    })

    lib.registerContext({
        id = 'trucking_weigh_station',
        title = 'DOT Inspector \194\183 ' .. (station.label or 'Weigh Station'),
        options = options,
    })
    lib.showContext('trucking_weigh_station')
end

--- Server response for weigh station stamp
RegisterNetEvent('trucking:client:weighStationResult', function(data)
    if not data then return end
    if data.passed then
        lib.notify({
            title = 'Weigh Station Passed',
            description = 'Stamp issued — +5% compliance bonus applied',
            type = 'success',
        })
    else
        lib.notify({
            title = 'Weigh Station Issue',
            description = data.reason or 'Inspection noted a concern',
            type = 'error',
        })
    end
end)

-- ─────────────────────────────────────────────
-- BOL SIGNED / DEPARTURE CONFIRMATION
-- ─────────────────────────────────────────────
--- Server confirms BOL signed — transition to in_transit
RegisterNetEvent('trucking:client:bolSigned', function(data)
    if not data or not ActiveLoad then return end

    -- Update local state
    ActiveLoad.status = 'in_transit'
    ActiveLoad.departed_at = GetServerTime()

    if data.seal_number then
        ActiveLoad.seal_status = 'sealed'
        ActiveLoad.seal_number = data.seal_number
    end

    lib.notify({
        title = 'BOL Signed',
        description = 'Seal #' .. (data.seal_number or 'N/A') .. ' applied — proceed to destination',
        type = 'success',
    })

    -- Start all monitoring systems
    TriggerEvent('trucking:client:startMonitoring')
end)

-- ─────────────────────────────────────────────
-- CLEANUP ON RESOURCE STOP
-- ─────────────────────────────────────────────
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end

    -- Destroy all zones
    for _, zone in pairs(shipperZones) do
        if zone and zone.remove then zone:remove() end
    end
    for _, zone in pairs(truckStopZones) do
        if zone and zone.remove then zone:remove() end
    end
    for _, zone in pairs(weighStationZones) do
        if zone and zone.remove then zone:remove() end
    end
    for _, zone in pairs(insuranceZones) do
        if zone and zone.remove then zone:remove() end
    end

    lib.hideTextUI()
end)
