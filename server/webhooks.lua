--[[
    server/webhooks.lua — Discord Webhook Dispatch
    Handles all outbound Discord webhook notifications with rate limiting,
    retry logic, and database logging.
]]

--- Rate limiter state: tracks send timestamps per channel
---@type table<string, number[]>
local RateLimitBuckets = {}

--- Maximum webhooks per second per channel
local RATE_LIMIT_MAX = 5
local RATE_LIMIT_WINDOW = 1000 -- 1 second in ms

--- Maximum retry attempts on failure
local MAX_RETRY_ATTEMPTS = 3

--- Retry delay base in milliseconds (doubles each attempt)
local RETRY_BASE_DELAY = 1000

--- Valid webhook channels
local VALID_CHANNELS = {
    insurance = true,
    leon      = true,
    military  = true,
    claims    = true,
    surge     = true,
    admin     = true,
}

--- Check if a channel is rate-limited
---@param channel string The webhook channel name
---@return boolean allowed True if the send is allowed
local function CheckRateLimit(channel)
    local now = GetGameTimer()
    local bucket = RateLimitBuckets[channel]

    if not bucket then
        RateLimitBuckets[channel] = { now }
        return true
    end

    -- Prune timestamps older than the rate window
    local pruned = {}
    for i = 1, #bucket do
        if (now - bucket[i]) < RATE_LIMIT_WINDOW then
            pruned[#pruned + 1] = bucket[i]
        end
    end

    if #pruned >= RATE_LIMIT_MAX then
        RateLimitBuckets[channel] = pruned
        return false
    end

    pruned[#pruned + 1] = now
    RateLimitBuckets[channel] = pruned
    return true
end

--- Build a consistently formatted Discord embed
---@param title string Embed title
---@param fields table[] Array of { name, value, inline? } field objects
---@param color number|nil Hex color integer (defaults to Bears navy 0x0B1F45)
---@param description string|nil Optional description text
---@return table embed The formatted embed table
function BuildEmbed(title, fields, color, description)
    local embed = {
        title       = title or 'Trucking System',
        color       = color or 0x0B1F45,
        timestamp   = os.date('!%Y-%m-%dT%H:%M:%SZ', GetServerTime()),
        fields      = {},
        footer      = {
            text = 'Bears Trucking System',
        },
    }

    if description then
        embed.description = description
    end

    if fields and type(fields) == 'table' then
        for i = 1, #fields do
            local field = fields[i]
            embed.fields[#embed.fields + 1] = {
                name    = tostring(field.name or 'Field'),
                value   = tostring(field.value or '—'),
                inline  = field.inline or false,
            }
        end
    end

    return embed
end

--- Log a webhook attempt to the database
---@param channel string Webhook channel name
---@param eventType string The event type being logged
---@param citizenid string|nil Associated citizenid
---@param bolNumber string|nil Associated BOL number
---@param payload table The embed payload
---@param delivered boolean Whether delivery succeeded
---@param attempts number Number of delivery attempts made
local function LogWebhookToDatabase(channel, eventType, citizenid, bolNumber, payload, delivered, attempts)
    MySQL.insert([[
        INSERT INTO truck_webhook_log
        (webhook_channel, event_type, citizenid, bol_number, payload,
         delivered, delivery_attempts, delivered_at, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        channel,
        eventType,
        citizenid,
        bolNumber,
        json.encode(payload),
        delivered,
        attempts,
        delivered and GetServerTime() or nil,
        GetServerTime(),
    })
end

--- Perform the actual HTTP POST to Discord with retry logic
---@param url string The webhook URL
---@param embed table The embed payload
---@param channel string The channel name (for logging)
---@param eventType string The event type (for logging)
---@param citizenid string|nil Associated citizenid
---@param bolNumber string|nil Associated BOL number
local function PerformWebhookSend(url, embed, channel, eventType, citizenid, bolNumber)
    local payload = {
        embeds = { embed },
    }
    local payloadJson = json.encode(payload)
    local attempts = 0
    local delivered = false

    CreateThread(function()
        while attempts < MAX_RETRY_ATTEMPTS and not delivered do
            attempts = attempts + 1

            PerformHttpRequest(url, function(statusCode)
                if statusCode and statusCode >= 200 and statusCode < 300 then
                    delivered = true
                elseif statusCode == 429 then
                    -- Discord rate limited — wait longer before retry
                    Wait(RETRY_BASE_DELAY * attempts * 2)
                end
            end, 'POST', payloadJson, {
                ['Content-Type'] = 'application/json',
            })

            -- Wait for the callback to fire
            Wait(RETRY_BASE_DELAY * attempts)
        end

        LogWebhookToDatabase(channel, eventType, citizenid, bolNumber, embed, delivered, attempts)

        if not delivered then
            print(('[Trucking Webhooks] Failed to deliver webhook to channel "%s" after %d attempts (event: %s)')
                :format(channel, attempts, eventType))
        end
    end)
end

--- Send a webhook embed to a configured Discord channel
---@param channel string The channel name (insurance, leon, military, claims, surge, admin)
---@param embed table The Discord embed table
---@param eventType string|nil Optional event type label for logging (defaults to embed.title)
---@param citizenid string|nil Optional citizenid for log association
---@param bolNumber string|nil Optional BOL number for log association
function SendWebhook(channel, embed, eventType, citizenid, bolNumber)
    if not channel or not VALID_CHANNELS[channel] then
        print(('[Trucking Webhooks] Invalid webhook channel: %s'):format(tostring(channel)))
        return
    end

    if not embed then
        print('[Trucking Webhooks] SendWebhook called with nil embed')
        return
    end

    -- Get the webhook URL from config
    local url = Config.Webhooks and Config.Webhooks[channel]
    if not url or url == '' then
        -- Channel not configured — log to database only, mark as undelivered
        LogWebhookToDatabase(
            channel,
            eventType or embed.title or 'unknown',
            citizenid,
            bolNumber,
            embed,
            false,
            0
        )
        return
    end

    -- Enforce rate limit
    if not CheckRateLimit(channel) then
        -- Queue for delayed send
        CreateThread(function()
            Wait(RATE_LIMIT_WINDOW)
            SendWebhook(channel, embed, eventType, citizenid, bolNumber)
        end)
        return
    end

    PerformWebhookSend(
        url,
        embed,
        channel,
        eventType or embed.title or 'unknown',
        citizenid,
        bolNumber
    )
end

--- Log an admin action to the admin webhook channel with Bears orange color
---@param src number The admin's server ID
---@param actionType string The type of admin action performed
---@param data table|nil Additional data about the action
function LogAdminAction(src, actionType, data)
    if not src then
        print('[Trucking Webhooks] LogAdminAction called with nil source')
        return
    end

    local adminName = GetPlayerName(src) or 'Unknown'
    local player = exports.qbx_core:GetPlayer(src)
    local adminCitizenId = player and player.PlayerData.citizenid or 'unknown'

    local fields = {
        { name = 'Admin',       value = adminName,      inline = true },
        { name = 'Citizen ID',  value = adminCitizenId, inline = true },
        { name = 'Action',      value = actionType,     inline = true },
    }

    if data then
        -- Flatten data into readable fields
        if type(data) == 'table' then
            for key, value in pairs(data) do
                local displayValue = type(value) == 'table' and json.encode(value) or tostring(value)
                -- Truncate long values for Discord field limits
                if #displayValue > 1024 then
                    displayValue = displayValue:sub(1, 1021) .. '...'
                end
                fields[#fields + 1] = {
                    name    = tostring(key),
                    value   = displayValue,
                    inline  = false,
                }
            end
        else
            fields[#fields + 1] = {
                name    = 'Details',
                value   = tostring(data),
                inline  = false,
            }
        end
    end

    local embed = BuildEmbed(
        'Admin Action: ' .. actionType,
        fields,
        0xC83803 -- Bears orange
    )

    SendWebhook('admin', embed, 'admin_' .. actionType, adminCitizenId)
end

--- Send an insurance-related webhook
---@param eventType string The insurance event type
---@param data table Event data with citizenid, bol_number, and relevant fields
function SendInsuranceWebhook(eventType, data)
    local fields = {
        { name = 'Event',       value = eventType,                  inline = true },
        { name = 'Citizen ID',  value = data.citizenid or '—',      inline = true },
        { name = 'BOL',         value = data.bol_number or '—',     inline = true },
    }

    if data.claim_amount then
        fields[#fields + 1] = { name = 'Claim Amount', value = '$' .. tostring(data.claim_amount), inline = true }
    end
    if data.policy_type then
        fields[#fields + 1] = { name = 'Policy Type', value = data.policy_type, inline = true }
    end
    if data.status then
        fields[#fields + 1] = { name = 'Status', value = data.status, inline = true }
    end

    local embed = BuildEmbed(
        'Insurance: ' .. eventType,
        fields,
        0x2D7A3E -- success green for approvals, override for denials
    )

    if data.status == 'denied' then
        embed.color = 0xC83803 -- Bears orange for denied
    end

    SendWebhook('insurance', embed, eventType, data.citizenid, data.bol_number)
end

--- Send a Leon-related webhook
---@param eventType string The Leon event type
---@param data table Event data
function SendLeonWebhook(eventType, data)
    local fields = {
        { name = 'Event',       value = eventType,              inline = true },
        { name = 'Citizen ID',  value = data.citizenid or '—',  inline = true },
    }

    if data.supplier_id then
        fields[#fields + 1] = { name = 'Supplier', value = data.supplier_id, inline = true }
    end
    if data.risk_tier then
        fields[#fields + 1] = { name = 'Risk Tier', value = data.risk_tier, inline = true }
    end
    if data.payout then
        fields[#fields + 1] = { name = 'Payout', value = '$' .. tostring(data.payout), inline = true }
    end
    if data.fee then
        fields[#fields + 1] = { name = 'Fee Paid', value = '$' .. tostring(data.fee), inline = true }
    end

    local embed = BuildEmbed(
        'Leon: ' .. eventType,
        fields,
        0x8A2702 -- orange-dim for criminal activity
    )

    SendWebhook('leon', embed, eventType, data.citizenid)
end

--- Send a military-related webhook
---@param eventType string The military event type
---@param data table Event data
function SendMilitaryWebhook(eventType, data)
    local fields = {
        { name = 'Event',           value = eventType,                      inline = true },
        { name = 'Citizen ID',      value = data.citizenid or '—',          inline = true },
        { name = 'Classification',  value = data.classification or '—',     inline = true },
    }

    if data.location then
        fields[#fields + 1] = {
            name = 'Location',
            value = type(data.location) == 'table'
                and ('%.1f, %.1f, %.1f'):format(data.location.x or 0, data.location.y or 0, data.location.z or 0)
                or tostring(data.location),
            inline = true,
        }
    end
    if data.consequence then
        fields[#fields + 1] = { name = 'Consequence', value = data.consequence, inline = false }
    end

    local embed = BuildEmbed(
        'Military: ' .. eventType,
        fields,
        0x051229 -- navy-dark for military
    )

    SendWebhook('military', embed, eventType, data.citizenid)
end

--- Send a surge-related webhook
---@param eventType string The surge event type
---@param data table Event data
function SendSurgeWebhook(eventType, data)
    local fields = {
        { name = 'Event',       value = eventType,                  inline = true },
        { name = 'Region',      value = data.region or '—',         inline = true },
        { name = 'Percentage',  value = (data.percentage or 0) .. '%', inline = true },
    }

    if data.cargo_type then
        fields[#fields + 1] = { name = 'Cargo Filter', value = data.cargo_type, inline = true }
    end
    if data.duration_minutes then
        fields[#fields + 1] = { name = 'Duration', value = data.duration_minutes .. ' min', inline = true }
    end

    local embed = BuildEmbed(
        'Surge: ' .. eventType,
        fields,
        0xC87B03 -- warning color
    )

    SendWebhook('surge', embed, eventType)
end
