--[[
    server/company.lua — Company and Dispatcher System

    Manages trucking companies with three roles:
        Owner      — Creates company, invites/removes members, assigns dispatcher
        Dispatcher — Monitors loads, assigns board loads to drivers, cannot drive while dispatching
        Driver     — Accepts assigned loads, participates in convoys

    Companies allow coordinated trucking operations with a dispatcher
    providing real-time load assignment and monitoring.
]]

-- ─────────────────────────────────────────────
-- IN-MEMORY STATE
-- ─────────────────────────────────────────────

--- Track which players are currently in dispatch mode
--- [citizenid] = true
local DispatchModeActive = {}

--- Pending company invites: [targetCitizenId] = { companyId, inviterCitizenId, expiresAt }
local PendingInvites = {}

-- ─────────────────────────────────────────────
-- COMPANY CREATION
-- ─────────────────────────────────────────────

--- Create a new trucking company
---@param src number Player server ID
---@param companyName string Desired company name
---@return boolean success
---@return string|number result Error message or company ID
function CreateCompany(src, companyName)
    if not src or not companyName then
        return false, 'missing_parameters'
    end

    local player = exports.qbx_core:GetPlayer(src)
    if not player then
        return false, 'player_not_found'
    end
    local citizenid = player.PlayerData.citizenid

    -- Validate company name (2-50 chars, alphanumeric + spaces)
    companyName = companyName:match('^%s*(.-)%s*$')  -- trim whitespace
    if not companyName or #companyName < 2 or #companyName > 50 then
        return false, 'invalid_name_length'
    end
    if not companyName:match('^[%w%s]+$') then
        return false, 'invalid_name_characters'
    end

    -- Check player is not already in a company
    local existingMembership = MySQL.single.await(
        'SELECT id FROM truck_company_members WHERE citizenid = ?',
        { citizenid }
    )
    if existingMembership then
        return false, 'already_in_company'
    end

    -- Check name uniqueness (case-insensitive)
    local nameCheck = MySQL.single.await(
        'SELECT id FROM truck_companies WHERE LOWER(company_name) = LOWER(?)',
        { companyName }
    )
    if nameCheck then
        return false, 'name_taken'
    end

    local now = os.time()

    -- Create company record
    local companyId = MySQL.insert.await(
        'INSERT INTO truck_companies (company_name, owner_citizenid, founded_at) VALUES (?, ?, ?)',
        { companyName, citizenid, now }
    )

    if not companyId then
        return false, 'database_error'
    end

    -- Add owner as first member
    MySQL.insert.await(
        'INSERT INTO truck_company_members (company_id, citizenid, role, joined_at) VALUES (?, ?, ?, ?)',
        { companyId, citizenid, 'owner', now }
    )

    lib.notify(src, {
        title = 'Company Founded',
        description = ('"%s" has been established'):format(companyName),
        type = 'success',
    })

    print(('[trucking:company] Company "%s" (ID %d) founded by %s'):format(
        companyName, companyId, citizenid))

    return true, companyId
end

-- ─────────────────────────────────────────────
-- MEMBER MANAGEMENT
-- ─────────────────────────────────────────────

--- Invite a player to join the company (owner only)
---@param src number Player server ID (must be owner)
---@param targetCitizenId string Citizen ID of the player to invite
---@return boolean success
---@return string|nil error
function InviteMember(src, targetCitizenId)
    if not src or not targetCitizenId then
        return false, 'missing_parameters'
    end

    local player = exports.qbx_core:GetPlayer(src)
    if not player then
        return false, 'player_not_found'
    end
    local citizenid = player.PlayerData.citizenid

    -- Verify caller is a company owner
    local company = MySQL.single.await(
        'SELECT id, company_name FROM truck_companies WHERE owner_citizenid = ?',
        { citizenid }
    )
    if not company then
        return false, 'not_owner'
    end

    -- Check target is not already in a company
    local targetMembership = MySQL.single.await(
        'SELECT id FROM truck_company_members WHERE citizenid = ?',
        { targetCitizenId }
    )
    if targetMembership then
        return false, 'target_already_in_company'
    end

    -- Check for existing pending invite
    if PendingInvites[targetCitizenId] then
        return false, 'invite_already_pending'
    end

    -- Store pending invite (expires in 60 seconds)
    PendingInvites[targetCitizenId] = {
        companyId = company.id,
        companyName = company.company_name,
        inviterCitizenId = citizenid,
        expiresAt = os.time() + 60,
    }

    -- Notify target player if online
    local targetSrc = exports.qbx_core:GetPlayerByCitizenId(targetCitizenId)
    if targetSrc then
        TriggerClientEvent('trucking:client:companyInvite', targetSrc, {
            companyId = company.id,
            companyName = company.company_name,
            inviterName = player.PlayerData.charinfo.firstname .. ' ' .. player.PlayerData.charinfo.lastname,
        })
    else
        -- Clear invite if player is offline
        PendingInvites[targetCitizenId] = nil
        return false, 'target_offline'
    end

    return true
end

--- Accept a pending company invite (called by the invited player)
RegisterNetEvent('trucking:server:acceptCompanyInvite', function()
    local src = source
    local player = exports.qbx_core:GetPlayer(src)
    if not player then return end
    local citizenid = player.PlayerData.citizenid

    local invite = PendingInvites[citizenid]
    if not invite then
        lib.notify(src, { title = 'Company', description = 'No pending invite found.', type = 'error' })
        return
    end

    -- Check invite expiry
    if os.time() > invite.expiresAt then
        PendingInvites[citizenid] = nil
        lib.notify(src, { title = 'Company', description = 'Invite has expired.', type = 'error' })
        return
    end

    -- Double-check not already in a company
    local existingMembership = MySQL.single.await(
        'SELECT id FROM truck_company_members WHERE citizenid = ?',
        { citizenid }
    )
    if existingMembership then
        PendingInvites[citizenid] = nil
        lib.notify(src, { title = 'Company', description = 'You are already in a company.', type = 'error' })
        return
    end

    -- Add as member
    MySQL.insert.await(
        'INSERT INTO truck_company_members (company_id, citizenid, role, joined_at) VALUES (?, ?, ?, ?)',
        { invite.companyId, citizenid, 'driver', os.time() }
    )

    PendingInvites[citizenid] = nil

    lib.notify(src, {
        title = 'Company Joined',
        description = ('You joined %s'):format(invite.companyName),
        type = 'success',
    })

    -- Notify the owner
    local ownerSrc = exports.qbx_core:GetPlayerByCitizenId(invite.inviterCitizenId)
    if ownerSrc then
        local memberName = player.PlayerData.charinfo.firstname .. ' ' .. player.PlayerData.charinfo.lastname
        lib.notify(ownerSrc, {
            title = 'New Member',
            description = ('%s has joined your company'):format(memberName),
            type = 'success',
        })
    end

    print(('[trucking:company] %s joined company %d (%s)'):format(
        citizenid, invite.companyId, invite.companyName))
end)

--- Decline a pending company invite
RegisterNetEvent('trucking:server:declineCompanyInvite', function()
    local src = source
    local player = exports.qbx_core:GetPlayer(src)
    if not player then return end
    local citizenid = player.PlayerData.citizenid

    PendingInvites[citizenid] = nil
    lib.notify(src, { title = 'Company', description = 'Invite declined.', type = 'inform' })
end)

--- Remove a member from the company (owner only)
---@param src number Player server ID (must be owner)
---@param targetCitizenId string Citizen ID of the member to remove
---@return boolean success
---@return string|nil error
function RemoveMember(src, targetCitizenId)
    if not src or not targetCitizenId then
        return false, 'missing_parameters'
    end

    local player = exports.qbx_core:GetPlayer(src)
    if not player then
        return false, 'player_not_found'
    end
    local citizenid = player.PlayerData.citizenid

    -- Cannot remove yourself (owner must disband company instead)
    if citizenid == targetCitizenId then
        return false, 'cannot_remove_self'
    end

    -- Verify caller is a company owner
    local company = MySQL.single.await(
        'SELECT id, dispatcher_citizenid FROM truck_companies WHERE owner_citizenid = ?',
        { citizenid }
    )
    if not company then
        return false, 'not_owner'
    end

    -- Verify target is in this company
    local membership = MySQL.single.await(
        'SELECT id FROM truck_company_members WHERE company_id = ? AND citizenid = ?',
        { company.id, targetCitizenId }
    )
    if not membership then
        return false, 'target_not_in_company'
    end

    -- Remove member
    MySQL.update.await(
        'DELETE FROM truck_company_members WHERE company_id = ? AND citizenid = ?',
        { company.id, targetCitizenId }
    )

    -- If removed member was dispatcher, clear dispatcher role
    if company.dispatcher_citizenid == targetCitizenId then
        MySQL.update.await(
            'UPDATE truck_companies SET dispatcher_citizenid = NULL WHERE id = ?',
            { company.id }
        )
        DispatchModeActive[targetCitizenId] = nil
    end

    -- Notify removed player if online
    local targetSrc = exports.qbx_core:GetPlayerByCitizenId(targetCitizenId)
    if targetSrc then
        lib.notify(targetSrc, {
            title = 'Company',
            description = 'You have been removed from the company.',
            type = 'error',
        })
        TriggerClientEvent('trucking:client:removedFromCompany', targetSrc)
    end

    print(('[trucking:company] %s removed from company %d by %s'):format(
        targetCitizenId, company.id, citizenid))

    return true
end

-- ─────────────────────────────────────────────
-- DISPATCHER ROLE
-- ─────────────────────────────────────────────

--- Assign the dispatcher role to a company member (owner only)
---@param src number Player server ID (must be owner)
---@param targetCitizenId string Citizen ID of the member to promote
---@return boolean success
---@return string|nil error
function SetDispatcher(src, targetCitizenId)
    if not src or not targetCitizenId then
        return false, 'missing_parameters'
    end

    local player = exports.qbx_core:GetPlayer(src)
    if not player then
        return false, 'player_not_found'
    end
    local citizenid = player.PlayerData.citizenid

    -- Verify caller is company owner
    local company = MySQL.single.await(
        'SELECT id, dispatcher_citizenid FROM truck_companies WHERE owner_citizenid = ?',
        { citizenid }
    )
    if not company then
        return false, 'not_owner'
    end

    -- Verify target is in the company
    local membership = MySQL.single.await(
        'SELECT id FROM truck_company_members WHERE company_id = ? AND citizenid = ?',
        { company.id, targetCitizenId }
    )
    if not membership then
        return false, 'target_not_in_company'
    end

    -- Clear previous dispatcher's dispatch mode if different person
    if company.dispatcher_citizenid and company.dispatcher_citizenid ~= targetCitizenId then
        DispatchModeActive[company.dispatcher_citizenid] = nil
        local prevSrc = exports.qbx_core:GetPlayerByCitizenId(company.dispatcher_citizenid)
        if prevSrc then
            TriggerClientEvent('trucking:client:dispatchModeDisabled', prevSrc)
            lib.notify(prevSrc, {
                title = 'Dispatcher',
                description = 'You are no longer the company dispatcher.',
                type = 'inform',
            })
        end
    end

    -- Set new dispatcher
    MySQL.update.await(
        'UPDATE truck_companies SET dispatcher_citizenid = ? WHERE id = ?',
        { targetCitizenId, company.id }
    )

    -- Notify target
    local targetSrc = exports.qbx_core:GetPlayerByCitizenId(targetCitizenId)
    if targetSrc then
        lib.notify(targetSrc, {
            title = 'Dispatcher Role',
            description = 'You have been assigned as company dispatcher.',
            type = 'success',
        })
    end

    print(('[trucking:company] %s assigned as dispatcher for company %d'):format(
        targetCitizenId, company.id))

    return true
end

-- ─────────────────────────────────────────────
-- DISPATCH MODE
-- ─────────────────────────────────────────────

--- Enable dispatch mode for the calling player
--- Blocks load acceptance while active
---@param src number Player server ID
---@return boolean success
---@return string|nil error
function EnableDispatchMode(src)
    if not src then return false, 'missing_parameters' end

    local player = exports.qbx_core:GetPlayer(src)
    if not player then return false, 'player_not_found' end
    local citizenid = player.PlayerData.citizenid

    -- Verify player is the assigned dispatcher
    local company = MySQL.single.await(
        'SELECT id FROM truck_companies WHERE dispatcher_citizenid = ?',
        { citizenid }
    )
    if not company then
        return false, 'not_dispatcher'
    end

    DispatchModeActive[citizenid] = true

    TriggerClientEvent('trucking:client:enableDispatchMode', src)

    lib.notify(src, {
        title = 'Dispatch Mode',
        description = 'Dispatch mode active. You cannot accept loads.',
        type = 'inform',
    })

    return true
end

--- Disable dispatch mode for the calling player
---@param src number Player server ID
---@return boolean success
function DisableDispatchMode(src)
    if not src then return false end

    local player = exports.qbx_core:GetPlayer(src)
    if not player then return false end
    local citizenid = player.PlayerData.citizenid

    DispatchModeActive[citizenid] = nil

    TriggerClientEvent('trucking:client:disableDispatchMode', src)

    lib.notify(src, {
        title = 'Dispatch Mode',
        description = 'Dispatch mode deactivated.',
        type = 'inform',
    })

    return true
end

--- Check if a player is currently in dispatch mode
---@param citizenid string Driver's citizen ID
---@return boolean isDispatching
function IsInDispatchMode(citizenid)
    return DispatchModeActive[citizenid] == true
end

-- ─────────────────────────────────────────────
-- LOAD ASSIGNMENT
-- ─────────────────────────────────────────────

--- Dispatcher assigns a board load to a company driver
---@param src number Player server ID (must be dispatcher in dispatch mode)
---@param loadId number The load ID from the board
---@param targetCitizenId string Citizen ID of the driver to assign to
---@return boolean success
---@return string|nil error
function AssignLoadToDriver(src, loadId, targetCitizenId)
    if not src or not loadId or not targetCitizenId then
        return false, 'missing_parameters'
    end

    local player = exports.qbx_core:GetPlayer(src)
    if not player then
        return false, 'player_not_found'
    end
    local citizenid = player.PlayerData.citizenid

    -- Verify caller is in dispatch mode
    if not DispatchModeActive[citizenid] then
        return false, 'not_in_dispatch_mode'
    end

    -- Verify caller is the company's dispatcher
    local company = MySQL.single.await(
        'SELECT id, company_name FROM truck_companies WHERE dispatcher_citizenid = ?',
        { citizenid }
    )
    if not company then
        return false, 'not_dispatcher'
    end

    -- Verify target is in the same company
    local targetMembership = MySQL.single.await(
        'SELECT id FROM truck_company_members WHERE company_id = ? AND citizenid = ?',
        { company.id, targetCitizenId }
    )
    if not targetMembership then
        return false, 'target_not_in_company'
    end

    -- Verify target is not in dispatch mode
    if DispatchModeActive[targetCitizenId] then
        return false, 'target_in_dispatch_mode'
    end

    -- Verify target is online
    local targetSrc = exports.qbx_core:GetPlayerByCitizenId(targetCitizenId)
    if not targetSrc then
        return false, 'target_offline'
    end

    -- Verify load exists and is available
    local load = MySQL.single.await(
        'SELECT * FROM truck_loads WHERE id = ? AND board_status = ?',
        { loadId, 'available' }
    )
    if not load then
        return false, 'load_not_available'
    end

    -- Send assignment notification to the target driver
    local dispatcherName = player.PlayerData.charinfo.firstname .. ' ' .. player.PlayerData.charinfo.lastname

    TriggerClientEvent('trucking:client:loadAssigned', targetSrc, {
        load_id = load.id,
        cargo_type = load.cargo_type,
        destination_label = load.destination_label,
        distance_miles = load.distance_miles,
        tier = load.tier,
        company_id = company.id,
    }, dispatcherName)

    lib.notify(src, {
        title = 'Load Assigned',
        description = ('Assigned load to driver'):format(),
        type = 'success',
    })

    print(('[trucking:company] Dispatcher %s assigned load %d to driver %s'):format(
        citizenid, loadId, targetCitizenId))

    return true
end

-- ─────────────────────────────────────────────
-- COMPANY QUERIES
-- ─────────────────────────────────────────────

--- Get all members of a company with their online status
---@param companyId number The company ID
---@return table members Array of member records with online status
function GetCompanyMembers(companyId)
    if not companyId then return {} end

    local members = MySQL.query.await([[
        SELECT cm.citizenid, cm.role, cm.joined_at,
               td.player_name, td.reputation_score, td.reputation_tier
        FROM truck_company_members cm
        LEFT JOIN truck_drivers td ON cm.citizenid = td.citizenid
        WHERE cm.company_id = ?
        ORDER BY FIELD(cm.role, 'owner', 'driver'), cm.joined_at ASC
    ]], { companyId })

    if not members then return {} end

    -- Enrich with online status and dispatch mode
    for _, member in ipairs(members) do
        local memberSrc = exports.qbx_core:GetPlayerByCitizenId(member.citizenid)
        member.online = memberSrc ~= nil and memberSrc ~= false
        member.in_dispatch_mode = DispatchModeActive[member.citizenid] == true
    end

    return members
end

--- Get all active loads for company members (dispatcher view)
---@param companyId number The company ID
---@return table loads Array of active load records
function GetCompanyActiveLoads(companyId)
    if not companyId then return {} end

    local loads = MySQL.query.await([[
        SELECT al.*, tl.cargo_type, tl.destination_label, tl.distance_miles,
               tl.tier, td.player_name
        FROM truck_active_loads al
        JOIN truck_loads tl ON al.load_id = tl.id
        LEFT JOIN truck_drivers td ON al.citizenid = td.citizenid
        WHERE al.company_id = ?
        ORDER BY al.accepted_at DESC
    ]], { companyId })

    return loads or {}
end

--- Get the company a player belongs to (if any)
---@param citizenid string Driver's citizen ID
---@return table|nil companyData Company record with role, or nil
function GetCompanyByPlayer(citizenid)
    if not citizenid then return nil end

    local membership = MySQL.single.await([[
        SELECT cm.company_id, cm.role, cm.joined_at,
               tc.company_name, tc.owner_citizenid, tc.dispatcher_citizenid
        FROM truck_company_members cm
        JOIN truck_companies tc ON cm.company_id = tc.id
        WHERE cm.citizenid = ?
    ]], { citizenid })

    return membership
end

-- ─────────────────────────────────────────────
-- NET EVENTS
-- ─────────────────────────────────────────────

RegisterNetEvent('trucking:server:createCompany', function(companyName)
    local src = source
    if not RateLimitEvent(src, 'createCompany', 10000) then return end

    local success, result = CreateCompany(src, companyName)
    TriggerClientEvent('trucking:client:createCompanyResult', src, success, result)
end)

RegisterNetEvent('trucking:server:inviteMember', function(targetCitizenId)
    local src = source
    if not RateLimitEvent(src, 'inviteMember', 5000) then return end

    local success, err = InviteMember(src, targetCitizenId)
    if not success then
        lib.notify(src, { title = 'Company', description = 'Failed to send invite: ' .. (err or 'unknown'), type = 'error' })
    else
        lib.notify(src, { title = 'Company', description = 'Invite sent.', type = 'success' })
    end
end)

RegisterNetEvent('trucking:server:removeMember', function(targetCitizenId)
    local src = source
    if not RateLimitEvent(src, 'removeMember', 5000) then return end

    local success, err = RemoveMember(src, targetCitizenId)
    if not success then
        lib.notify(src, { title = 'Company', description = 'Failed to remove member: ' .. (err or 'unknown'), type = 'error' })
    end
end)

RegisterNetEvent('trucking:server:setDispatcher', function(targetCitizenId)
    local src = source
    if not RateLimitEvent(src, 'setDispatcher', 5000) then return end

    local success, err = SetDispatcher(src, targetCitizenId)
    if not success then
        lib.notify(src, { title = 'Company', description = 'Failed to set dispatcher: ' .. (err or 'unknown'), type = 'error' })
    end
end)

RegisterNetEvent('trucking:server:enableDispatchMode', function()
    local src = source
    if not RateLimitEvent(src, 'enableDispatchMode', 3000) then return end
    EnableDispatchMode(src)
end)

RegisterNetEvent('trucking:server:disableDispatchMode', function()
    local src = source
    if not RateLimitEvent(src, 'disableDispatchMode', 3000) then return end
    DisableDispatchMode(src)
end)

RegisterNetEvent('trucking:server:assignLoadToDriver', function(loadId, targetCitizenId)
    local src = source
    if not RateLimitEvent(src, 'assignLoadToDriver', 3000) then return end

    local success, err = AssignLoadToDriver(src, loadId, targetCitizenId)
    if not success then
        lib.notify(src, { title = 'Dispatch', description = 'Assignment failed: ' .. (err or 'unknown'), type = 'error' })
    end
end)

RegisterNetEvent('trucking:server:getCompanyMembers', function()
    local src = source
    local player = exports.qbx_core:GetPlayer(src)
    if not player then return end

    local company = GetCompanyByPlayer(player.PlayerData.citizenid)
    if not company then
        TriggerClientEvent('trucking:client:companyMembers', src, {})
        return
    end

    local members = GetCompanyMembers(company.company_id)
    TriggerClientEvent('trucking:client:companyMembers', src, members)
end)

RegisterNetEvent('trucking:server:getCompanyActiveLoads', function()
    local src = source
    local player = exports.qbx_core:GetPlayer(src)
    if not player then return end

    local company = GetCompanyByPlayer(player.PlayerData.citizenid)
    if not company then
        TriggerClientEvent('trucking:client:companyActiveLoads', src, {})
        return
    end

    local loads = GetCompanyActiveLoads(company.company_id)
    TriggerClientEvent('trucking:client:companyActiveLoads', src, loads)
end)

-- ─────────────────────────────────────────────
-- INVITE EXPIRY CLEANUP THREAD
-- Clears stale pending invites every 30 seconds
-- ─────────────────────────────────────────────

CreateThread(function()
    while true do
        Wait(30000)
        local now = os.time()
        for targetCid, invite in pairs(PendingInvites) do
            if now > invite.expiresAt then
                PendingInvites[targetCid] = nil
            end
        end
    end
end)

-- Clean up dispatch mode when player drops
AddEventHandler('playerDropped', function()
    local src = source
    local player = exports.qbx_core:GetPlayer(src)
    if player then
        DispatchModeActive[player.PlayerData.citizenid] = nil
    end
end)

print('[trucking:company] Company and dispatcher system initialized')
