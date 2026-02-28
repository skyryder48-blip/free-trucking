--[[
    client/company.lua — Company and Dispatcher Client State
    Free Trucking — QBX Framework

    Responsibilities:
    - Company state tracking (current company, role, dispatch mode)
    - RegisterNetEvent handlers:
        * loadAssigned (from dispatcher)
        * transferOffer (from another driver)
        * directOffer (from shipper preferred tier)
    - Dispatcher mode: opens dispatcher tablet NUI, cannot accept loads
    - Load assignment accept/decline via lib.alertDialog
    - Transfer mechanic: check proximity (15m), initiate/accept
    - Company member list display
    - Driver status broadcasting to company members

    Authority model:
    - Client manages UI interactions and proximity checks
    - Server validates all company operations, membership, and transfers
    - No payout or reputation logic runs here
]]

-- ─────────────────────────────────────────────
-- STATE
-- ─────────────────────────────────────────────

--- Current company data (nil if not in a company)
local CompanyData = nil

--- Player's role in the company (nil, 'owner', 'dispatcher', 'driver')
local CompanyRole = nil

--- Company ID
local CompanyId = nil

--- Dispatcher mode state
local DispatchModeActive = false

--- Company member list cache (display only, server-authoritative)
local CompanyMembers = {}

--- Driver statuses cache (updated by server broadcasts)
local DriverStatuses = {}

--- Transfer proximity threshold (meters)
local TRANSFER_PROXIMITY = 15.0

-- ─────────────────────────────────────────────
-- COMPANY STATE MANAGEMENT
-- ─────────────────────────────────────────────

--- Get the current company data.
---@return table|nil companyData
function GetCompanyData()
    return CompanyData
end

--- Get the player's current company role.
---@return string|nil role
function GetCompanyRole()
    return CompanyRole
end

--- Check if the player is in a company.
---@return boolean inCompany
function IsInCompany()
    return CompanyData ~= nil and CompanyId ~= nil
end

--- Check if the player is in dispatcher mode.
---@return boolean dispatching
function IsDispatchMode()
    return DispatchModeActive
end

-- ─────────────────────────────────────────────
-- SERVER-TO-CLIENT EVENTS: COMPANY DATA
-- ─────────────────────────────────────────────

--- Server sends full company data (on login, on company join, on request).
RegisterNetEvent('trucking:client:companyState', function(data)
    if not data then
        CompanyData = nil
        CompanyRole = nil
        CompanyId = nil
        CompanyMembers = {}
        DriverStatuses = {}
        return
    end

    CompanyData = data.company or nil
    CompanyRole = data.role or nil
    CompanyId = data.companyId or nil
    CompanyMembers = data.members or {}
    DriverStatuses = data.statuses or {}

    -- Forward to NUI
    SendNUIMessage({
        action = 'companyData',
        data = {
            company = CompanyData,
            role = CompanyRole,
            companyId = CompanyId,
            members = CompanyMembers,
            statuses = DriverStatuses,
        },
    })
end)

--- Server updates the member list.
RegisterNetEvent('trucking:client:companyMemberUpdate', function(data)
    if not data then return end
    CompanyMembers = data.members or CompanyMembers
    DriverStatuses = data.statuses or DriverStatuses

    SendNUIMessage({
        action = 'companyMemberUpdate',
        data = {
            members = CompanyMembers,
            statuses = DriverStatuses,
        },
    })
end)

--- Server updates a single driver's status.
RegisterNetEvent('trucking:client:driverStatusUpdate', function(data)
    if not data or not data.citizenid then return end
    DriverStatuses[data.citizenid] = {
        status = data.status,
        cargoType = data.cargoType,
        destination = data.destination,
        progress = data.progress,
    }

    SendNUIMessage({
        action = 'driverStatusUpdate',
        data = data,
    })
end)

-- ─────────────────────────────────────────────
-- DISPATCHER MODE
-- ─────────────────────────────────────────────

--- Enable dispatcher mode. Opens the dispatcher tablet NUI.
--- While in dispatch mode, the player cannot accept loads directly.
RegisterNetEvent('trucking:client:enableDispatchMode', function()
    if CompanyRole ~= 'dispatcher' and CompanyRole ~= 'owner' then
        lib.notify({
            title = 'Dispatch Mode',
            description = 'You do not have dispatcher permissions.',
            type = 'error',
        })
        return
    end

    DispatchModeActive = true

    -- Open dispatcher tablet NUI
    SendNUIMessage({
        action = 'openDispatcherUI',
        data = {
            company = CompanyData,
            members = CompanyMembers,
            statuses = DriverStatuses,
        },
    })

    lib.notify({
        title = 'Dispatch Mode Active',
        description = 'You are now dispatching. Cannot accept loads while active.',
        type = 'inform',
        duration = 6000,
    })

    TriggerServerEvent('trucking:server:enableDispatchMode')
end)

--- Disable dispatcher mode.
RegisterNetEvent('trucking:client:disableDispatchMode', function()
    DispatchModeActive = false

    SendNUIMessage({
        action = 'closeDispatcherUI',
    })

    lib.notify({
        title = 'Dispatch Mode Off',
        description = 'Dispatch mode deactivated.',
        type = 'inform',
    })

    TriggerServerEvent('trucking:server:disableDispatchMode')
end)

--- Toggle dispatch mode.
function ToggleDispatchMode()
    if DispatchModeActive then
        TriggerEvent('trucking:client:disableDispatchMode')
    else
        TriggerEvent('trucking:client:enableDispatchMode')
    end
end

-- ─────────────────────────────────────────────
-- LOAD ASSIGNMENT (FROM DISPATCHER)
-- ─────────────────────────────────────────────

--- Dispatcher assigns load to this driver.
--- Uses lib.alertDialog for accept/decline.
RegisterNetEvent('trucking:client:loadAssignedByDispatch', function(loadData, dispatcherName)
    if not loadData then return end

    local result = lib.alertDialog({
        header = 'Dispatch Assignment',
        content = '**' .. (dispatcherName or 'Dispatcher') .. '** has assigned you a load.\n\n'
            .. '**Cargo:** ' .. (loadData.cargo_type or 'Unknown') .. '\n'
            .. '**Route:** ' .. (loadData.origin_label or '?') .. ' to '
            .. (loadData.destination_label or '?') .. '\n'
            .. '**Distance:** ' .. (loadData.distance_miles or '?') .. ' mi\n'
            .. '**Estimated Payout:** $' .. (loadData.estimated_payout or 0),
        centered = true,
        cancel = true,
        labels = {
            confirm = 'Accept',
            cancel = 'Decline',
        },
    })

    if result == 'confirm' then
        TriggerServerEvent('trucking:server:acceptAssignment', loadData.load_id)
        lib.notify({
            title = 'Assignment Accepted',
            description = 'Dispatch assignment confirmed.',
            type = 'success',
        })
    else
        TriggerServerEvent('trucking:server:declineAssignment', loadData.load_id)
        lib.notify({
            title = 'Assignment Declined',
            description = 'Dispatch assignment declined.',
            type = 'inform',
        })
    end
end)

-- ─────────────────────────────────────────────
-- LOAD TRANSFER
-- ─────────────────────────────────────────────

--- Initiate a load transfer to a nearby company driver.
--- Client checks proximity before sending to server.
function InitiateTransfer()
    if not ActiveLoad then
        lib.notify({
            title = 'Transfer',
            description = 'No active load to transfer.',
            type = 'error',
        })
        return
    end

    if not IsInCompany() then
        lib.notify({
            title = 'Transfer',
            description = 'You must be in a company to transfer loads.',
            type = 'error',
        })
        return
    end

    -- Build list of nearby company members
    local nearbyMembers = {}
    local playerPos = GetEntityCoords(PlayerPedId())

    for _, member in ipairs(CompanyMembers) do
        local memberCitizenId = member.citizenid
        if memberCitizenId ~= GetCitizenId() then
            -- Check if member has a known status (is online)
            local status = DriverStatuses[memberCitizenId]
            if status then
                table.insert(nearbyMembers, {
                    value = memberCitizenId,
                    label = (member.name or 'Unknown') .. ' — '
                        .. (status.status or 'idle'),
                })
            end
        end
    end

    if #nearbyMembers == 0 then
        lib.notify({
            title = 'Transfer',
            description = 'No company members nearby (within '
                .. TRANSFER_PROXIMITY .. 'm).',
            type = 'warning',
        })
        return
    end

    local result = lib.inputDialog('Transfer Load', {
        {
            type = 'select',
            label = 'Transfer To',
            description = 'Select a company driver to transfer your load to',
            required = true,
            options = nearbyMembers,
        },
    })

    if result and result[1] then
        TriggerServerEvent('trucking:server:initiateTransfer', result[1])
        lib.notify({
            title = 'Transfer',
            description = 'Transfer request sent.',
            type = 'inform',
        })
    end
end

--- Receive a transfer offer from another company driver.
RegisterNetEvent('trucking:client:transferOffer', function(data)
    if not data then return end

    local result = lib.alertDialog({
        header = 'Load Transfer Offer',
        content = '**' .. (data.fromName or 'Unknown') .. '** wants to transfer their load.\n\n'
            .. '**BOL:** #' .. (data.bolNumber or '?') .. '\n'
            .. '**Cargo:** ' .. (data.cargoType or 'unknown') .. '\n'
            .. '**Destination:** ' .. (data.destination or 'unknown') .. '\n'
            .. '**Your share:** ' .. math.floor((data.splitRatio or 0) * 100) .. '% of payout',
        centered = true,
        cancel = true,
        labels = {
            confirm = 'Accept Transfer',
            cancel = 'Decline',
        },
    })

    if result == 'confirm' then
        TriggerServerEvent('trucking:server:acceptTransfer', data.bolId)
    else
        TriggerServerEvent('trucking:server:declineTransfer', data.bolId)
    end
end)

-- ─────────────────────────────────────────────
-- DIRECT OFFER (FROM SHIPPER PREFERRED TIER)
-- ─────────────────────────────────────────────

--- Receive a direct load offer from a shipper (preferred tier benefit).
RegisterNetEvent('trucking:client:directOffer', function(data)
    if not data then return end

    local result = lib.alertDialog({
        header = 'Direct Shipper Offer',
        content = '**' .. (data.shipperName or 'Unknown Shipper') .. '** is offering you a load directly.\n\n'
            .. '**Cargo:** ' .. (data.cargoType or 'unknown') .. '\n'
            .. '**Route:** ' .. (data.origin or '?') .. ' to ' .. (data.destination or '?') .. '\n'
            .. '**Distance:** ' .. (data.distance or '?') .. ' mi\n'
            .. '**Estimated Payout:** $' .. (data.estimatedPayout or 0) .. '\n\n'
            .. 'This is an exclusive offer from your preferred shipper.',
        centered = true,
        cancel = true,
        labels = {
            confirm = 'Accept Offer',
            cancel = 'Decline',
        },
    })

    if result == 'confirm' then
        TriggerServerEvent('trucking:server:acceptLoad', data.loadId)
    else
        TriggerServerEvent('trucking:server:declineDirectOffer', data.loadId)
    end
end)

-- ─────────────────────────────────────────────
-- DISPATCHER NUI CALLBACKS
-- ─────────────────────────────────────────────

--- Dispatcher assigns a load to a driver via NUI.
RegisterNUICallback('trucking:dispatchAssignLoad', function(data, cb)
    if not DispatchModeActive then
        cb({ ok = false, error = 'Not in dispatch mode' })
        return
    end
    if not data.loadId or not data.targetCitizenId then
        cb({ ok = false, error = 'Missing parameters' })
        return
    end

    TriggerServerEvent('trucking:server:assignLoadToDriver', data.loadId, data.targetCitizenId)
    cb({ ok = true })
end)

--- Dispatcher requests updated driver statuses via NUI.
RegisterNUICallback('trucking:dispatchRefresh', function(_, cb)
    if not DispatchModeActive then
        cb({ ok = false, error = 'Not in dispatch mode' })
        return
    end

    TriggerServerEvent('trucking:server:getCompanyActiveLoads')
    cb({ ok = true })
end)

--- Dispatcher closes the tablet.
RegisterNUICallback('trucking:closeDispatcherUI', function(_, cb)
    TriggerEvent('trucking:client:disableDispatchMode')
    cb({ ok = true })
end)

-- ─────────────────────────────────────────────
-- DRIVER STATUS BROADCASTING
-- ─────────────────────────────────────────────

--- Periodically broadcast this driver's status to company members.
--- Runs every 10 seconds when in a company with an active load.
CreateThread(function()
    while true do
        Wait(10000)

        if IsInCompany() and ActiveLoad and IsPlayerLoggedIn() then
            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)
            local vehicle = GetVehiclePedIsIn(ped, false)
            local speed = 0
            if vehicle and vehicle ~= 0 then
                speed = math.floor(GetEntitySpeed(vehicle) * 2.23694) -- mph
            end

            TriggerServerEvent('trucking:server:driverStatusBroadcast', {
                status = ActiveLoad.status or 'in_transit',
                cargoType = ActiveLoad.cargo_type,
                destination = ActiveLoad.destination_label,
                coords = { x = coords.x, y = coords.y, z = coords.z },
                speed = speed,
                integrity = ActiveLoad.cargo_integrity,
            })
        end
    end
end)

-- ─────────────────────────────────────────────
-- COMPANY MEMBER LIST DISPLAY
-- ─────────────────────────────────────────────

--- Show the company member list via context menu.
function ShowCompanyMembers()
    if not IsInCompany() then
        lib.notify({
            title = 'Company',
            description = 'You are not in a company.',
            type = 'inform',
        })
        return
    end

    local options = {}
    for _, member in ipairs(CompanyMembers) do
        local status = DriverStatuses[member.citizenid]
        local statusLabel = 'Offline'
        local icon = 'circle'
        local iconColor = 'grey'

        if status then
            if status.status == 'in_transit' then
                statusLabel = 'In Transit — ' .. (status.cargoType or '?')
                icon = 'truck'
                iconColor = 'green'
            elseif status.status == 'at_origin' then
                statusLabel = 'At Origin'
                icon = 'warehouse'
                iconColor = 'blue'
            elseif status.status == 'at_destination' then
                statusLabel = 'At Destination'
                icon = 'flag-checkered'
                iconColor = 'green'
            else
                statusLabel = status.status or 'Idle'
                icon = 'user'
                iconColor = 'white'
            end
        end

        table.insert(options, {
            title = (member.name or 'Unknown') .. ' (' .. (member.role or 'driver') .. ')',
            description = statusLabel,
            icon = icon,
            iconColor = iconColor,
        })
    end

    lib.registerContext({
        id = 'company_member_list',
        title = (CompanyData and CompanyData.company_name or 'Company') .. ' — Members',
        options = options,
    })
    lib.showContext('company_member_list')
end

-- ─────────────────────────────────────────────
-- CLEANUP
-- ─────────────────────────────────────────────

--- Reset all company state.
local function CleanupCompanyState()
    CompanyData = nil
    CompanyRole = nil
    CompanyId = nil
    CompanyMembers = {}
    DriverStatuses = {}
    DispatchModeActive = false
end

--- Stop all monitoring on state cleanup.
AddEventHandler('trucking:client:stopAllMonitoring', function()
    if DispatchModeActive then
        DispatchModeActive = false
        SendNUIMessage({ action = 'closeDispatcherUI' })
    end
end)

--- Player unloaded — clear company state.
RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    CleanupCompanyState()
end)

-- ─────────────────────────────────────────────
-- RESOURCE CLEANUP
-- ─────────────────────────────────────────────
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    CleanupCompanyState()
end)
