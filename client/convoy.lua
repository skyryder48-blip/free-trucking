--[[
    client/convoy.lua — Convoy Proximity Tracking
    Free Trucking — QBX Framework

    Responsibilities:
    - Convoy state tracking (convoyId, members, isLead)
    - Proximity update: every 5 seconds, calculate distance from each
      convoy member to convoy lead
    - Send proximity data to HUD overlay via SendNUIMessage
    - Convoy join/leave interactions
    - Convoy creation: lib.inputDialog for convoy type (open/invite/company)
    - Convoy notification when nearby players are forming
    - Visual: blip for each convoy member on minimap

    Authority model:
    - Client tracks local proximity, draws blips, updates HUD
    - Server manages convoy membership, creation, disbanding
    - Convoy bonuses calculated server-side at delivery
]]

-- ─────────────────────────────────────────────
-- STATE
-- ─────────────────────────────────────────────

--- Current convoy data (nil if not in a convoy)
local ConvoyId = nil
local ConvoyType = nil      -- 'open', 'invite', 'company'
local IsConvoyLead = false
local ConvoyMembers = {}    -- array of { citizenid, name, serverId, coords, distance, blip }
local ConvoyActive = false

--- Blip handles for convoy members
local memberBlips = {}

--- Proximity update interval (ms)
local PROXIMITY_UPDATE_MS = 5000

--- Maximum convoy size (from Config)
local MAX_CONVOY_SIZE = Config.ConvoyMaxSize or 6

--- Convoy proximity radius for formation (from Config)
local CONVOY_PROXIMITY_RADIUS = Config.ConvoyProximityRadius or 150

-- ─────────────────────────────────────────────
-- BLIP MANAGEMENT
-- ─────────────────────────────────────────────

--- Create or update a blip for a convoy member.
---@param citizenid string The member's citizen ID
---@param name string Display name
---@param coords vector3 Member's world coordinates
---@param isLead boolean Whether this member is the convoy lead
---@return number blipHandle
local function UpdateMemberBlip(citizenid, name, coords, isLead)
    -- Remove existing blip if it exists
    if memberBlips[citizenid] then
        RemoveBlip(memberBlips[citizenid])
        memberBlips[citizenid] = nil
    end

    if not coords then return 0 end

    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    if isLead then
        SetBlipSprite(blip, 477)    -- lead truck icon
        SetBlipColour(blip, 46)     -- orange
        SetBlipScale(blip, 0.9)
    else
        SetBlipSprite(blip, 477)    -- truck icon
        SetBlipColour(blip, 3)      -- blue
        SetBlipScale(blip, 0.7)
    end

    SetBlipDisplay(blip, 2)         -- show on minimap and main map
    SetBlipAsShortRange(blip, false)

    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(name .. (isLead and ' (Lead)' or ''))
    EndTextCommandSetBlipName(blip)

    memberBlips[citizenid] = blip
    return blip
end

--- Remove all convoy member blips.
local function RemoveAllBlips()
    for citizenid, blip in pairs(memberBlips) do
        if DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
    end
    memberBlips = {}
end

-- ─────────────────────────────────────────────
-- PROXIMITY CALCULATION
-- ─────────────────────────────────────────────

--- Calculate distance from each convoy member to the convoy lead.
--- Updates the HUD overlay with proximity data.
local function UpdateProximity()
    if not ConvoyActive or #ConvoyMembers == 0 then return end

    -- Find the lead member
    local leadCoords = nil
    local leadCitizenId = nil
    for _, member in ipairs(ConvoyMembers) do
        if member.isLead then
            leadCoords = member.coords
            leadCitizenId = member.citizenid
            break
        end
    end

    if not leadCoords then return end

    -- Calculate distances
    local proximityData = {}
    for _, member in ipairs(ConvoyMembers) do
        local distance = 0
        local inFormation = true

        if member.coords and not member.isLead then
            distance = #(vector3(member.coords.x, member.coords.y, member.coords.z)
                - vector3(leadCoords.x, leadCoords.y, leadCoords.z))
            inFormation = distance <= CONVOY_PROXIMITY_RADIUS
        end

        table.insert(proximityData, {
            citizenid = member.citizenid,
            name = member.name,
            isLead = member.isLead,
            distance = math.floor(distance),
            inFormation = inFormation,
        })

        -- Update blip position
        if member.coords then
            UpdateMemberBlip(
                member.citizenid,
                member.name or 'Unknown',
                vector3(member.coords.x, member.coords.y, member.coords.z),
                member.isLead
            )
        end
    end

    -- Send proximity data to HUD
    SendNUIMessage({
        action = 'convoyUpdate',
        data = {
            convoyId = ConvoyId,
            convoyType = ConvoyType,
            isLead = IsConvoyLead,
            memberCount = #ConvoyMembers,
            maxSize = MAX_CONVOY_SIZE,
            members = proximityData,
        },
    })
end

-- ─────────────────────────────────────────────
-- CONVOY CREATION
-- ─────────────────────────────────────────────

--- Open the convoy creation dialog.
function CreateConvoy()
    if ConvoyActive then
        lib.notify({
            title = 'Convoy',
            description = 'You are already in a convoy.',
            type = 'warning',
        })
        return
    end

    if not ActiveLoad then
        lib.notify({
            title = 'Convoy',
            description = 'You need an active load to form a convoy.',
            type = 'warning',
        })
        return
    end

    local result = lib.inputDialog('Form Convoy', {
        {
            type = 'select',
            label = 'Convoy Type',
            description = 'Who can join this convoy?',
            required = true,
            options = {
                { value = 'open',    label = 'Open — Any driver can join' },
                { value = 'invite',  label = 'Invite Only — By invitation' },
                { value = 'company', label = 'Company — Company members only' },
            },
        },
    })

    if result and result[1] then
        TriggerServerEvent('trucking:server:createConvoy', result[1])
        lib.notify({
            title = 'Convoy',
            description = 'Creating ' .. result[1] .. ' convoy...',
            type = 'inform',
        })
    end
end

--- Join an existing convoy.
---@param convoyId number The convoy to join
function JoinConvoy(convoyId)
    if ConvoyActive then
        lib.notify({
            title = 'Convoy',
            description = 'You are already in a convoy. Leave first.',
            type = 'warning',
        })
        return
    end

    TriggerServerEvent('trucking:server:joinConvoy', convoyId)
end

--- Leave the current convoy.
function LeaveConvoy()
    if not ConvoyActive then
        lib.notify({
            title = 'Convoy',
            description = 'You are not in a convoy.',
            type = 'inform',
        })
        return
    end

    TriggerServerEvent('trucking:server:leaveConvoy', ConvoyId)
end

--- Invite a player to the convoy.
---@param targetCitizenId string Target player's citizen ID
function InviteToConvoy(targetCitizenId)
    if not ConvoyActive then return end
    if not IsConvoyLead then
        lib.notify({
            title = 'Convoy',
            description = 'Only the convoy lead can send invitations.',
            type = 'warning',
        })
        return
    end

    TriggerServerEvent('trucking:server:inviteToConvoy', ConvoyId, targetCitizenId)
end

-- ─────────────────────────────────────────────
-- SERVER-TO-CLIENT EVENTS
-- ─────────────────────────────────────────────

--- Server confirms convoy creation.
RegisterNetEvent('trucking:client:convoyCreated', function(data)
    if not data then return end

    ConvoyId = data.convoyId
    ConvoyType = data.convoyType
    IsConvoyLead = true
    ConvoyActive = true
    ConvoyMembers = data.members or {}

    lib.notify({
        title = 'Convoy Formed',
        description = 'You are the convoy lead. Type: ' .. (ConvoyType or 'open'),
        type = 'success',
        duration = 6000,
    })

    -- Start proximity tracking
    StartConvoyTracking()
end)

--- Server confirms convoy join.
RegisterNetEvent('trucking:client:convoyJoined', function(data)
    if not data then return end

    ConvoyId = data.convoyId
    ConvoyType = data.convoyType
    IsConvoyLead = data.isLead or false
    ConvoyActive = true
    ConvoyMembers = data.members or {}

    lib.notify({
        title = 'Convoy Joined',
        description = 'Joined convoy with ' .. #ConvoyMembers .. ' member(s).',
        type = 'success',
        duration = 5000,
    })

    StartConvoyTracking()
end)

--- Server confirms convoy leave.
RegisterNetEvent('trucking:client:convoyLeft', function(data)
    StopConvoyTracking()

    lib.notify({
        title = 'Convoy',
        description = 'You have left the convoy.',
        type = 'inform',
    })
end)

--- Server sends updated convoy member list and positions.
RegisterNetEvent('trucking:client:convoyMemberUpdate', function(data)
    if not data or not ConvoyActive then return end

    ConvoyMembers = data.members or ConvoyMembers

    -- Check if lead changed
    for _, member in ipairs(ConvoyMembers) do
        if member.citizenid == GetCitizenId() then
            IsConvoyLead = member.isLead or false
            break
        end
    end
end)

--- Server sends convoy disbanded notification.
RegisterNetEvent('trucking:client:convoyDisbanded', function(data)
    StopConvoyTracking()

    lib.notify({
        title = 'Convoy Disbanded',
        description = data and data.reason or 'The convoy has been disbanded.',
        type = 'inform',
        duration = 5000,
    })
end)

--- Server sends convoy invitation.
RegisterNetEvent('trucking:client:convoyInvite', function(data)
    if not data then return end

    local result = lib.alertDialog({
        header = 'Convoy Invitation',
        content = '**' .. (data.leadName or 'Unknown') .. '** invites you to join their '
            .. (data.convoyType or 'open') .. ' convoy.\n\n'
            .. 'Members: ' .. (data.memberCount or 1) .. '/' .. MAX_CONVOY_SIZE,
        centered = true,
        cancel = true,
        labels = {
            confirm = 'Join Convoy',
            cancel = 'Decline',
        },
    })

    if result == 'confirm' then
        JoinConvoy(data.convoyId)
    end
end)

--- Notification when a nearby convoy is forming (open convoys).
RegisterNetEvent('trucking:client:nearbyConvoyForming', function(data)
    if not data then return end
    if ConvoyActive then return end -- already in a convoy

    lib.notify({
        title = 'Convoy Forming Nearby',
        description = (data.leadName or 'A driver') .. ' is forming an open convoy nearby.\n'
            .. 'Members: ' .. (data.memberCount or 1) .. '/' .. MAX_CONVOY_SIZE,
        type = 'inform',
        duration = 8000,
    })
end)

--- Server notifies that an open convoy is forming nearby
RegisterNetEvent('trucking:client:convoyForming', function(data)
    if not data then return end
    if ConvoyActive then return end
    lib.notify({
        title = 'Convoy Forming',
        description = (data.leadName or 'A driver') .. ' is forming a '
            .. (data.convoyType or 'open') .. ' convoy. '
            .. (data.memberCount or 1) .. '/' .. MAX_CONVOY_SIZE .. ' members.',
        type = 'inform',
        duration = 8000,
    })
end)

--- Server broadcasts updated convoy member positions
RegisterNetEvent('trucking:client:convoyMembersUpdate', function(data)
    if not data or not ConvoyActive then return end
    ConvoyMembers = data.members or ConvoyMembers
    for _, member in ipairs(ConvoyMembers) do
        if member.citizenid == GetCitizenId() then
            IsConvoyLead = member.isLead or false
            break
        end
    end
    UpdateProximity()
end)

--- Server notifies that the convoy has started (all members confirmed)
RegisterNetEvent('trucking:client:convoyStarted', function(data)
    if not data or not ConvoyActive then return end
    lib.notify({
        title = 'Convoy Started',
        description = 'All members ready. Convoy is now active with '
            .. (data.memberCount or #ConvoyMembers) .. ' members.',
        type = 'success',
        duration = 6000,
    })
end)

--- Server notifies convoy is unguarded (military escort destroyed)
RegisterNetEvent('trucking:client:convoyUnguarded', function(data)
    if not data then return end
    lib.notify({
        title = 'Convoy Unguarded',
        description = data.reason or 'Military escort neutralized. Proceed with caution.',
        type = 'error',
        duration = 8000,
    })
end)

--- Server responds to convoy creation request
RegisterNetEvent('trucking:client:createConvoyResult', function(data)
    if not data then return end
    if data.success then
        ConvoyId = data.convoyId
        ConvoyType = data.convoyType
        IsConvoyLead = true
        ConvoyActive = true
        ConvoyMembers = data.members or {}
        lib.notify({
            title = 'Convoy Formed',
            description = 'You are the convoy lead. Type: ' .. (ConvoyType or 'open'),
            type = 'success',
            duration = 6000,
        })
        StartConvoyTracking()
    else
        lib.notify({
            title = 'Convoy Failed',
            description = data.reason or 'Unable to create convoy.',
            type = 'error',
        })
    end
end)

--- Server responds to join convoy request
RegisterNetEvent('trucking:client:joinConvoyResult', function(data)
    if not data then return end
    if data.success then
        ConvoyId = data.convoyId
        ConvoyType = data.convoyType
        IsConvoyLead = data.isLead or false
        ConvoyActive = true
        ConvoyMembers = data.members or {}
        lib.notify({
            title = 'Convoy Joined',
            description = 'Joined convoy with ' .. #ConvoyMembers .. ' member(s).',
            type = 'success',
            duration = 5000,
        })
        StartConvoyTracking()
    else
        lib.notify({
            title = 'Join Failed',
            description = data.reason or 'Unable to join convoy.',
            type = 'error',
        })
    end
end)

-- ─────────────────────────────────────────────
-- PROXIMITY TRACKING THREAD
-- ─────────────────────────────────────────────

--- Start the convoy proximity tracking thread.
--- Sends player position to server every 5 seconds and updates HUD.
function StartConvoyTracking()
    if not ConvoyActive then return end

    CreateThread(function()
        while ConvoyActive do
            -- Send own position to server for relay to other convoy members
            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)
            local vehicle = GetVehiclePedIsIn(ped, false)
            local speed = 0
            if vehicle and vehicle ~= 0 then
                speed = math.floor(GetEntitySpeed(vehicle) * 2.23694) -- mph
            end

            TriggerServerEvent('trucking:server:updateConvoyPosition', ConvoyId, {
                x = coords.x,
                y = coords.y,
                z = coords.z,
                speed = speed,
            })

            -- Update local proximity calculations and HUD
            UpdateProximity()

            Wait(PROXIMITY_UPDATE_MS)
        end
    end)
end

--- Stop convoy tracking, remove blips, clear state.
function StopConvoyTracking()
    ConvoyActive = false
    ConvoyId = nil
    ConvoyType = nil
    IsConvoyLead = false
    ConvoyMembers = {}

    RemoveAllBlips()

    -- Clear convoy HUD
    SendNUIMessage({
        action = 'convoyUpdate',
        data = {
            convoyId = nil,
            members = {},
            memberCount = 0,
        },
    })
end

-- ─────────────────────────────────────────────
-- QUERY FUNCTIONS
-- ─────────────────────────────────────────────

--- Check if the player is in a convoy.
---@return boolean inConvoy
function IsInConvoy()
    return ConvoyActive
end

--- Get current convoy ID.
---@return number|nil convoyId
function GetConvoyId()
    return ConvoyId
end

--- Get convoy member count.
---@return number count
function GetConvoyMemberCount()
    return #ConvoyMembers
end

-- ─────────────────────────────────────────────
-- EVENT LISTENERS
-- ─────────────────────────────────────────────

--- Stop all monitoring on state cleanup.
AddEventHandler('trucking:client:stopAllMonitoring', function()
    if ConvoyActive then
        LeaveConvoy()
    end
    StopConvoyTracking()
end)

--- Player unloaded — leave convoy.
RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    StopConvoyTracking()
end)

-- ─────────────────────────────────────────────
-- RESOURCE CLEANUP
-- ─────────────────────────────────────────────
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    StopConvoyTracking()
end)
