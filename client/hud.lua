--[[
    client/hud.lua — Active Load HUD Overlay (Section 27.5)
    Free Trucking — QBX Framework

    Responsibilities:
    - 3-line HUD in top-right corner:
        Line 1: BOL number + cargo type
        Line 2: Destination + distance remaining
        Line 3: Time remaining + temperature (if reefer) + integrity %
    - Border states: #1E3A6E normal, #C87B03 warning (window <25%), #C83803 critical
      (window <10% or integrity <50%)
    - Update every second via SendNUIMessage
    - Convoy overlay: show convoy member distances if in convoy
    - Show/hide on active load start/end
]]

-- ─────────────────────────────────────────────
-- LOCAL STATE
-- ─────────────────────────────────────────────
local hudVisible = false
local hudThread = nil
local convoyData = nil

-- Border color hex values (Bears palette)
local BORDER_NORMAL   = '#1E3A6E'
local BORDER_WARNING  = '#C87B03'
local BORDER_CRITICAL = '#C83803'

-- ─────────────────────────────────────────────
-- HUD SHOW / HIDE
-- ─────────────────────────────────────────────

--- Show the HUD overlay. Called when a load becomes active (after departure).
RegisterNetEvent('trucking:client:showHUD', function()
    if hudVisible then return end
    hudVisible = true

    SendNUIMessage({
        action = 'showHUD',
    })

    StartHUDUpdateThread()
end)

--- Hide the HUD overlay. Called when load completes, fails, or is abandoned.
RegisterNetEvent('trucking:client:hideHUD', function()
    hudVisible = false
    hudThread = nil
    convoyData = nil

    SendNUIMessage({
        action = 'hideHUD',
    })
end)

-- ─────────────────────────────────────────────
-- HUD UPDATE THREAD
-- ─────────────────────────────────────────────

--- Main thread that sends HUD data to NUI every second while visible.
function StartHUDUpdateThread()
    if hudThread then return end

    hudThread = CreateThread(function()
        while hudVisible and ActiveLoad and ActiveBOL do
            local hudPayload = BuildHUDPayload()
            if hudPayload then
                SendNUIMessage({
                    action = 'updateHUD',
                    data = hudPayload,
                })
            end

            Wait(1000)
        end

        -- Auto-hide if loop exits because load ended
        if hudVisible then
            hudVisible = false
            SendNUIMessage({ action = 'hideHUD' })
        end
        hudThread = nil
    end)
end

--- Build the HUD data payload for NUI rendering.
---@return table|nil payload
function BuildHUDPayload()
    if not ActiveLoad or not ActiveBOL then return nil end

    -- Line 1: BOL number + cargo type
    local bolNumber = ActiveBOL.bol_number or '?'
    local cargoType = FormatCargoType(ActiveBOL.cargo_type or 'unknown')

    -- Line 2: Destination + distance remaining
    local destination = GetCurrentDestinationLabel and GetCurrentDestinationLabel() or (ActiveBOL.destination_label or 'Unknown')
    local distanceMiles = GetDistanceMiles and GetDistanceMiles() or 0
    local distanceDisplay = string.format('%.1f mi', distanceMiles)

    -- Multi-stop indicator
    local stopIndicator = nil
    if ActiveLoad.is_multi_stop and ActiveLoad.stop_count and ActiveLoad.stop_count > 1 then
        stopIndicator = (ActiveLoad.current_stop or 1) .. '/' .. ActiveLoad.stop_count
    end

    -- Line 3: Time remaining + temperature + integrity
    local windowRemainingMs = CalculateWindowRemaining and CalculateWindowRemaining() or 0
    local timeDisplay = FormatTimeRemaining(windowRemainingMs)

    -- Temperature (only for reefer loads)
    local tempDisplay = nil
    local tempOk = true
    if ActiveBOL.temp_required_min then
        local currentTemp = ActiveLoad.current_temp_f
        if currentTemp then
            tempDisplay = math.floor(currentTemp) .. '\194\176F'
            tempOk = currentTemp >= ActiveBOL.temp_required_min and currentTemp <= ActiveBOL.temp_required_max
        else
            tempDisplay = '--\194\176F'
        end

        if ActiveLoad.excursion_active then
            tempOk = false
        end
    end

    -- Integrity
    local integrity = ActiveLoad.cargo_integrity or 100

    -- Determine border state
    local borderState = 'normal'
    local borderColor = BORDER_NORMAL

    if integrity < 50 then
        borderState = 'critical'
        borderColor = BORDER_CRITICAL
    elseif windowRemainingMs > 0 then
        local windowTotalMs = CalculateWindowTotal and CalculateWindowTotal() or 1
        local windowPct = windowRemainingMs / windowTotalMs

        if windowPct < 0.10 then
            borderState = 'critical'
            borderColor = BORDER_CRITICAL
        elseif windowPct < 0.25 then
            borderState = 'warning'
            borderColor = BORDER_WARNING
        end
    elseif windowRemainingMs <= 0 and ActiveLoad.window_expires_at and ActiveLoad.window_expires_at > 0 then
        borderState = 'critical'
        borderColor = BORDER_CRITICAL
    end

    -- Seal status icon
    local sealIcon = nil
    if ActiveLoad.seal_status == 'sealed' then
        sealIcon = 'sealed'
    elseif ActiveLoad.seal_status == 'broken' then
        sealIcon = 'broken'
    end

    -- Convoy overlay data
    local convoyOverlay = nil
    if convoyData and ActiveLoad.convoy_id then
        convoyOverlay = BuildConvoyOverlay()
    end

    return {
        -- Line 1
        bolNumber     = bolNumber,
        cargoType     = cargoType,

        -- Line 2
        destination   = destination,
        distance      = distanceDisplay,
        stopIndicator = stopIndicator,

        -- Line 3
        timeRemaining = timeDisplay,
        temperature   = tempDisplay,
        tempOk        = tempOk,
        integrity     = integrity,
        sealIcon      = sealIcon,

        -- Border
        borderState   = borderState,
        borderColor   = borderColor,

        -- Convoy
        convoy        = convoyOverlay,
    }
end

-- ─────────────────────────────────────────────
-- HUD DATA EVENT (from missions.lua)
-- ─────────────────────────────────────────────
--- Alternative path: missions.lua can push data directly via event.
--- This is used for immediate updates outside the 1-second thread cycle.
RegisterNetEvent('trucking:client:hudData', function(data)
    if not hudVisible then return end
    -- Data is already structured — just merge border color
    if data then
        if data.borderState == 'critical' then
            data.borderColor = BORDER_CRITICAL
        elseif data.borderState == 'warning' then
            data.borderColor = BORDER_WARNING
        else
            data.borderColor = BORDER_NORMAL
        end
    end
end)

--- Force HUD update event (from any file)
RegisterNetEvent('trucking:client:hudUpdate', function()
    if not hudVisible then return end
    local payload = BuildHUDPayload()
    if payload then
        SendNUIMessage({
            action = 'updateHUD',
            data = payload,
        })
    end
end)

-- ─────────────────────────────────────────────
-- CONVOY OVERLAY
-- ─────────────────────────────────────────────

--- Receive convoy position updates from server.
--- Shows distances to convoy members on the HUD.
RegisterNetEvent('trucking:client:convoyPositions', function(data)
    convoyData = data
end)

--- Build convoy overlay data for HUD display.
---@return table|nil convoy
function BuildConvoyOverlay()
    if not convoyData or not convoyData.members then return nil end

    local playerCoords = GetEntityCoords(PlayerPedId())
    local members = {}

    for _, member in ipairs(convoyData.members) do
        if member.serverId ~= GetPlayerServerId(PlayerId()) then
            local dist = nil
            if member.coords then
                local memberPos = vector3(member.coords.x, member.coords.y, member.coords.z)
                dist = #(playerCoords - memberPos)
            end

            table.insert(members, {
                name = member.name or 'Driver',
                distance = dist and string.format('%.0f m', dist) or '?',
                inRange = dist and dist <= (Config.ConvoyProximityRadius or 150),
            })
        end
    end

    return {
        convoyId = convoyData.convoyId,
        memberCount = #convoyData.members,
        members = members,
    }
end

-- ─────────────────────────────────────────────
-- FORMATTING UTILITIES
-- ─────────────────────────────────────────────

--- Format cargo type for display (replace underscores, title case).
---@param cargoType string Raw cargo type identifier
---@return string formatted
function FormatCargoType(cargoType)
    if not cargoType then return 'Unknown' end

    -- Replace underscores with spaces
    local formatted = cargoType:gsub('_', ' ')

    -- Title case
    formatted = formatted:gsub('(%a)([%w]*)', function(first, rest)
        return first:upper() .. rest:lower()
    end)

    return formatted
end

--- Format milliseconds remaining into H:MM:SS or MM:SS display.
---@param ms number Milliseconds remaining
---@return string formatted
function FormatTimeRemaining(ms)
    if ms <= 0 then return 'EXPIRED' end

    local totalSeconds = math.floor(ms / 1000)
    local hours = math.floor(totalSeconds / 3600)
    local minutes = math.floor((totalSeconds % 3600) / 60)
    local seconds = totalSeconds % 60

    if hours > 0 then
        return string.format('%d:%02d:%02d', hours, minutes, seconds)
    else
        return string.format('%02d:%02d', minutes, seconds)
    end
end

-- ─────────────────────────────────────────────
-- CLEANUP ON RESOURCE STOP
-- ─────────────────────────────────────────────
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end

    hudVisible = false
    hudThread = nil
    convoyData = nil

    SendNUIMessage({ action = 'hideHUD' })
end)
