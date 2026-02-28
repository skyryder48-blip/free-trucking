--[[
    client/leon.lua — Leon Interaction Client
    Free Trucking — QBX Framework

    Leon is the criminal freight broker. He appears at his spot between
    22:00-04:00 server time only. Interaction is entirely through ox_lib
    context menus — no NUI board. Leon is terse; he doesn't chat.

    Section 21 of the Development Guide.
]]

-- ═══════════════════════════════════════════════════════════════
-- STATE
-- ═══════════════════════════════════════════════════════════════

local leonPed         = nil       -- spawned ped handle
local leonBlip        = nil       -- minimap blip (only when active hours)
local leonZone        = nil       -- lib.zones.sphere interaction zone
local leonSpawned     = false     -- ped currently exists in world
local leonAvailable   = false     -- within active hours
local leonAccessOk    = false     -- player has leon_access flag
local leonBoardData   = nil       -- cached board data from server
local activeLeonLoad  = nil       -- active Leon load after fee paid

-- Leon's location: under the overpass near LS docks, industrial area
-- Dark, hidden spot behind warehousing south of the Olympic Freeway
local LEON_COORDS     = vector3(-199.42, -1395.87, 31.26)
local LEON_HEADING    = 230.0
local LEON_MODEL      = `ig_chef2`                -- shady-looking NPC
local LEON_SPAWN_DIST = 80.0                      -- spawn ped when this close
local LEON_DESPAWN_DIST = 100.0                    -- despawn when this far
local LEON_INTERACT_DIST = 3.0                     -- context menu range
local LEON_CHECK_INTERVAL = 5000                   -- ms between proximity checks

-- ═══════════════════════════════════════════════════════════════
-- UTILITY
-- ═══════════════════════════════════════════════════════════════

--- Check if current server time is within Leon's active hours (22:00-04:00).
---@return boolean
local function IsLeonHours()
    local serverTime = GlobalState.serverTime
    if not serverTime or serverTime == 0 then return false end
    local hour = tonumber(os.date('%H', serverTime))
    if not hour then return false end

    local startHour = Config.LeonActiveHoursStart or 22
    local endHour   = Config.LeonActiveHoursEnd or 4

    if startHour > endHour then
        return hour >= startHour or hour < endHour
    else
        return hour >= startHour and hour < endHour
    end
end

--- Get risk tier display color for context menu.
---@param tier string Risk tier name
---@return string color ox_lib icon color
local function GetRiskColor(tier)
    local colors = {
        low      = 'green',
        medium   = 'yellow',
        high     = 'orange',
        critical = 'red',
    }
    return colors[tier] or 'white'
end

--- Get risk tier icon for context menu.
---@param tier string Risk tier name
---@return string icon FontAwesome icon name
local function GetRiskIcon(tier)
    local icons = {
        low      = 'circle-check',
        medium   = 'triangle-exclamation',
        high     = 'skull',
        critical = 'radiation',
    }
    return icons[tier] or 'question'
end

-- ═══════════════════════════════════════════════════════════════
-- PED MANAGEMENT
-- ═══════════════════════════════════════════════════════════════

--- Spawn Leon's ped at his location.
local function SpawnLeonPed()
    if leonSpawned then return end

    lib.requestModel(LEON_MODEL)
    leonPed = CreatePed(4, LEON_MODEL, LEON_COORDS.x, LEON_COORDS.y, LEON_COORDS.z - 1.0, LEON_HEADING, false, true)

    if not DoesEntityExist(leonPed) then
        SetModelAsNoLongerNeeded(LEON_MODEL)
        return
    end

    SetEntityInvincible(leonPed, true)
    SetBlockingOfNonTemporaryEvents(leonPed, true)
    FreezeEntityPosition(leonPed, true)
    SetPedFleeAttributes(leonPed, 0, false)
    SetPedCombatAttributes(leonPed, 46, true)
    SetPedKeepTask(leonPed, true)

    -- Leon leans against the wall, smoking — shady posture
    TaskStartScenarioInPlace(leonPed, 'WORLD_HUMAN_SMOKING', 0, true)

    SetModelAsNoLongerNeeded(LEON_MODEL)
    leonSpawned = true
end

--- Despawn Leon's ped from the world.
local function DespawnLeonPed()
    if not leonSpawned then return end

    if leonPed and DoesEntityExist(leonPed) then
        DeleteEntity(leonPed)
    end

    leonPed = nil
    leonSpawned = false
end

--- Create Leon's minimap blip (only during active hours).
local function CreateLeonBlip()
    if leonBlip then return end

    leonBlip = AddBlipForCoord(LEON_COORDS.x, LEON_COORDS.y, LEON_COORDS.z)
    SetBlipSprite(leonBlip, 480)      -- dark business icon
    SetBlipColour(leonBlip, 40)       -- dark grey
    SetBlipScale(leonBlip, 0.7)
    SetBlipAlpha(leonBlip, 180)
    SetBlipAsShortRange(leonBlip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName('Contact')
    EndTextCommandSetBlipName(leonBlip)
end

--- Remove Leon's minimap blip.
local function RemoveLeonBlip()
    if leonBlip then
        RemoveBlip(leonBlip)
        leonBlip = nil
    end
end

-- ═══════════════════════════════════════════════════════════════
-- LEON BOARD — OX_LIB CONTEXT MENUS
-- ═══════════════════════════════════════════════════════════════

--- Show a specific load's fee confirmation dialog.
---@param loadData table Load data from server
local function ShowFeeConfirmation(loadData)
    local confirmed = lib.alertDialog({
        header  = 'Pay Fee',
        content = string.format(
            'Risk: **%s**\nFee: **%s**\n\nPay this fee to get the details? Non-refundable.',
            (loadData.risk_tier or 'unknown'):upper(),
            FormatMoney(loadData.fee or 0)
        ),
        centered = true,
        cancel   = true,
        labels   = { confirm = 'Pay', cancel = 'Walk Away' },
    })

    if confirmed == 'confirm' then
        TriggerServerEvent('trucking:server:payLeonFee', loadData.load_id)
    end
end

--- Build and show Leon's board context menu with available loads.
---@param loads table Array of load data from server
local function ShowLeonBoard(loads)
    if not loads or #loads == 0 then
        lib.registerContext({
            id      = 'leon_board_empty',
            title   = 'Leon',
            options = {
                {
                    title       = '"Nothing right now. Come back later."',
                    description = 'No loads available.',
                    icon        = 'ban',
                    iconColor   = 'grey',
                    readOnly    = true,
                },
            },
        })
        lib.showContext('leon_board_empty')
        return
    end

    local options = {
        {
            title    = '"What do you need?"',
            icon     = 'comment',
            readOnly = true,
        },
    }

    for i, load in ipairs(loads) do
        local riskTier = load.risk_tier or 'low'
        options[#options + 1] = {
            title       = string.format('Job %d — %s Risk', i, riskTier:upper()),
            description = string.format('Fee: %s', FormatMoney(load.fee or 0)),
            icon        = GetRiskIcon(riskTier),
            iconColor   = GetRiskColor(riskTier),
            onSelect    = function()
                ShowFeeConfirmation(load)
            end,
        }
    end

    lib.registerContext({
        id      = 'leon_board',
        title   = 'Leon',
        options = options,
    })
    lib.showContext('leon_board')
end

--- Show Leon's initial approach menu (first interaction).
local function ShowLeonApproach()
    lib.registerContext({
        id      = 'leon_approach',
        title   = 'Leon',
        options = {
            {
                title       = '"Yeah?"',
                description = 'He looks you over.',
                icon        = 'eye',
                iconColor   = 'grey',
                readOnly    = true,
            },
            {
                title       = 'See what\'s available',
                description = 'Check Leon\'s board.',
                icon        = 'clipboard-list',
                iconColor   = 'orange',
                onSelect    = function()
                    -- Request board data from server
                    TriggerServerEvent('trucking:server:openLeonBoard')
                end,
            },
        },
    })
    lib.showContext('leon_approach')
end

--- Show load details after fee is paid.
---@param data table Load details revealed by server
local function ShowLeonLoadDetails(data)
    local options = {
        {
            title    = '"Here\'s your details. Don\'t be late."',
            icon     = 'comment',
            readOnly = true,
        },
        {
            title       = 'Pickup',
            description = data.origin_label or 'Unknown',
            icon        = 'location-dot',
            iconColor   = 'green',
            readOnly    = true,
        },
        {
            title       = 'Drop',
            description = data.destination_label or 'Find it yourself.',
            icon        = 'flag-checkered',
            iconColor   = 'red',
            readOnly    = true,
        },
        {
            title       = 'Cargo',
            description = data.cargo_description or 'Don\'t ask.',
            icon        = 'box',
            iconColor   = 'orange',
            readOnly    = true,
        },
        {
            title       = 'Pay',
            description = FormatMoney(data.payout or 0) .. ' cash',
            icon        = 'money-bill',
            iconColor   = 'green',
            readOnly    = true,
        },
        {
            title       = 'Window',
            description = data.window_label or 'Don\'t waste time.',
            icon        = 'clock',
            iconColor   = 'yellow',
            readOnly    = true,
        },
        {
            title       = 'Accept Job',
            description = 'No BOL. No seal. No GPS to the drop.',
            icon        = 'handshake',
            iconColor   = 'orange',
            onSelect    = function()
                TriggerServerEvent('trucking:server:acceptLeonLoad', data.load_id)
            end,
        },
    }

    lib.registerContext({
        id      = 'leon_load_details',
        title   = 'Leon — Job Details',
        options = options,
    })
    lib.showContext('leon_load_details')
end

-- ═══════════════════════════════════════════════════════════════
-- INTERACTION ZONE
-- ═══════════════════════════════════════════════════════════════

--- Create the Leon interaction zone (lib.zones.sphere).
local function CreateLeonZone()
    if leonZone then return end

    leonZone = lib.zones.sphere({
        coords = LEON_COORDS,
        radius = LEON_INTERACT_DIST,
        debug  = false,

        onEnter = function()
            if not leonAvailable or not leonAccessOk then return end
            lib.notify({
                title       = 'Leon',
                description = 'Press [E] to talk.',
                type        = 'inform',
                duration    = 3000,
            })
        end,

        inside = function()
            if not leonAvailable or not leonAccessOk then return end
            if not leonSpawned then return end

            if IsControlJustPressed(0, 51) then -- E key
                ShowLeonApproach()
            end
        end,

        onExit = function()
            lib.hideContext()
        end,
    })
end

--- Remove the Leon interaction zone.
local function RemoveLeonZone()
    if leonZone then
        leonZone:remove()
        leonZone = nil
    end
end

-- ═══════════════════════════════════════════════════════════════
-- PROXIMITY AND TIME MONITORING
-- ═══════════════════════════════════════════════════════════════

--- Main monitoring thread: handles ped spawn/despawn based on proximity
--- and Leon's availability based on time and player access.
CreateThread(function()
    -- Wait for player to be fully loaded
    while not LocalPlayer.state.isLoggedIn do
        Wait(1000)
    end

    while true do
        Wait(LEON_CHECK_INTERVAL)

        -- Check if player has Leon access (set by server via statebag or callback)
        leonAccessOk = LocalPlayer.state.leonAccess or false

        if not leonAccessOk then
            -- Clean up if we previously had access
            if leonSpawned then DespawnLeonPed() end
            if leonBlip then RemoveLeonBlip() end
            if leonZone then RemoveLeonZone() end
            leonAvailable = false
            goto continue
        end

        -- Check time window
        local wasAvailable = leonAvailable
        leonAvailable = IsLeonHours()

        -- Time window just closed
        if wasAvailable and not leonAvailable then
            DespawnLeonPed()
            RemoveLeonBlip()
            RemoveLeonZone()
            leonBoardData = nil
            goto continue
        end

        -- Not in active hours
        if not leonAvailable then
            if leonSpawned then DespawnLeonPed() end
            if leonBlip then RemoveLeonBlip() end
            if leonZone then RemoveLeonZone() end
            goto continue
        end

        -- Active hours — manage blip
        if not leonBlip then
            CreateLeonBlip()
        end

        -- Active hours — manage zone
        if not leonZone then
            CreateLeonZone()
        end

        -- Proximity-based ped spawn/despawn
        local playerCoords = GetEntityCoords(cache.ped)
        local dist = #(playerCoords - LEON_COORDS)

        if dist <= LEON_SPAWN_DIST and not leonSpawned then
            SpawnLeonPed()
        elseif dist > LEON_DESPAWN_DIST and leonSpawned then
            DespawnLeonPed()
        end

        ::continue::
    end
end)

-- ═══════════════════════════════════════════════════════════════
-- SERVER EVENTS
-- ═══════════════════════════════════════════════════════════════

--- Receive Leon board data from server.
RegisterNetEvent('trucking:client:leonBoardData', function(loads)
    leonBoardData = loads
    ShowLeonBoard(loads)
end)

--- Receive load details after fee payment.
RegisterNetEvent('trucking:client:leonLoadRevealed', function(data)
    if not data then
        lib.notify({
            title       = 'Leon',
            description = 'Payment failed.',
            type        = 'error',
        })
        return
    end

    activeLeonLoad = data
    ShowLeonLoadDetails(data)
end)

--- Leon load accepted — set GPS to pickup (no delivery GPS).
RegisterNetEvent('trucking:client:leonLoadAccepted', function(data)
    if not data then return end

    activeLeonLoad = data

    -- Set GPS waypoint to pickup location only
    if data.origin_coords then
        local coords = data.origin_coords
        if type(coords) == 'table' then
            SetNewWaypoint(coords.x or coords[1], coords.y or coords[2])
        elseif type(coords) == 'vector3' then
            SetNewWaypoint(coords.x, coords.y)
        end
    end

    lib.notify({
        title       = 'Leon',
        description = 'GPS set to pickup. No GPS to the drop — you better know where you\'re going.',
        type        = 'inform',
        duration    = 8000,
    })
end)

--- Leon delivery completed — cash payout notification.
RegisterNetEvent('trucking:client:leonDeliveryComplete', function(data)
    activeLeonLoad = nil

    if data and data.payout then
        lib.notify({
            title       = 'Leon',
            description = string.format('Cash received: %s', FormatMoney(data.payout)),
            type        = 'success',
            duration    = 5000,
        })
    end
end)

--- Leon load failed/expired.
RegisterNetEvent('trucking:client:leonLoadFailed', function(reason)
    activeLeonLoad = nil

    lib.notify({
        title       = 'Leon',
        description = reason or 'Job\'s done. One way or another.',
        type        = 'error',
        duration    = 5000,
    })
end)

--- Server grants/revokes Leon access (e.g. after first T3 delivery).
RegisterNetEvent('trucking:client:setLeonAccess', function(hasAccess)
    leonAccessOk = hasAccess
    LocalPlayer.state:set('leonAccess', hasAccess, false)

    if hasAccess then
        lib.notify({
            title       = 'Trucking',
            description = 'You\'ve got options now. Industrial district, after dark.',
            type        = 'inform',
            duration    = 8000,
        })
    end
end)

--- Fee payment rejected (insufficient funds, etc).
RegisterNetEvent('trucking:client:leonFeeFailed', function(reason)
    lib.notify({
        title       = 'Leon',
        description = reason or 'Can\'t cover the fee.',
        type        = 'error',
        duration    = 4000,
    })
end)

-- ═══════════════════════════════════════════════════════════════
-- CLEANUP
-- ═══════════════════════════════════════════════════════════════

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end

    DespawnLeonPed()
    RemoveLeonBlip()
    RemoveLeonZone()
end)

-- Clean up on player logout
RegisterNetEvent('qbx_core:client:onLogout', function()
    DespawnLeonPed()
    RemoveLeonBlip()
    RemoveLeonZone()
    leonAccessOk  = false
    leonAvailable = false
    leonBoardData = nil
    activeLeonLoad = nil
end)
