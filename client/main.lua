--[[
    client/main.lua — Client Initialization
    Free Trucking — QBX Framework

    Responsibilities:
    - PlayerData state tracking
    - Active load state (received from server on accept/restore)
    - RegisterNetEvent handlers for server-to-client events
    - NUI open/close management (F6 keybind + lb-phone app)
    - NUI callback registration for all screens
    - Player state cleanup on resource stop
]]

-- ─────────────────────────────────────────────
-- STATE
-- ─────────────────────────────────────────────
local PlayerData = {}
local isLoggedIn = false

--- Active load state — populated by server on accept or reconnect restore.
--- Never modified client-side except by server events.
ActiveLoad = nil

--- Active BOL record — shipped alongside ActiveLoad for display purposes.
ActiveBOL = nil

--- NUI visibility state
local nuiOpen = false

--- Player reputation cache (display only, not authoritative)
local cachedReputation = {
    score = 500,
    tier = 'developing',
}

-- ─────────────────────────────────────────────
-- PLAYER DATA TRACKING
-- ─────────────────────────────────────────────
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    PlayerData = exports.qbx_core:GetPlayerData() or {}
    isLoggedIn = true
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    PlayerData = {}
    isLoggedIn = false
    CleanupState()
end)

--- Utility: get player citizenid
function GetCitizenId()
    if PlayerData and PlayerData.citizenid then
        return PlayerData.citizenid
    end
    local pd = exports.qbx_core:GetPlayerData()
    if pd then
        PlayerData = pd
        return pd.citizenid
    end
    return nil
end

--- Utility: check if player is logged in
function IsPlayerLoggedIn()
    return isLoggedIn
end

--- Utility: get current server-synced time
function GetServerTime()
    return GlobalState.serverTime or 0
end

--- Utility: elapsed time helper (milliseconds)
function GetElapsed(startTimer)
    return GetGameTimer() - startTimer
end

--- Utility: get player's current region based on zone
function GetPlayerRegion()
    local coords = GetEntityCoords(PlayerPedId())
    -- Determine region based on Y coordinate (simplified GTA map zones)
    if coords.y > 5500 then
        return 'paleto'
    elseif coords.y > 3500 then
        return 'grapeseed'
    elseif coords.y > 1500 then
        return 'sandy_shores'
    else
        return 'los_santos'
    end
end

-- ─────────────────────────────────────────────
-- SERVER-TO-CLIENT EVENT HANDLERS
-- ─────────────────────────────────────────────

--- Restore active load after reconnect (crash recovery)
RegisterNetEvent('trucking:client:restoreActiveLoad', function(activeLoad, bol)
    if not activeLoad or not bol then return end

    ActiveLoad = activeLoad
    ActiveBOL = bol

    -- Resume monitoring systems based on load state
    if ActiveLoad.status == 'in_transit' or ActiveLoad.status == 'at_stop' then
        TriggerEvent('trucking:client:resumeMonitoring')
    end

    lib.notify({
        title = 'Load Restored',
        description = 'BOL #' .. (bol.bol_number or '?') .. ' has been restored',
        type = 'inform',
    })
end)

--- New load assigned (accepted from board)
RegisterNetEvent('trucking:client:loadAssigned', function(activeLoad, bol)
    if not activeLoad or not bol then return end

    ActiveLoad = activeLoad
    ActiveBOL = bol

    lib.notify({
        title = 'Load Accepted',
        description = 'BOL #' .. (bol.bol_number or '?') .. ' — ' .. (bol.cargo_type or 'unknown'),
        type = 'success',
    })

    -- Trigger mission start systems
    TriggerEvent('trucking:client:missionStart')
end)

--- Reputation update (display cache)
RegisterNetEvent('trucking:client:reputationUpdate', function(data)
    if not data then return end
    cachedReputation.score = data.score or cachedReputation.score
    cachedReputation.tier = data.tier or cachedReputation.tier

    -- Forward to NUI for profile display
    SendNUIMessage({
        action = 'reputationUpdate',
        data = data,
    })

    -- Notify on tier change
    if data.tierChanged then
        lib.notify({
            title = 'Reputation Updated',
            description = 'You are now ' .. (data.tier or 'unknown'),
            type = data.pointsChange and data.pointsChange > 0 and 'success' or 'error',
        })
    end
end)

--- Insurance claim paid notification
RegisterNetEvent('trucking:client:claimPaid', function(data)
    if not data then return end
    lib.notify({
        title = 'Insurance Claim Paid',
        description = '$' .. (data.amount or 0) .. ' deposited to your bank',
        type = 'success',
        duration = 8000,
    })
end)

--- Surge alert notification
RegisterNetEvent('trucking:client:surgeAlert', function(data)
    if not data then return end
    lib.notify({
        title = 'Surge Pricing Active',
        description = '+' .. (data.percentage or 0) .. '% on '
            .. (data.cargoFilter or 'all loads')
            .. ' in ' .. (data.region or 'your region'),
        type = 'inform',
        duration = 10000,
    })
end)

--- Board refresh notification
RegisterNetEvent('trucking:client:boardRefresh', function(data)
    if not data then return end
    -- Forward to NUI if board is open
    SendNUIMessage({
        action = 'boardRefresh',
        data = data,
    })
end)

--- Transfer offer received from another driver
RegisterNetEvent('trucking:client:transferOffer', function(data)
    if not data then return end
    local accept = lib.alertDialog({
        header = 'Load Transfer Offer',
        content = 'Driver **' .. (data.driverName or 'Unknown') .. '** wants to transfer BOL #'
            .. (data.bolNumber or '?') .. '\n\nCargo: ' .. (data.cargoType or 'unknown')
            .. '\nDestination: ' .. (data.destination or 'unknown')
            .. '\nPayout share: $' .. (data.estimatedPayout or 0),
        centered = true,
        cancel = true,
    })

    if accept == 'confirm' then
        TriggerServerEvent('trucking:server:acceptTransfer', data.bolId)
    end
end)

--- Direct load offer from dispatcher
RegisterNetEvent('trucking:client:directOffer', function(data)
    if not data then return end
    local accept = lib.alertDialog({
        header = 'Dispatch Offer',
        content = 'Your dispatcher is offering:\n\n'
            .. '**' .. (data.cargoType or 'unknown') .. '**\n'
            .. (data.origin or '?') .. ' -> ' .. (data.destination or '?')
            .. '\nEstimated payout: $' .. (data.estimatedPayout or 0),
        centered = true,
        cancel = true,
    })

    if accept == 'confirm' then
        TriggerServerEvent('trucking:server:acceptDirectOffer', data.loadId)
    end
end)

--- Convoy update (member positions, status)
RegisterNetEvent('trucking:client:convoyUpdate', function(data)
    if not data then return end
    -- Forward to HUD for convoy overlay
    SendNUIMessage({
        action = 'convoyUpdate',
        data = data,
    })
end)

--- Load state update from server (status changes, integrity, etc.)
RegisterNetEvent('trucking:client:loadStateUpdate', function(updates)
    if not ActiveLoad or not updates then return end

    for key, value in pairs(updates) do
        ActiveLoad[key] = value
    end

    -- Forward relevant updates to HUD
    TriggerEvent('trucking:client:hudUpdate')
end)

--- Load completed — cleanup client state
RegisterNetEvent('trucking:client:loadCompleted', function(data)
    if not data then return end

    lib.notify({
        title = 'Delivery Complete',
        description = 'BOL #' .. (data.bolNumber or '?') .. ' — Payout: $' .. (data.payout or 0),
        type = 'success',
        duration = 10000,
    })

    -- Show payout breakdown in NUI
    SendNUIMessage({
        action = 'payoutBreakdown',
        data = data,
    })

    CleanupState()
end)

--- Load failed (abandoned, stolen, expired, rejected)
RegisterNetEvent('trucking:client:loadFailed', function(data)
    if not data then return end

    local typeLabels = {
        abandoned = 'Load Abandoned',
        stolen = 'Load Stolen',
        expired = 'Delivery Window Expired',
        rejected = 'Load Rejected at Destination',
    }

    lib.notify({
        title = typeLabels[data.reason] or 'Load Failed',
        description = 'BOL #' .. (data.bolNumber or '?')
            .. (data.depositForfeited and ' — Deposit forfeited' or ''),
        type = 'error',
        duration = 10000,
    })

    CleanupState()
end)

-- ─────────────────────────────────────────────
-- NUI MANAGEMENT
-- ─────────────────────────────────────────────

--- Open the trucking NUI panel
function OpenTruckingNUI()
    if nuiOpen then return end
    nuiOpen = true
    SetNuiFocus(true, true)

    -- Gather data for NUI display
    local nuiData = {
        activeLoad = ActiveLoad,
        activeBOL = ActiveBOL,
        reputation = cachedReputation,
        region = GetPlayerRegion(),
    }

    SendNUIMessage({
        action = 'open',
        data = nuiData,
    })

    -- Request fresh board data from server
    TriggerServerEvent('trucking:server:openBoard', GetPlayerRegion())
end

--- Close the trucking NUI panel
function CloseTruckingNUI()
    if not nuiOpen then return end
    nuiOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

--- Check if NUI is currently open
function IsTruckingNUIOpen()
    return nuiOpen
end

-- ─────────────────────────────────────────────
-- F6 KEYBIND (STANDALONE NUI)
-- ─────────────────────────────────────────────
if Config.UseStandaloneNUI then
    RegisterCommand('+trucking_nui', function()
        if not isLoggedIn then return end
        if nuiOpen then
            CloseTruckingNUI()
        else
            OpenTruckingNUI()
        end
    end, false)

    RegisterKeyMapping('+trucking_nui', 'Open Trucking Panel', 'keyboard', Config.NUIKey or 'F6')
end

-- ─────────────────────────────────────────────
-- LB-PHONE INTEGRATION
-- ─────────────────────────────────────────────
if Config.UsePhoneApp then
    CreateThread(function()
        -- Wait for lb-phone to be available
        while GetResourceState(Config.PhoneResource) ~= 'started' do
            Wait(1000)
        end

        local phoneExport = exports[Config.PhoneResource]

        -- Register the Trucking app with lb-phone
        phoneExport:RegisterApp({
            identifier = 'trucking',
            name = 'Trucking',
            description = 'Freight board, active loads, and driver profile',
            developer = 'Free Trucking',
            defaultApp = false,
            ui = GetCurrentResourceName() .. '/nui/index.html',
            icon = 'nui/img/trucking_icon.png',
        })

        -- Listen for app open/close from phone
        RegisterNUICallback('trucking:phoneOpen', function(_, cb)
            if not isLoggedIn then
                cb({ ok = false })
                return
            end

            local nuiData = {
                activeLoad = ActiveLoad,
                activeBOL = ActiveBOL,
                reputation = cachedReputation,
                region = GetPlayerRegion(),
                isPhoneMode = true,
            }

            SendNUIMessage({
                action = 'open',
                data = nuiData,
            })

            TriggerServerEvent('trucking:server:openBoard', GetPlayerRegion())
            cb({ ok = true })
        end)
    end)
end

-- ─────────────────────────────────────────────
-- NUI CALLBACKS
-- ─────────────────────────────────────────────

--- Close NUI via escape or close button
RegisterNUICallback('trucking:close', function(_, cb)
    CloseTruckingNUI()
    cb({ ok = true })
end)

--- Request board data for a specific region
RegisterNUICallback('trucking:requestBoard', function(data, cb)
    local region = data.region or GetPlayerRegion()
    TriggerServerEvent('trucking:server:openBoard', region)
    cb({ ok = true })
end)

--- Reserve a load from the board
RegisterNUICallback('trucking:reserveLoad', function(data, cb)
    if not data.loadId then
        cb({ ok = false, error = 'No load specified' })
        return
    end
    TriggerServerEvent('trucking:server:reserveLoad', data.loadId)
    cb({ ok = true })
end)

--- Accept a reserved load
RegisterNUICallback('trucking:acceptLoad', function(data, cb)
    if not data.loadId then
        cb({ ok = false, error = 'No load specified' })
        return
    end
    TriggerServerEvent('trucking:server:acceptLoad', data.loadId)
    cb({ ok = true })
end)

--- Cancel a reservation
RegisterNUICallback('trucking:cancelReservation', function(data, cb)
    if not data.loadId then
        cb({ ok = false, error = 'No load specified' })
        return
    end
    TriggerServerEvent('trucking:server:cancelReservation', data.loadId)
    cb({ ok = true })
end)

--- Request profile data
RegisterNUICallback('trucking:requestProfile', function(_, cb)
    TriggerServerEvent('trucking:server:requestProfile')
    cb({ ok = true })
end)

--- Request insurance data
RegisterNUICallback('trucking:requestInsurance', function(_, cb)
    TriggerServerEvent('trucking:server:requestInsurance')
    cb({ ok = true })
end)

--- Purchase insurance
RegisterNUICallback('trucking:purchaseInsurance', function(data, cb)
    if not data.policyType then
        cb({ ok = false, error = 'No policy type specified' })
        return
    end
    TriggerServerEvent('trucking:server:insurancePurchase', data.policyType, data.tierCoverage)
    cb({ ok = true })
end)

--- Request company data
RegisterNUICallback('trucking:requestCompany', function(_, cb)
    TriggerServerEvent('trucking:server:requestCompany')
    cb({ ok = true })
end)

--- Request active load detail
RegisterNUICallback('trucking:requestActiveLoad', function(_, cb)
    cb({
        ok = true,
        activeLoad = ActiveLoad,
        activeBOL = ActiveBOL,
    })
end)

--- Request load detail for board preview
RegisterNUICallback('trucking:requestLoadDetail', function(data, cb)
    if not data.loadId then
        cb({ ok = false, error = 'No load specified' })
        return
    end
    TriggerServerEvent('trucking:server:requestLoadDetail', data.loadId)
    cb({ ok = true })
end)

--- Server response for profile data
RegisterNetEvent('trucking:client:profileData', function(data)
    SendNUIMessage({
        action = 'profileData',
        data = data,
    })
end)

--- Server response for insurance data
RegisterNetEvent('trucking:client:insuranceData', function(data)
    SendNUIMessage({
        action = 'insuranceData',
        data = data,
    })
end)

--- Server response for company data
RegisterNetEvent('trucking:client:companyData', function(data)
    SendNUIMessage({
        action = 'companyData',
        data = data,
    })
end)

--- Server response for load detail
RegisterNetEvent('trucking:client:loadDetail', function(data)
    SendNUIMessage({
        action = 'loadDetail',
        data = data,
    })
end)

--- Server response for board data
RegisterNetEvent('trucking:client:boardData', function(data)
    SendNUIMessage({
        action = 'boardData',
        data = data,
    })
end)

-- ─────────────────────────────────────────────
-- STATE CLEANUP
-- ─────────────────────────────────────────────

--- Clean up all client-side state
function CleanupState()
    -- Clear active load
    ActiveLoad = nil
    ActiveBOL = nil

    -- Stop monitoring systems
    TriggerEvent('trucking:client:stopAllMonitoring')

    -- Remove GPS waypoints
    TriggerEvent('trucking:client:clearGPS')

    -- Remove delivery zones
    TriggerEvent('trucking:client:removeDeliveryZone')

    -- Hide HUD
    TriggerEvent('trucking:client:hideHUD')

    -- Close NUI if open
    if nuiOpen then
        CloseTruckingNUI()
    end
end

-- ─────────────────────────────────────────────
-- RESOURCE STOP CLEANUP
-- ─────────────────────────────────────────────
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end

    CleanupState()

    -- Ensure NUI focus is released
    SetNuiFocus(false, false)
end)

-- ─────────────────────────────────────────────
-- INITIAL LOAD (if player is already logged in when resource starts)
-- ─────────────────────────────────────────────
CreateThread(function()
    local pd = exports.qbx_core:GetPlayerData()
    if pd and pd.citizenid then
        PlayerData = pd
        isLoggedIn = true
    end
end)
