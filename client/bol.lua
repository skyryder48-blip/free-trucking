--[[
    client/bol.lua — Physical BOL Item Interactions
    Free Trucking — QBX Framework

    Responsibilities:
    - ox_inventory item use handler for 'trucking_bol': opens BOL detail view in NUI
    - BOL item metadata display (bol_number, cargo_type, shipper, destination, issued_at)
    - Insurance claim interaction: at Vapid office, select BOL from inventory, trigger server claim
]]

-- ─────────────────────────────────────────────
-- BOL ITEM USE HANDLER
-- ─────────────────────────────────────────────
--- Register the trucking_bol item as usable via ox_inventory.
--- When used, opens the BOL detail view showing metadata.
exports.ox_inventory:registerHook('usingItem', function(payload)
    if payload.item.name ~= 'trucking_bol' then return true end

    local metadata = payload.item.metadata or {}

    -- Display BOL details via NUI
    local bolData = {
        bol_number  = metadata.bol_number or 'Unknown',
        cargo_type  = metadata.cargo_type or 'Unknown',
        shipper     = metadata.shipper or 'Unknown',
        destination = metadata.destination or 'Unknown',
        issued_at   = metadata.issued_at or 0,
    }

    -- If standalone NUI is available, show full BOL view
    if Config.UseStandaloneNUI then
        OpenBOLDetailNUI(bolData)
    else
        -- Fallback: show as ox_lib context menu
        ShowBOLContextMenu(bolData)
    end

    return true  -- allow the item use
end, { itemName = 'trucking_bol' })

-- ─────────────────────────────────────────────
-- BOL DETAIL DISPLAY (NUI)
-- ─────────────────────────────────────────────

--- Open the BOL detail view in the standalone NUI panel.
---@param bolData table BOL metadata
function OpenBOLDetailNUI(bolData)
    -- Format the issued_at timestamp for display
    local issuedDisplay = 'Unknown'
    if bolData.issued_at and bolData.issued_at > 0 then
        -- Use server time to calculate relative time
        local serverNow = GetServerTime()
        if serverNow > 0 then
            local elapsed = serverNow - bolData.issued_at
            if elapsed < 3600 then
                issuedDisplay = math.floor(elapsed / 60) .. ' minutes ago'
            elseif elapsed < 86400 then
                issuedDisplay = math.floor(elapsed / 3600) .. ' hours ago'
            else
                issuedDisplay = math.floor(elapsed / 86400) .. ' days ago'
            end
        end
    end

    bolData.issued_display = issuedDisplay

    SendNUIMessage({
        action = 'showBOLDetail',
        data = bolData,
    })

    -- Only set NUI focus if not already open from another panel
    if not IsTruckingNUIOpen() then
        SetNuiFocus(true, true)
    end
end

--- Close BOL detail NUI
RegisterNUICallback('trucking:closeBOLDetail', function(_, cb)
    SendNUIMessage({ action = 'hideBOLDetail' })

    -- Only release focus if main NUI is not open
    if not IsTruckingNUIOpen() then
        SetNuiFocus(false, false)
    end

    cb({ ok = true })
end)

-- ─────────────────────────────────────────────
-- BOL DETAIL DISPLAY (CONTEXT MENU FALLBACK)
-- ─────────────────────────────────────────────

--- Show BOL details as an ox_lib context menu when NUI is not available.
---@param bolData table BOL metadata
function ShowBOLContextMenu(bolData)
    local issuedDisplay = 'Unknown'
    if bolData.issued_at and bolData.issued_at > 0 then
        local serverNow = GetServerTime()
        if serverNow > 0 then
            local elapsed = serverNow - bolData.issued_at
            if elapsed < 3600 then
                issuedDisplay = math.floor(elapsed / 60) .. ' minutes ago'
            elseif elapsed < 86400 then
                issuedDisplay = math.floor(elapsed / 3600) .. ' hours ago'
            else
                issuedDisplay = math.floor(elapsed / 86400) .. ' days ago'
            end
        end
    end

    lib.registerContext({
        id = 'trucking_bol_detail',
        title = 'Bill of Lading \194\183 #' .. (bolData.bol_number or '?'),
        options = {
            {
                title = 'BOL Number',
                description = '#' .. (bolData.bol_number or 'Unknown'),
                icon = 'fas fa-file-invoice',
                disabled = true,
            },
            {
                title = 'Cargo Type',
                description = bolData.cargo_type or 'Unknown',
                icon = 'fas fa-box',
                disabled = true,
            },
            {
                title = 'Shipper',
                description = bolData.shipper or 'Unknown',
                icon = 'fas fa-building',
                disabled = true,
            },
            {
                title = 'Destination',
                description = bolData.destination or 'Unknown',
                icon = 'fas fa-map-marker-alt',
                disabled = true,
            },
            {
                title = 'Issued',
                description = issuedDisplay,
                icon = 'fas fa-clock',
                disabled = true,
            },
            {
                title = 'Close',
                icon = 'fas fa-times',
                onSelect = function()
                    lib.hideContext()
                end,
            },
        },
    })
    lib.showContext('trucking_bol_detail')
end

-- ─────────────────────────────────────────────
-- INSURANCE CLAIM INTERACTION
-- ─────────────────────────────────────────────
--- At Vapid office (or insurance terminal), player selects a BOL from inventory
--- and triggers a server-side insurance claim.

RegisterNetEvent('trucking:client:openClaimInteraction', function()
    if not IsPlayerLoggedIn() then return end

    -- Get all trucking_bol items from player inventory
    local ok, bolItems = pcall(exports.ox_inventory.Search, exports.ox_inventory, 'slots', 'trucking_bol')

    if not ok or not bolItems or #bolItems == 0 then
        lib.notify({
            title = 'No BOLs Found',
            description = 'You need a physical BOL in your inventory to file a claim',
            type = 'error',
        })
        return
    end

    -- Build selection menu from BOL items
    local options = {
        {
            title = '"Which BOL are you filing on?"',
            description = 'Select a BOL from your inventory to file an insurance claim',
            disabled = true,
            icon = 'fas fa-user-tie',
        },
    }

    for _, slot in ipairs(bolItems) do
        local meta = slot.metadata or {}
        local bolNum = meta.bol_number or 'Unknown'
        local cargo = meta.cargo_type or 'Unknown'
        local dest = meta.destination or 'Unknown'

        table.insert(options, {
            title = 'BOL #' .. bolNum,
            description = cargo .. ' \226\134\146 ' .. dest,
            icon = 'fas fa-file-medical',
            onSelect = function()
                local confirm = lib.alertDialog({
                    header = 'File Insurance Claim?',
                    content = 'Filing claim on BOL **#' .. bolNum .. '**\n\n'
                        .. 'Cargo: ' .. cargo .. '\n'
                        .. 'Destination: ' .. dest .. '\n\n'
                        .. 'The insurance company will review your claim.\n'
                        .. 'If approved, payout will be deposited after a '
                        .. math.floor((Config.ClaimDelaySeconds or 900) / 60)
                        .. '-minute processing period.',
                    centered = true,
                    cancel = true,
                })

                if confirm == 'confirm' then
                    TriggerServerEvent('trucking:server:fileInsuranceClaim', bolNum, slot.slot)
                end
            end,
        })
    end

    table.insert(options, {
        title = 'Cancel',
        icon = 'fas fa-arrow-left',
        onSelect = function()
            lib.hideContext()
        end,
    })

    lib.registerContext({
        id = 'trucking_insurance_claim',
        title = 'Insurance Claim \194\183 Vapid Commercial',
        options = options,
    })
    lib.showContext('trucking_insurance_claim')
end)

--- Server response for claim filing
RegisterNetEvent('trucking:client:claimFiled', function(data)
    if not data then return end

    if data.success then
        lib.notify({
            title = 'Claim Filed',
            description = 'Claim #' .. (data.claimId or '?')
                .. ' filed on BOL #' .. (data.bolNumber or '?')
                .. '\nExpected payout: $' .. (data.expectedPayout or 0)
                .. ' in ' .. math.floor((Config.ClaimDelaySeconds or 900) / 60) .. ' minutes',
            type = 'success',
            duration = 10000,
        })
    else
        lib.notify({
            title = 'Claim Denied',
            description = data.reason or 'Your claim could not be processed',
            type = 'error',
            duration = 8000,
        })
    end
end)
