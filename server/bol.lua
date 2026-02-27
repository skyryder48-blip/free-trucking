--[[
    server/bol.lua
    Bill of Lading (BOL) lifecycle management.

    Responsibilities:
      - GenerateBOLNumber: format "BOL-YYMM-XXXXX" with incrementing number
      - CreateBOL: insert full BOL record with all fields
      - UpdateBOLField: update specific fields on a BOL
      - LogBOLEvent: append audit trail events to truck_bol_events
      - FinalizeBOL: set final status, payout breakdown, timestamps
      - GetBOLAuditTrail: fetch all events for a BOL (admin panel)

    The BOL is the central record of a delivery. It starts as 'active' when a load
    is accepted and is finalized to 'delivered', 'rejected', 'stolen', 'abandoned',
    'expired', or 'partial' when the load completes.

    A physical BOL item (trucking_bol) is added to the player's ox_inventory on
    load acceptance. The item metadata contains the bol_number. The item is required
    for insurance claims and is never auto-removed from inventory.
]]

-- ============================================================================
-- BOL NUMBER GENERATION
-- Format: BOL-YYMM-XXXXX
-- The XXXXX portion is an incrementing counter that resets each month.
-- We track the current month's counter in a local variable and seed it
-- from the database on resource start.
-- ============================================================================

local bolCounter = 0
local bolCounterMonth = '' -- 'YYMM' string for the current month

--- Initialize the BOL counter from the database.
--- Called on resource start to pick up where we left off.
function InitBOLCounter()
    local currentMonth = os.date('%y%m')
    bolCounterMonth = currentMonth

    -- Find the highest BOL number for this month
    local result = MySQL.single.await([[
        SELECT bol_number FROM truck_bols
        WHERE bol_number LIKE ?
        ORDER BY id DESC LIMIT 1
    ]], { 'BOL-' .. currentMonth .. '-%' })

    if result and result.bol_number then
        -- Extract the numeric portion: BOL-YYMM-XXXXX -> XXXXX
        local numPart = result.bol_number:match('BOL%-%d%d%d%d%-(%d+)')
        if numPart then
            bolCounter = tonumber(numPart) or 0
        end
    end

    -- Also check truck_loads for BOL numbers that haven't been accepted yet
    local loadResult = MySQL.single.await([[
        SELECT bol_number FROM truck_loads
        WHERE bol_number LIKE ?
        ORDER BY id DESC LIMIT 1
    ]], { 'BOL-' .. currentMonth .. '-%' })

    if loadResult and loadResult.bol_number then
        local numPart = loadResult.bol_number:match('BOL%-%d%d%d%d%-(%d+)')
        if numPart then
            local loadCounter = tonumber(numPart) or 0
            if loadCounter > bolCounter then
                bolCounter = loadCounter
            end
        end
    end

    print(('[trucking] BOL counter initialized: month=%s, counter=%d'):format(currentMonth, bolCounter))
end

--- Generate the next BOL number in sequence.
--- Format: BOL-YYMM-XXXXX (e.g., BOL-2601-00042)
---@return string bolNumber
function GenerateBOLNumber()
    local currentMonth = os.date('%y%m')

    -- Reset counter if we rolled into a new month
    if currentMonth ~= bolCounterMonth then
        bolCounterMonth = currentMonth
        bolCounter = 0
    end

    bolCounter = bolCounter + 1
    return ('BOL-%s-%05d'):format(currentMonth, bolCounter)
end

-- Initialize counter when this file loads (runs after resource start)
CreateThread(function()
    -- Wait for MySQL to be ready
    Wait(1000)
    InitBOLCounter()
end)

-- ============================================================================
-- CREATE BOL
-- Full BOL record creation. Called by missions.lua during load acceptance.
-- ============================================================================

--- Create a complete BOL record from load data, driver data, and company data.
--- Returns the BOL id and BOL number.
---@param loadData table  The load row from truck_loads
---@param driverData table  { citizenid, driver_name, driver_id }
---@param companyData table|nil  { company_id, company_name } or nil
---@return number bolId
---@return string bolNumber
function CreateBOL(loadData, driverData, companyData)
    local cargo = CargoTypes and CargoTypes[loadData.cargo_type] or {}
    local bolNumber = loadData.bol_number or GenerateBOLNumber()
    local now = os.time()

    -- Determine license class from load requirements
    local licenseClass = nil
    if loadData.required_license and loadData.required_license ~= 'none' then
        licenseClass = loadData.required_license
    end

    -- Check license match
    local licenseMismatch = false
    if licenseClass then
        local license = DB.GetLicense(driverData.citizenid, licenseClass)
        if not license or license.status ~= 'active' then
            licenseMismatch = true
        end
    end

    -- Build the BOL data table
    local bolData = {
        bol_number = bolNumber,
        load_id = loadData.id,
        citizenid = driverData.citizenid,
        driver_name = driverData.driver_name,
        company_id = companyData and companyData.company_id or nil,
        company_name = companyData and companyData.company_name or nil,
        shipper_id = loadData.shipper_id,
        shipper_name = loadData.shipper_name,
        origin_label = loadData.origin_label,
        destination_label = loadData.destination_label,
        distance_miles = loadData.distance_miles,
        cargo_type = loadData.cargo_type,
        cargo_description = cargo.description or loadData.cargo_type:gsub('_', ' '),
        weight_lbs = loadData.weight_lbs,
        tier = loadData.tier,
        hazmat_class = loadData.hazmat_class,
        placard_class = loadData.hazmat_class and ('Class ' .. loadData.hazmat_class) or nil,
        license_class = licenseClass,
        license_matched = not licenseMismatch,
        seal_number = nil, -- Applied at departure
        seal_status = 'not_applied',
        temp_required_min = loadData.temp_min_f,
        temp_required_max = loadData.temp_max_f,
        bol_status = 'active',
        is_leon = loadData.is_leon_load or false,
        issued_at = now,
    }

    local bolId = DB.InsertBOL(bolData)
    return bolId, bolNumber
end

-- ============================================================================
-- UPDATE BOL FIELD
-- Update a specific field (or fields) on a BOL record.
-- Thin wrapper for targeted updates during the load lifecycle.
-- ============================================================================

--- Update one or more fields on a BOL record.
---@param bolId number  The BOL primary key
---@param field string  The column name to update
---@param value any     The new value
---@return number affectedRows
function UpdateBOLField(bolId, field, value)
    -- Validate the field is an allowed column to prevent SQL injection
    local allowedFields = {
        'bol_status', 'seal_number', 'seal_status', 'temp_compliance',
        'weigh_station_stamp', 'manifest_verified', 'pre_trip_completed',
        'welfare_final_rating', 'final_payout', 'payout_breakdown',
        'deposit_returned', 'item_in_inventory', 'item_disposed_at',
        'departed_at', 'delivered_at', 'citizenid', 'driver_name',
        'license_matched',
    }

    local isAllowed = false
    for _, f in ipairs(allowedFields) do
        if f == field then
            isAllowed = true
            break
        end
    end

    if not isAllowed then
        print(('[trucking] WARNING: Attempted to update disallowed BOL field: %s'):format(field))
        return 0
    end

    -- Handle JSON encoding for payout_breakdown
    if field == 'payout_breakdown' and type(value) == 'table' then
        value = json.encode(value)
    end

    return MySQL.update.await(
        'UPDATE truck_bols SET ' .. field .. ' = ? WHERE id = ?',
        { value, bolId }
    )
end

-- ============================================================================
-- LOG BOL EVENT
-- Append an event to the truck_bol_events audit trail.
-- This is the immutable record of everything that happened during a delivery.
-- ============================================================================

--- Log a BOL lifecycle event to the audit trail.
---@param bolId number  The BOL primary key
---@param bolNumber string  The BOL number string (e.g., "BOL-2601-00042")
---@param citizenid string  The driver's citizenid
---@param eventType string  One of the ENUM values in truck_bol_events.event_type
---@param eventData table|nil  Optional JSON-serializable context data
---@param coords vector3|table|nil  Optional coordinates where the event occurred
---@return number insertId
function LogBOLEvent(bolId, bolNumber, citizenid, eventType, eventData, coords)
    -- Normalize coords to a plain table for JSON encoding
    local coordsTable = nil
    if coords then
        if type(coords) == 'vector3' then
            coordsTable = { x = coords.x, y = coords.y, z = coords.z }
        elseif type(coords) == 'table' then
            coordsTable = coords
        end
    end

    return DB.InsertBOLEvent({
        bol_id = bolId,
        bol_number = bolNumber,
        citizenid = citizenid,
        event_type = eventType,
        event_data = eventData,
        coords = coordsTable,
        occurred_at = os.time(),
    })
end

-- ============================================================================
-- FINALIZE BOL
-- Set the final status, payout breakdown, and timestamps on a BOL.
-- Called at delivery, rejection, abandonment, theft, or expiration.
-- ============================================================================

--- Finalize a BOL with its terminal status and payout data.
---@param bolId number  The BOL primary key
---@param status string  One of: 'delivered', 'rejected', 'stolen', 'abandoned', 'expired', 'partial'
---@param payoutData table|nil  { final_payout, breakdown, delivered_at }
function FinalizeBOL(bolId, status, payoutData)
    local updates = {
        bol_status = status,
    }

    if payoutData then
        if payoutData.final_payout then
            updates.final_payout = payoutData.final_payout
        end
        if payoutData.breakdown then
            updates.payout_breakdown = payoutData.breakdown
        end
        if payoutData.delivered_at then
            updates.delivered_at = payoutData.delivered_at
        end
    end

    -- For delivered status, mark deposit as returned
    if status == 'delivered' then
        updates.deposit_returned = true
    end

    -- For non-delivered terminal states, deposit is forfeited (handled elsewhere)
    -- but we record the fact on the BOL for reference
    if status == 'stolen' or status == 'abandoned' or status == 'expired' then
        updates.deposit_returned = false
    end

    DB.UpdateBOL(bolId, updates)

    -- Log the finalization event
    local bol = DB.GetBOL(bolId)
    if bol then
        local eventType = 'load_delivered'
        if status == 'rejected' then eventType = 'load_rejected'
        elseif status == 'stolen' then eventType = 'load_stolen'
        elseif status == 'abandoned' then eventType = 'load_abandoned'
        elseif status == 'expired' then eventType = 'window_expired'
        end

        LogBOLEvent(bolId, bol.bol_number, bol.citizenid, eventType, {
            final_status = status,
            final_payout = payoutData and payoutData.final_payout or 0,
        })
    end
end

-- ============================================================================
-- GET BOL AUDIT TRAIL
-- Fetch all events for a BOL, ordered chronologically.
-- Used by the admin panel for dispute resolution and audit.
-- ============================================================================

--- Fetch the complete audit trail for a BOL.
---@param bolId number  The BOL primary key
---@return table[] events  Array of truck_bol_events rows
function GetBOLAuditTrail(bolId)
    return MySQL.query.await(
        'SELECT * FROM truck_bol_events WHERE bol_id = ? ORDER BY occurred_at ASC, id ASC',
        { bolId }
    )
end

--- Fetch the audit trail for a BOL by its number string.
---@param bolNumber string
---@return table[] events
function GetBOLAuditTrailByNumber(bolNumber)
    return MySQL.query.await(
        'SELECT * FROM truck_bol_events WHERE bol_number = ? ORDER BY occurred_at ASC, id ASC',
        { bolNumber }
    )
end

-- ============================================================================
-- BOL ITEM DISPOSAL
-- When a player manually disposes of the physical BOL item from inventory,
-- we record the disposal on the BOL record.
-- ============================================================================

--- Mark a BOL's physical item as disposed (no longer in inventory).
---@param bolId number
---@return number affectedRows
function DisposeBOLItem(bolId)
    return DB.UpdateBOL(bolId, {
        item_in_inventory = false,
        item_disposed_at = os.time(),
    })
end

-- ============================================================================
-- BOL LOOKUP HELPERS (for admin panel and external integrations)
-- ============================================================================

--- Fetch a BOL by its number string.
---@param bolNumber string
---@return table|nil
function GetBOLByNumber(bolNumber)
    return DB.GetBOLByNumber(bolNumber)
end

--- Fetch recent BOLs for a player.
---@param citizenid string
---@param limit number|nil  Defaults to 50
---@return table[]
function GetPlayerBOLHistory(citizenid, limit)
    return DB.GetBOLsByPlayer(citizenid, limit)
end

--- Fetch a BOL with its full audit trail combined.
--- Returns the BOL record with an added 'events' field.
---@param bolId number
---@return table|nil bolWithEvents
function GetBOLWithAuditTrail(bolId)
    local bol = DB.GetBOL(bolId)
    if not bol then return nil end

    bol.events = GetBOLAuditTrail(bolId)

    -- Parse JSON fields for convenience
    if bol.payout_breakdown and type(bol.payout_breakdown) == 'string' then
        bol.payout_breakdown = json.decode(bol.payout_breakdown)
    end

    return bol
end

-- ============================================================================
-- TEMPERATURE COMPLIANCE DETERMINATION
-- Called during excursion tracking to update the BOL's temp_compliance field.
-- ============================================================================

--- Determine and update the temperature compliance status on a BOL.
--- Called when an excursion ends or when the load is being finalized.
---@param bolId number
---@param totalExcursionMinutes number  Total minutes of temperature excursion
function UpdateTempCompliance(bolId, totalExcursionMinutes)
    local compliance = 'clean'

    local minorThreshold = Config.ExcursionMinorMins or 5
    local significantThreshold = Config.ExcursionSignificantMins or 15

    if totalExcursionMinutes >= significantThreshold then
        compliance = 'significant_excursion'
    elseif totalExcursionMinutes >= minorThreshold then
        compliance = 'minor_excursion'
    end

    DB.UpdateBOL(bolId, { temp_compliance = compliance })
end

-- ============================================================================
-- WELFARE RATING FINALIZATION
-- Called at delivery to set the final welfare rating on the BOL.
-- ============================================================================

--- Set the final livestock welfare rating on the BOL.
---@param bolId number
---@param welfareRating number  1-5
function FinalizeWelfareRating(bolId, welfareRating)
    DB.UpdateBOL(bolId, { welfare_final_rating = welfareRating })
end
