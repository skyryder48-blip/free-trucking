--[[
    server/convoy.lua — Convoy System

    Manages convoy formation, membership, and completion tracking.
    Convoys allow 2-6 drivers to haul together for a payout bonus
    if all members deliver within a 15-minute window.

    Convoy types:
        open    — any driver can join
        invite  — join by invite only
        company — restricted to company members

    Convoy bonus is applied at delivery if CheckConvoyArrivalWindow passes.
    Bonus amount scales with convoy size (see Economy.ComplianceBonuses).
]]

-- ─────────────────────────────────────────────
-- CONSTANTS
-- ─────────────────────────────────────────────

local MAX_CONVOY_SIZE = 6
local CONVOY_ARRIVAL_WINDOW = 900  -- 15 minutes in seconds

-- ─────────────────────────────────────────────
-- IN-MEMORY STATE
-- Convoy member tracking for position updates
-- ─────────────────────────────────────────────

--- [convoyId] = { [citizenid] = { src, coords, deliveredAt } }
local ConvoyMembers = {}

-- ─────────────────────────────────────────────
-- CONVOY CREATION
-- ─────────────────────────────────────────────

--- Create a new convoy and add the creator as the first member
---@param src number Player server ID
---@param convoyType string 'open', 'invite', or 'company'
---@return boolean success
---@return string|number result Error message or convoy ID
function CreateConvoy(src, convoyType)
    if not src or not convoyType then
        return false, 'missing_parameters'
    end

    local player = exports.qbx_core:GetPlayer(src)
    if not player then
        return false, 'player_not_found'
    end
    local citizenid = player.PlayerData.citizenid

    -- Validate convoy type
    local validTypes = { open = true, invite = true, company = true }
    if not validTypes[convoyType] then
        return false, 'invalid_convoy_type'
    end

    -- Check player is not already in a convoy
    for convoyId, members in pairs(ConvoyMembers) do
        if members[citizenid] then
            return false, 'already_in_convoy'
        end
    end

    -- For company convoys, verify player is in a company
    local companyId = nil
    if convoyType == 'company' then
        local company = GetCompanyByPlayer(citizenid)
        if not company then
            return false, 'not_in_company'
        end
        companyId = company.company_id
    end

    local now = GetServerTime()

    -- Create convoy record in database
    local convoyId = MySQL.insert.await([[
        INSERT INTO truck_convoys
        (initiated_by, company_id, convoy_type, status, vehicle_count, created_at)
        VALUES (?, ?, ?, 'forming', 1, ?)
    ]], { citizenid, companyId, convoyType, now })

    if not convoyId then
        return false, 'database_error'
    end

    -- Initialize in-memory tracking
    ConvoyMembers[convoyId] = {
        [citizenid] = {
            src = src,
            coords = nil,
            deliveredAt = nil,
        }
    }

    -- Notify region players if open convoy
    if convoyType == 'open' then
        local ped = GetPlayerPed(src)
        if ped and ped ~= 0 then
            local coords = GetEntityCoords(ped)
            -- Broadcast to all connected players in the trucking system
            TriggerClientEvent('trucking:client:convoyForming', -1, {
                convoyId = convoyId,
                initiator = player.PlayerData.charinfo.firstname,
                coords = coords,
                convoyType = convoyType,
            })
        end
    end

    lib.notify(src, {
        title = 'Convoy Created',
        description = ('Convoy #%d formed. Waiting for drivers.'):format(convoyId),
        type = 'success',
    })

    print(('[trucking:convoy] Convoy %d created by %s (type: %s)'):format(
        convoyId, citizenid, convoyType))

    return true, convoyId
end

-- ─────────────────────────────────────────────
-- CONVOY MEMBERSHIP
-- ─────────────────────────────────────────────

--- Join an existing convoy
---@param src number Player server ID
---@param convoyId number The convoy ID to join
---@return boolean success
---@return string|nil error
function JoinConvoy(src, convoyId)
    if not src or not convoyId then
        return false, 'missing_parameters'
    end

    local player = exports.qbx_core:GetPlayer(src)
    if not player then
        return false, 'player_not_found'
    end
    local citizenid = player.PlayerData.citizenid

    -- Check player is not already in a convoy
    for cId, members in pairs(ConvoyMembers) do
        if members[citizenid] then
            return false, 'already_in_convoy'
        end
    end

    -- Verify convoy exists and is in forming state
    local convoy = MySQL.single.await(
        'SELECT * FROM truck_convoys WHERE id = ? AND status = ?',
        { convoyId, 'forming' }
    )
    if not convoy then
        return false, 'convoy_not_found_or_started'
    end

    -- Check convoy is not full
    local memberCount = GetConvoySize(convoyId)
    if memberCount >= MAX_CONVOY_SIZE then
        return false, 'convoy_full'
    end

    -- For company convoys, verify player is in the same company
    if convoy.convoy_type == 'company' and convoy.company_id then
        local company = GetCompanyByPlayer(citizenid)
        if not company or company.company_id ~= convoy.company_id then
            return false, 'not_in_same_company'
        end
    end

    -- Add to in-memory tracking
    if not ConvoyMembers[convoyId] then
        ConvoyMembers[convoyId] = {}
    end
    ConvoyMembers[convoyId][citizenid] = {
        src = src,
        coords = nil,
        deliveredAt = nil,
    }

    -- Update vehicle count in database
    MySQL.update.await(
        'UPDATE truck_convoys SET vehicle_count = vehicle_count + 1 WHERE id = ?',
        { convoyId }
    )

    -- Notify all convoy members
    local memberName = player.PlayerData.charinfo.firstname .. ' ' .. player.PlayerData.charinfo.lastname
    for memberCid, memberData in pairs(ConvoyMembers[convoyId]) do
        if memberCid ~= citizenid and memberData.src then
            lib.notify(memberData.src, {
                title = 'Convoy',
                description = ('%s joined the convoy'):format(memberName),
                type = 'inform',
            })
        end
    end

    lib.notify(src, {
        title = 'Convoy Joined',
        description = ('Joined convoy #%d (%d/%d)'):format(convoyId, memberCount + 1, MAX_CONVOY_SIZE),
        type = 'success',
    })

    print(('[trucking:convoy] %s joined convoy %d'):format(citizenid, convoyId))

    return true
end

--- Leave a convoy
---@param src number Player server ID
---@param convoyId number The convoy ID to leave
---@return boolean success
---@return string|nil error
function LeaveConvoy(src, convoyId)
    if not src or not convoyId then
        return false, 'missing_parameters'
    end

    local player = exports.qbx_core:GetPlayer(src)
    if not player then
        return false, 'player_not_found'
    end
    local citizenid = player.PlayerData.citizenid

    -- Verify player is in this convoy
    if not ConvoyMembers[convoyId] or not ConvoyMembers[convoyId][citizenid] then
        return false, 'not_in_convoy'
    end

    -- Remove from in-memory tracking
    ConvoyMembers[convoyId][citizenid] = nil

    -- Update vehicle count
    MySQL.update.await(
        'UPDATE truck_convoys SET vehicle_count = GREATEST(vehicle_count - 1, 0) WHERE id = ?',
        { convoyId }
    )

    -- Check if convoy is now empty — disband
    local remaining = 0
    for _ in pairs(ConvoyMembers[convoyId]) do
        remaining = remaining + 1
    end

    if remaining == 0 then
        DisbandConvoy(convoyId)
    else
        -- Notify remaining members
        local memberName = player.PlayerData.charinfo.firstname .. ' ' .. player.PlayerData.charinfo.lastname
        for memberCid, memberData in pairs(ConvoyMembers[convoyId]) do
            if memberData.src then
                lib.notify(memberData.src, {
                    title = 'Convoy',
                    description = ('%s left the convoy'):format(memberName),
                    type = 'inform',
                })
            end
        end
    end

    lib.notify(src, {
        title = 'Convoy Left',
        description = 'You have left the convoy.',
        type = 'inform',
    })

    print(('[trucking:convoy] %s left convoy %d'):format(citizenid, convoyId))

    return true
end

-- ─────────────────────────────────────────────
-- CONVOY LIFECYCLE
-- ─────────────────────────────────────────────

--- Start a convoy (set status to active, record start time)
---@param convoyId number The convoy ID
---@return boolean success
---@return string|nil error
function StartConvoy(convoyId)
    if not convoyId then return false, 'missing_parameters' end

    local convoy = MySQL.single.await(
        'SELECT * FROM truck_convoys WHERE id = ? AND status = ?',
        { convoyId, 'forming' }
    )
    if not convoy then
        return false, 'convoy_not_found_or_already_started'
    end

    -- Require at least 2 members to start
    local memberCount = GetConvoySize(convoyId)
    if memberCount < 2 then
        return false, 'need_minimum_two_members'
    end

    local now = GetServerTime()

    MySQL.update.await(
        'UPDATE truck_convoys SET status = ?, started_at = ? WHERE id = ?',
        { 'active', now, convoyId }
    )

    -- Notify all members
    if ConvoyMembers[convoyId] then
        for memberCid, memberData in pairs(ConvoyMembers[convoyId]) do
            if memberData.src then
                lib.notify(memberData.src, {
                    title = 'Convoy Active',
                    description = ('Convoy #%d is now rolling. Stay together!'):format(convoyId),
                    type = 'success',
                })
                TriggerClientEvent('trucking:client:convoyStarted', memberData.src, convoyId)
            end
        end
    end

    print(('[trucking:convoy] Convoy %d started with %d members'):format(convoyId, memberCount))

    return true
end

--- Check if all convoy members have delivered within the specified window
--- Used at delivery time to determine if the convoy bonus applies
---@param convoyId number The convoy ID
---@param windowSeconds number Maximum seconds between first and last delivery (default 900 = 15 min)
---@return boolean allArrived Whether all members delivered within the window
function CheckConvoyArrivalWindow(convoyId, windowSeconds)
    windowSeconds = windowSeconds or CONVOY_ARRIVAL_WINDOW

    if not ConvoyMembers[convoyId] then
        return false
    end

    local deliveryTimes = {}
    local totalMembers = 0
    local deliveredCount = 0

    for citizenid, memberData in pairs(ConvoyMembers[convoyId]) do
        totalMembers = totalMembers + 1
        if memberData.deliveredAt then
            deliveredCount = deliveredCount + 1
            table.insert(deliveryTimes, memberData.deliveredAt)
        end
    end

    -- All members must have delivered
    if deliveredCount < totalMembers then
        return false
    end

    -- Check window between earliest and latest delivery
    if #deliveryTimes < 2 then
        return true  -- single member convoy (shouldn't happen, but safe)
    end

    table.sort(deliveryTimes)
    local earliest = deliveryTimes[1]
    local latest = deliveryTimes[#deliveryTimes]

    return (latest - earliest) <= windowSeconds
end

--- Get the number of members in a convoy
---@param convoyId number The convoy ID
---@return number count
function GetConvoySize(convoyId)
    if not convoyId then return 0 end

    if ConvoyMembers[convoyId] then
        local count = 0
        for _ in pairs(ConvoyMembers[convoyId]) do
            count = count + 1
        end
        return count
    end

    -- Fallback to database if not in memory
    local convoy = MySQL.single.await(
        'SELECT vehicle_count FROM truck_convoys WHERE id = ?',
        { convoyId }
    )

    return convoy and convoy.vehicle_count or 0
end

--- Get all members of a convoy with their positions
---@param convoyId number The convoy ID
---@return table members Array of { citizenid, src, coords, deliveredAt }
function GetConvoyMembers(convoyId)
    if not convoyId or not ConvoyMembers[convoyId] then
        return {}
    end

    local members = {}
    for citizenid, data in pairs(ConvoyMembers[convoyId]) do
        -- Update coords from server entity if player is online
        local coords = data.coords
        if data.src then
            local ped = GetPlayerPed(data.src)
            if ped and ped ~= 0 then
                coords = GetEntityCoords(ped)
            end
        end

        table.insert(members, {
            citizenid = citizenid,
            src = data.src,
            coords = coords,
            deliveredAt = data.deliveredAt,
        })
    end

    return members
end

--- Complete a convoy (all members have delivered)
---@param convoyId number The convoy ID
---@return boolean success
function CompleteConvoy(convoyId)
    if not convoyId then return false end

    local now = GetServerTime()

    MySQL.update.await(
        'UPDATE truck_convoys SET status = ?, completed_at = ? WHERE id = ?',
        { 'completed', now, convoyId }
    )

    -- Notify all members of completion
    if ConvoyMembers[convoyId] then
        local allInWindow = CheckConvoyArrivalWindow(convoyId, CONVOY_ARRIVAL_WINDOW)
        for memberCid, memberData in pairs(ConvoyMembers[convoyId]) do
            if memberData.src then
                if allInWindow then
                    lib.notify(memberData.src, {
                        title = 'Convoy Complete',
                        description = 'All members delivered within window. Convoy bonus applied!',
                        type = 'success',
                    })
                else
                    lib.notify(memberData.src, {
                        title = 'Convoy Complete',
                        description = 'Convoy finished, but arrival window exceeded. No bonus.',
                        type = 'inform',
                    })
                end
            end
        end
    end

    -- Clean up in-memory state
    ConvoyMembers[convoyId] = nil

    print(('[trucking:convoy] Convoy %d completed'):format(convoyId))

    return true
end

--- Disband a convoy (cleanup without completion)
---@param convoyId number The convoy ID
---@return boolean success
function DisbandConvoy(convoyId)
    if not convoyId then return false end

    -- Notify remaining members before cleanup
    if ConvoyMembers[convoyId] then
        for memberCid, memberData in pairs(ConvoyMembers[convoyId]) do
            if memberData.src then
                lib.notify(memberData.src, {
                    title = 'Convoy Disbanded',
                    description = 'The convoy has been disbanded.',
                    type = 'inform',
                })
                TriggerClientEvent('trucking:client:convoyDisbanded', memberData.src, convoyId)
            end
        end
    end

    MySQL.update.await(
        'UPDATE truck_convoys SET status = ? WHERE id = ? AND status IN (?, ?)',
        { 'disbanded', convoyId, 'forming', 'active' }
    )

    -- Clean up in-memory state
    ConvoyMembers[convoyId] = nil

    print(('[trucking:convoy] Convoy %d disbanded'):format(convoyId))

    return true
end

-- ─────────────────────────────────────────────
-- CONVOY MEMBER DELIVERY TRACKING
-- Called by the delivery system when a convoy member completes
-- ─────────────────────────────────────────────

--- Record that a convoy member has delivered
---@param convoyId number The convoy ID
---@param citizenid string The delivering driver's citizen ID
function RecordConvoyDelivery(convoyId, citizenid)
    if not convoyId or not citizenid then return end
    if not ConvoyMembers[convoyId] or not ConvoyMembers[convoyId][citizenid] then return end

    ConvoyMembers[convoyId][citizenid].deliveredAt = GetServerTime()

    -- Check if all members have now delivered
    local totalMembers = 0
    local deliveredCount = 0
    for _, data in pairs(ConvoyMembers[convoyId]) do
        totalMembers = totalMembers + 1
        if data.deliveredAt then
            deliveredCount = deliveredCount + 1
        end
    end

    if deliveredCount >= totalMembers then
        CompleteConvoy(convoyId)
    end
end

-- ─────────────────────────────────────────────
-- NET EVENTS
-- ─────────────────────────────────────────────

RegisterNetEvent('trucking:server:createConvoy', function(convoyType)
    local src = source
    if not RateLimitEvent(src, 'createConvoy', 10000) then return end

    local success, result = CreateConvoy(src, convoyType)
    TriggerClientEvent('trucking:client:createConvoyResult', src, success, result)
end)

RegisterNetEvent('trucking:server:joinConvoy', function(convoyId)
    local src = source
    if not RateLimitEvent(src, 'joinConvoy', 5000) then return end

    local success, err = JoinConvoy(src, convoyId)
    TriggerClientEvent('trucking:client:joinConvoyResult', src, success, err)
end)

RegisterNetEvent('trucking:server:leaveConvoy', function(convoyId)
    local src = source
    if not RateLimitEvent(src, 'leaveConvoy', 3000) then return end

    LeaveConvoy(src, convoyId)
end)

RegisterNetEvent('trucking:server:startConvoy', function(convoyId)
    local src = source
    if not RateLimitEvent(src, 'startConvoy', 10000) then return end

    -- Only the convoy initiator can start it
    local player = exports.qbx_core:GetPlayer(src)
    if not player then return end
    local citizenid = player.PlayerData.citizenid

    local convoy = MySQL.single.await(
        'SELECT initiated_by FROM truck_convoys WHERE id = ?',
        { convoyId }
    )
    if not convoy or convoy.initiated_by ~= citizenid then
        lib.notify(src, { title = 'Convoy', description = 'Only the convoy creator can start it.', type = 'error' })
        return
    end

    local success, err = StartConvoy(convoyId)
    if not success then
        lib.notify(src, { title = 'Convoy', description = err or 'Failed to start convoy.', type = 'error' })
    end
end)

RegisterNetEvent('trucking:server:disbandConvoy', function(convoyId)
    local src = source
    if not RateLimitEvent(src, 'disbandConvoy', 10000) then return end

    -- Only the convoy initiator can disband it
    local player = exports.qbx_core:GetPlayer(src)
    if not player then return end
    local citizenid = player.PlayerData.citizenid

    local convoy = MySQL.single.await(
        'SELECT initiated_by FROM truck_convoys WHERE id = ?',
        { convoyId }
    )
    if not convoy or convoy.initiated_by ~= citizenid then
        lib.notify(src, { title = 'Convoy', description = 'Only the convoy creator can disband it.', type = 'error' })
        return
    end

    DisbandConvoy(convoyId)
end)

--- Convoy member position update (from client every 5 seconds)
RegisterNetEvent('trucking:server:updateConvoyPosition', function(convoyId, coords)
    local src = source
    local player = exports.qbx_core:GetPlayer(src)
    if not player then return end
    local citizenid = player.PlayerData.citizenid

    if ConvoyMembers[convoyId] and ConvoyMembers[convoyId][citizenid] then
        ConvoyMembers[convoyId][citizenid].coords = coords
    end
end)

--- Request convoy members data (for HUD overlay)
RegisterNetEvent('trucking:server:getConvoyMembers', function(convoyId)
    local src = source
    if not convoyId then return end

    local members = GetConvoyMembers(convoyId)
    TriggerClientEvent('trucking:client:convoyMembersUpdate', src, members)
end)

-- ─────────────────────────────────────────────
-- CLEANUP ON PLAYER DROP
-- ─────────────────────────────────────────────

AddEventHandler('playerDropped', function()
    local src = source
    local player = exports.qbx_core:GetPlayer(src)
    if not player then return end
    local citizenid = player.PlayerData.citizenid

    -- Find and remove from any convoy
    for convoyId, members in pairs(ConvoyMembers) do
        if members[citizenid] then
            members[citizenid] = nil

            -- Update vehicle count
            MySQL.update.await(
                'UPDATE truck_convoys SET vehicle_count = GREATEST(vehicle_count - 1, 0) WHERE id = ?',
                { convoyId }
            )

            -- Check if convoy is now empty
            local remaining = 0
            for _ in pairs(members) do
                remaining = remaining + 1
            end

            if remaining == 0 then
                DisbandConvoy(convoyId)
            else
                -- Notify remaining members
                for memberCid, memberData in pairs(members) do
                    if memberData.src then
                        lib.notify(memberData.src, {
                            title = 'Convoy',
                            description = 'A convoy member has disconnected.',
                            type = 'inform',
                        })
                    end
                end
            end

            break  -- player can only be in one convoy
        end
    end
end)

--- Send convoy invite to another player
RegisterNetEvent('trucking:server:inviteToConvoy', function(convoyId, targetCitizenId)
    local src = source
    local player = exports.qbx_core:GetPlayer(src)
    if not player then return end
    if not RateLimitEvent(src, 'convoyInvite', 5000) then return end

    local convoy = Convoys[convoyId]
    if not convoy then return end

    -- Verify sender is in the convoy
    local citizenid = player.PlayerData.citizenid
    if not ConvoyMembers[convoyId] or not ConvoyMembers[convoyId][citizenid] then return end

    -- Find target player
    local targetSrc = GetPlayerByIdentifier(targetCitizenId)
    if not targetSrc then
        lib.notify(src, { title = 'Convoy', description = 'Player not online.', type = 'error' })
        return
    end

    TriggerClientEvent('trucking:client:convoyInvite', targetSrc, {
        convoyId = convoyId,
        invitedBy = citizenid,
        convoyType = convoy.convoy_type,
    })
end)

print('[trucking:convoy] Convoy system initialized')
