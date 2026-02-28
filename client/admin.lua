--[[
    client/admin.lua — Admin Panel Client Handlers
    Free Trucking — QBX Framework

    Receives admin panel data from server and forwards to NUI.
]]

-- ─────────────────────────────────────────────
-- SERVER-TO-CLIENT EVENT HANDLERS
-- ─────────────────────────────────────────────

--- Open the admin panel NUI
RegisterNetEvent('trucking:client:openAdminPanel', function(data)
    if not data then return end
    SendNUIMessage({
        action = 'openAdminPanel',
        data = data,
    })
    SetNuiFocus(true, true)
end)

--- Server stats response
RegisterNetEvent('trucking:client:adminServerStats', function(data)
    if not data then return end
    SendNUIMessage({
        action = 'adminServerStats',
        data = data,
    })
end)

--- Active loads response
RegisterNetEvent('trucking:client:adminActiveLoads', function(data)
    if not data then return end
    SendNUIMessage({
        action = 'adminActiveLoads',
        data = data,
    })
end)

--- Active surges response
RegisterNetEvent('trucking:client:adminActiveSurges', function(data)
    if not data then return end
    SendNUIMessage({
        action = 'adminActiveSurges',
        data = data,
    })
end)

--- Board state response
RegisterNetEvent('trucking:client:adminBoardState', function(data)
    if not data then return end
    SendNUIMessage({
        action = 'adminBoardState',
        data = data,
    })
end)

--- Economy settings response
RegisterNetEvent('trucking:client:adminEconomySettings', function(data)
    if not data then return end
    SendNUIMessage({
        action = 'adminEconomySettings',
        data = data,
    })
end)

--- Pending claims response
RegisterNetEvent('trucking:client:adminPendingClaims', function(data)
    if not data then return end
    SendNUIMessage({
        action = 'adminPendingClaims',
        data = data,
    })
end)

--- Player profile lookup response
RegisterNetEvent('trucking:client:adminPlayerProfile', function(data)
    if not data then return end
    SendNUIMessage({
        action = 'adminPlayerProfile',
        data = data,
    })
end)

-- ─────────────────────────────────────────────
-- NUI CALLBACKS
-- ─────────────────────────────────────────────

--- Close admin panel
RegisterNUICallback('trucking:closeAdminPanel', function(_, cb)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closeAdminPanel' })
    cb({ ok = true })
end)

--- Request server stats
RegisterNUICallback('trucking:adminRequestStats', function(_, cb)
    TriggerServerEvent('trucking:server:admin:getServerStats')
    cb({ ok = true })
end)

--- Request active loads
RegisterNUICallback('trucking:adminRequestLoads', function(_, cb)
    TriggerServerEvent('trucking:server:admin:getActiveLoads')
    cb({ ok = true })
end)

--- Request active surges
RegisterNUICallback('trucking:adminRequestSurges', function(_, cb)
    TriggerServerEvent('trucking:server:admin:getActiveSurges')
    cb({ ok = true })
end)

--- Request board state
RegisterNUICallback('trucking:adminRequestBoard', function(_, cb)
    TriggerServerEvent('trucking:server:admin:getBoardState')
    cb({ ok = true })
end)

--- Request economy settings
RegisterNUICallback('trucking:adminRequestEconomy', function(_, cb)
    TriggerServerEvent('trucking:server:admin:getEconomySettings')
    cb({ ok = true })
end)

--- Request pending claims
RegisterNUICallback('trucking:adminRequestClaims', function(_, cb)
    TriggerServerEvent('trucking:server:admin:getPendingClaims')
    cb({ ok = true })
end)

--- Lookup player profile
RegisterNUICallback('trucking:adminLookupPlayer', function(data, cb)
    if not data or not data.citizenid then
        cb({ ok = false, error = 'No citizen ID provided' })
        return
    end
    TriggerServerEvent('trucking:server:admin:playerLookup', data.citizenid)
    cb({ ok = true })
end)
