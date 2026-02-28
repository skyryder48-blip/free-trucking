--[[
    server/database.lua
    Pure data-access layer for the trucking script.
    Every function is a thin wrapper around oxmysql.
    NO business logic lives here -- only SQL execution and result passthrough.

    Query conventions:
      - MySQL.single.await  -> fetch exactly one row (or nil)
      - MySQL.query.await   -> fetch multiple rows (returns table, may be empty)
      - MySQL.insert.await  -> INSERT, returns last insert id
      - MySQL.update.await  -> UPDATE/DELETE, returns affected row count
      - NEVER use MySQL.scalar.await for row fetches
]]

DB = {}

-- ============================================================================
-- DRIVER CRUD
-- ============================================================================

--- Create a new driver record on first interaction
---@param citizenid string
---@param playerName string
---@return number insertId
function DB.CreateDriver(citizenid, playerName)
    local now = GetServerTime()
    return MySQL.insert.await([[
        INSERT INTO truck_drivers (citizenid, player_name, first_seen, last_seen)
        VALUES (?, ?, ?, ?)
    ]], { citizenid, playerName, now, now })
end

--- Fetch a single driver record by citizenid
---@param citizenid string
---@return table|nil
function DB.GetDriver(citizenid)
    return MySQL.single.await(
        'SELECT * FROM truck_drivers WHERE citizenid = ?',
        { citizenid }
    )
end

--- Fetch a driver record by its primary key
---@param driverId number
---@return table|nil
function DB.GetDriverById(driverId)
    return MySQL.single.await(
        'SELECT * FROM truck_drivers WHERE id = ?',
        { driverId }
    )
end

--- Generic field update on the driver row
---@param citizenid string
---@param fields table key-value pairs to SET
---@return number affectedRows
function DB.UpdateDriver(citizenid, fields)
    local setClauses = {}
    local params = {}
    for k, v in pairs(fields) do
        setClauses[#setClauses + 1] = k .. ' = ?'
        params[#params + 1] = v
    end
    params[#params + 1] = citizenid
    return MySQL.update.await(
        'UPDATE truck_drivers SET ' .. table.concat(setClauses, ', ') .. ' WHERE citizenid = ?',
        params
    )
end

--- Increment counters after a load completes or fails
---@param citizenid string
---@param statsTable table  e.g. { total_loads_completed = 1, total_distance_driven = 14 }
---@return number affectedRows
function DB.UpdateDriverStats(citizenid, statsTable)
    local setClauses = {}
    local params = {}
    for k, v in pairs(statsTable) do
        setClauses[#setClauses + 1] = k .. ' = ' .. k .. ' + ?'
        params[#params + 1] = v
    end
    params[#params + 1] = citizenid
    return MySQL.update.await(
        'UPDATE truck_drivers SET ' .. table.concat(setClauses, ', ') .. ' WHERE citizenid = ?',
        params
    )
end

-- ============================================================================
-- LICENSE CRUD
-- ============================================================================

--- Issue a new license
---@param data table  { driver_id, citizenid, license_type, fee_paid, ... }
---@return number insertId
function DB.CreateLicense(data)
    local now = GetServerTime()
    return MySQL.insert.await([[
        INSERT INTO truck_licenses
            (driver_id, citizenid, license_type, fee_paid, issued_at, expires_at)
        VALUES (?, ?, ?, ?, ?, ?)
    ]], {
        data.driver_id,
        data.citizenid,
        data.license_type,
        data.fee_paid or 0,
        now,
        data.expires_at, -- nil for permanent licenses
    })
end

--- Fetch a specific license for a driver
---@param citizenid string
---@param licenseType string
---@return table|nil
function DB.GetLicense(citizenid, licenseType)
    return MySQL.single.await([[
        SELECT * FROM truck_licenses
        WHERE citizenid = ? AND license_type = ?
        ORDER BY issued_at DESC LIMIT 1
    ]], { citizenid, licenseType })
end

--- Fetch all licenses held by a driver
---@param citizenid string
---@return table[]
function DB.GetAllLicenses(citizenid)
    return MySQL.query.await(
        'SELECT * FROM truck_licenses WHERE citizenid = ? ORDER BY issued_at DESC',
        { citizenid }
    )
end

--- Update license status (active, suspended, revoked)
---@param licenseId number
---@param status string
---@param lockedUntil number|nil  unix timestamp for lockout period
---@return number affectedRows
function DB.UpdateLicenseStatus(licenseId, status, lockedUntil)
    return MySQL.update.await(
        'UPDATE truck_licenses SET status = ?, locked_until = ? WHERE id = ?',
        { status, lockedUntil, licenseId }
    )
end

-- ============================================================================
-- CERTIFICATION CRUD
-- ============================================================================

--- Issue a new certification
---@param data table  { driver_id, citizenid, cert_type, background_fee_paid, expires_at }
---@return number insertId
function DB.CreateCert(data)
    local now = GetServerTime()
    return MySQL.insert.await([[
        INSERT INTO truck_certifications
            (driver_id, citizenid, cert_type, background_fee_paid, issued_at, expires_at)
        VALUES (?, ?, ?, ?, ?, ?)
    ]], {
        data.driver_id,
        data.citizenid,
        data.cert_type,
        data.background_fee_paid or 0,
        now,
        data.expires_at,
    })
end

--- Fetch a specific certification for a driver
---@param citizenid string
---@param certType string
---@return table|nil
function DB.GetCert(citizenid, certType)
    return MySQL.single.await([[
        SELECT * FROM truck_certifications
        WHERE citizenid = ? AND cert_type = ?
        ORDER BY issued_at DESC LIMIT 1
    ]], { citizenid, certType })
end

--- Fetch all certifications held by a driver
---@param citizenid string
---@return table[]
function DB.GetAllCerts(citizenid)
    return MySQL.query.await(
        'SELECT * FROM truck_certifications WHERE citizenid = ? ORDER BY issued_at DESC',
        { citizenid }
    )
end

--- Update certification status
---@param certId number
---@param status string  'active', 'suspended', 'revoked', 'expired'
---@param revokedReason string|nil
---@return number affectedRows
function DB.UpdateCertStatus(certId, status, revokedReason)
    local now = GetServerTime()
    return MySQL.update.await([[
        UPDATE truck_certifications
        SET status = ?,
            revoked_reason = ?,
            revoked_at = CASE WHEN ? IN ('revoked','suspended') THEN ? ELSE revoked_at END
        WHERE id = ?
    ]], { status, revokedReason, status, now, certId })
end

-- ============================================================================
-- LOAD QUERIES
-- ============================================================================

--- Insert a newly generated board load
---@param data table  Full load fields
---@return number insertId
function DB.InsertLoad(data)
    return MySQL.insert.await([[
        INSERT INTO truck_loads
            (bol_number, tier, cargo_type, cargo_subtype,
             shipper_id, shipper_name, origin_region, origin_label, origin_coords,
             destination_label, destination_coords, distance_miles, weight_lbs,
             weight_multiplier, temp_min_f, temp_max_f,
             hazmat_class, hazmat_un_number, requires_seal,
             min_vehicle_class, required_vehicle_type,
             required_license, required_endorsement, required_certification,
             base_rate_per_mile, base_payout_rental, base_payout_owner_op,
             deposit_amount, surge_active, surge_percentage, surge_expires,
             is_leon_load, leon_fee, leon_risk_tier, leon_supplier_id,
             is_multi_stop, stop_count, posted_at, expires_at, board_region)
        VALUES (?,?,?,?, ?,?,?,?,?, ?,?,?,?, ?,?,?, ?,?,?, ?,?, ?,?,?, ?,?,?, ?,?,?,?, ?,?,?,?, ?,?, ?,?,?)
    ]], {
        data.bol_number, data.tier, data.cargo_type, data.cargo_subtype,
        data.shipper_id, data.shipper_name, data.origin_region, data.origin_label,
        json.encode(data.origin_coords),
        data.destination_label, json.encode(data.destination_coords),
        data.distance_miles, data.weight_lbs,
        data.weight_multiplier, data.temp_min_f, data.temp_max_f,
        data.hazmat_class, data.hazmat_un_number, data.requires_seal,
        data.min_vehicle_class, data.required_vehicle_type,
        data.required_license, data.required_endorsement, data.required_certification,
        data.base_rate_per_mile, data.base_payout_rental, data.base_payout_owner_op,
        data.deposit_amount, data.surge_active or false, data.surge_percentage or 0,
        data.surge_expires,
        data.is_leon_load or false, data.leon_fee, data.leon_risk_tier, data.leon_supplier_id,
        data.is_multi_stop or false, data.stop_count or 1,
        data.posted_at, data.expires_at, data.board_region,
    })
end

--- Fetch a single load by id
---@param loadId number
---@return table|nil
function DB.GetLoad(loadId)
    return MySQL.single.await(
        'SELECT * FROM truck_loads WHERE id = ?',
        { loadId }
    )
end

--- Fetch all loads for a given region (any status)
---@param region string
---@return table[]
function DB.GetLoadsByRegion(region)
    return MySQL.query.await(
        'SELECT * FROM truck_loads WHERE board_region = ? ORDER BY tier ASC, posted_at DESC',
        { region }
    )
end

--- Update the board_status of a load
---@param loadId number
---@param status string
---@return number affectedRows
function DB.UpdateLoadStatus(loadId, status)
    return MySQL.update.await(
        'UPDATE truck_loads SET board_status = ? WHERE id = ?',
        { status, loadId }
    )
end

--- Fetch all available (unclaimed) loads for a region
---@param region string
---@return table[]
function DB.GetAvailableLoads(region)
    return MySQL.query.await([[
        SELECT * FROM truck_loads
        WHERE board_region = ?
          AND board_status = 'available'
          AND expires_at > ?
        ORDER BY tier ASC, posted_at DESC
    ]], { region, GetServerTime() })
end

--- Reserve a load for a player (3-minute hold)
---@param loadId number
---@param citizenid string
---@param reserveUntil number  unix timestamp
---@return number affectedRows  (0 = someone else already reserved it)
function DB.ReserveLoad(loadId, citizenid, reserveUntil)
    return MySQL.update.await([[
        UPDATE truck_loads
        SET board_status = 'reserved', reserved_by = ?, reserved_until = ?
        WHERE id = ? AND board_status = 'available'
    ]], { citizenid, reserveUntil, loadId })
end

--- Release a reservation, returning the load to available
---@param loadId number
---@param citizenid string
---@return number affectedRows
function DB.UnreserveLoad(loadId, citizenid)
    return MySQL.update.await([[
        UPDATE truck_loads
        SET board_status = 'available', reserved_by = NULL, reserved_until = NULL
        WHERE id = ? AND reserved_by = ?
    ]], { loadId, citizenid })
end

-- ============================================================================
-- ACTIVE LOAD
-- ============================================================================

--- Create an active load row when a player accepts a load
---@param data table
---@return number insertId
function DB.InsertActiveLoad(data)
    return MySQL.insert.await([[
        INSERT INTO truck_active_loads
            (load_id, bol_id, citizenid, driver_id,
             vehicle_plate, vehicle_model, is_rental,
             status, cargo_integrity, cargo_secured,
             seal_status, temp_monitoring_active,
             accepted_at, window_expires_at,
             deposit_posted, estimated_payout,
             company_id, convoy_id)
        VALUES (?,?,?,?, ?,?,?, ?,?,?, ?,?, ?,?, ?,?, ?,?)
    ]], {
        data.load_id, data.bol_id, data.citizenid, data.driver_id,
        data.vehicle_plate, data.vehicle_model, data.is_rental or false,
        data.status or 'at_origin', data.cargo_integrity or 100, data.cargo_secured or false,
        data.seal_status or 'not_applied', data.temp_monitoring_active or false,
        data.accepted_at, data.window_expires_at,
        data.deposit_posted or 0, data.estimated_payout or 0,
        data.company_id, data.convoy_id,
    })
end

--- Fetch the active load for a given citizenid
---@param citizenid string
---@return table|nil
function DB.GetActiveLoad(citizenid)
    return MySQL.single.await(
        'SELECT * FROM truck_active_loads WHERE citizenid = ?',
        { citizenid }
    )
end

--- Fetch an active load by its bol_id
---@param bolId number
---@return table|nil
function DB.GetActiveLoadByBol(bolId)
    return MySQL.single.await(
        'SELECT * FROM truck_active_loads WHERE bol_id = ?',
        { bolId }
    )
end

--- Update fields on an active load row
---@param activeLoadId number
---@param fields table key-value pairs to SET
---@return number affectedRows
function DB.UpdateActiveLoad(activeLoadId, fields)
    local setClauses = {}
    local params = {}
    for k, v in pairs(fields) do
        setClauses[#setClauses + 1] = k .. ' = ?'
        params[#params + 1] = v
    end
    params[#params + 1] = activeLoadId
    return MySQL.update.await(
        'UPDATE truck_active_loads SET ' .. table.concat(setClauses, ', ') .. ' WHERE id = ?',
        params
    )
end

--- Delete an active load row (on delivery or cleanup)
---@param activeLoadId number
---@return number affectedRows
function DB.DeleteActiveLoad(activeLoadId)
    return MySQL.update.await(
        'DELETE FROM truck_active_loads WHERE id = ?',
        { activeLoadId }
    )
end

--- Fetch all active loads (for resource-start recovery and admin panel)
---@return table[]
function DB.GetAllActiveLoads()
    return MySQL.query.await(
        'SELECT * FROM truck_active_loads ORDER BY accepted_at DESC',
        {}
    )
end

-- ============================================================================
-- BOL
-- ============================================================================

--- Insert a new BOL record
---@param data table
---@return number insertId
function DB.InsertBOL(data)
    return MySQL.insert.await([[
        INSERT INTO truck_bols
            (bol_number, load_id, citizenid, driver_name,
             company_id, company_name,
             shipper_id, shipper_name,
             origin_label, destination_label, distance_miles,
             cargo_type, cargo_description, weight_lbs, tier,
             hazmat_class, placard_class, license_class, license_matched,
             seal_number, seal_status,
             temp_required_min, temp_required_max,
             bol_status, is_leon, issued_at)
        VALUES (?,?,?,?, ?,?, ?,?, ?,?,?, ?,?,?,?, ?,?,?,?, ?,?, ?,?, ?,?,?)
    ]], {
        data.bol_number, data.load_id, data.citizenid, data.driver_name,
        data.company_id, data.company_name,
        data.shipper_id, data.shipper_name,
        data.origin_label, data.destination_label, data.distance_miles,
        data.cargo_type, data.cargo_description, data.weight_lbs, data.tier,
        data.hazmat_class, data.placard_class, data.license_class,
        data.license_matched ~= false, -- default true
        data.seal_number, data.seal_status or 'not_applied',
        data.temp_required_min, data.temp_required_max,
        data.bol_status or 'active', data.is_leon or false, data.issued_at or GetServerTime(),
    })
end

--- Fetch a single BOL by id
---@param bolId number
---@return table|nil
function DB.GetBOL(bolId)
    return MySQL.single.await(
        'SELECT * FROM truck_bols WHERE id = ?',
        { bolId }
    )
end

--- Fetch a single BOL by bol_number
---@param bolNumber string
---@return table|nil
function DB.GetBOLByNumber(bolNumber)
    return MySQL.single.await(
        'SELECT * FROM truck_bols WHERE bol_number = ?',
        { bolNumber }
    )
end

--- Update fields on a BOL record
---@param bolId number
---@param fields table key-value pairs to SET
---@return number affectedRows
function DB.UpdateBOL(bolId, fields)
    local setClauses = {}
    local params = {}
    for k, v in pairs(fields) do
        -- Handle JSON values -- payout_breakdown is stored as JSON
        if k == 'payout_breakdown' and type(v) == 'table' then
            setClauses[#setClauses + 1] = k .. ' = ?'
            params[#params + 1] = json.encode(v)
        else
            setClauses[#setClauses + 1] = k .. ' = ?'
            params[#params + 1] = v
        end
    end
    params[#params + 1] = bolId
    return MySQL.update.await(
        'UPDATE truck_bols SET ' .. table.concat(setClauses, ', ') .. ' WHERE id = ?',
        params
    )
end

--- Fetch all BOLs for a player (profile / history)
---@param citizenid string
---@param limit number|nil  defaults to 50
---@return table[]
function DB.GetBOLsByPlayer(citizenid, limit)
    return MySQL.query.await(
        'SELECT * FROM truck_bols WHERE citizenid = ? ORDER BY issued_at DESC LIMIT ?',
        { citizenid, limit or 50 }
    )
end

-- ============================================================================
-- BOL EVENTS
-- ============================================================================

--- Append an event to the BOL audit trail
---@param data table { bol_id, bol_number, citizenid, event_type, event_data, coords }
---@return number insertId
function DB.InsertBOLEvent(data)
    return MySQL.insert.await([[
        INSERT INTO truck_bol_events
            (bol_id, bol_number, citizenid, event_type, event_data, coords, occurred_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    ]], {
        data.bol_id,
        data.bol_number,
        data.citizenid,
        data.event_type,
        data.event_data and json.encode(data.event_data) or nil,
        data.coords and json.encode(data.coords) or nil,
        data.occurred_at or GetServerTime(),
    })
end

-- ============================================================================
-- DEPOSITS
-- ============================================================================

--- Record a deposit held against a BOL
---@param data table { bol_id, bol_number, citizenid, amount, tier, deposit_type }
---@return number insertId
function DB.InsertDeposit(data)
    return MySQL.insert.await([[
        INSERT INTO truck_deposits
            (bol_id, bol_number, citizenid, amount, tier, deposit_type, status, posted_at)
        VALUES (?, ?, ?, ?, ?, ?, 'held', ?)
    ]], {
        data.bol_id,
        data.bol_number,
        data.citizenid,
        data.amount,
        data.tier,
        data.deposit_type or 'percentage',
        GetServerTime(),
    })
end

--- Fetch a deposit record by bol_id
---@param bolId number
---@return table|nil
function DB.GetDeposit(bolId)
    return MySQL.single.await(
        'SELECT * FROM truck_deposits WHERE bol_id = ?',
        { bolId }
    )
end

--- Update deposit status (returned or forfeited)
---@param depositId number
---@param status string  'returned' or 'forfeited'
---@return number affectedRows
function DB.UpdateDepositStatus(depositId, status)
    return MySQL.update.await(
        'UPDATE truck_deposits SET status = ?, resolved_at = ? WHERE id = ?',
        { status, GetServerTime(), depositId }
    )
end

-- ============================================================================
-- REPUTATION
-- ============================================================================

--- Insert a driver reputation change log entry
---@param data table
---@return number insertId
function DB.InsertRepLog(data)
    return MySQL.insert.await([[
        INSERT INTO truck_driver_reputation_log
            (driver_id, citizenid, change_type,
             points_before, points_change, points_after,
             tier_before, tier_after,
             bol_id, bol_number, tier_of_load, occurred_at)
        VALUES (?,?,?, ?,?,?, ?,?, ?,?,?,?)
    ]], {
        data.driver_id, data.citizenid, data.change_type,
        data.points_before, data.points_change, data.points_after,
        data.tier_before, data.tier_after,
        data.bol_id, data.bol_number, data.tier_of_load,
        data.occurred_at or GetServerTime(),
    })
end

--- Get the current reputation for a driver (from the driver row itself)
---@param citizenid string
---@return table|nil  { reputation_score, reputation_tier }
function DB.GetDriverReputation(citizenid)
    return MySQL.single.await(
        'SELECT reputation_score, reputation_tier FROM truck_drivers WHERE citizenid = ?',
        { citizenid }
    )
end

-- ============================================================================
-- SHIPPER REPUTATION
-- ============================================================================

--- Get the shipper rep record for a driver+shipper pair
---@param citizenid string
---@param shipperId string
---@return table|nil
function DB.GetShipperRep(citizenid, shipperId)
    return MySQL.single.await([[
        SELECT * FROM truck_shipper_reputation
        WHERE citizenid = ? AND shipper_id = ?
    ]], { citizenid, shipperId })
end

--- Insert or update a shipper reputation record
---@param data table
---@return number affectedRows
function DB.UpsertShipperRep(data)
    return MySQL.insert.await([[
        INSERT INTO truck_shipper_reputation
            (driver_id, citizenid, shipper_id, points, tier,
             deliveries_completed, current_clean_streak, last_delivery_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            points = VALUES(points),
            tier = VALUES(tier),
            deliveries_completed = VALUES(deliveries_completed),
            current_clean_streak = VALUES(current_clean_streak),
            last_delivery_at = VALUES(last_delivery_at)
    ]], {
        data.driver_id, data.citizenid, data.shipper_id,
        data.points, data.tier,
        data.deliveries_completed, data.current_clean_streak,
        data.last_delivery_at or GetServerTime(),
    })
end

--- Insert a shipper reputation change log entry
---@param data table
---@return number insertId
function DB.InsertShipperRepLog(data)
    return MySQL.insert.await([[
        INSERT INTO truck_shipper_reputation_log
            (driver_id, citizenid, shipper_id, change_type,
             points_before, points_change, points_after,
             tier_before, tier_after, bol_id, occurred_at)
        VALUES (?,?,?,?, ?,?,?, ?,?, ?,?)
    ]], {
        data.driver_id, data.citizenid, data.shipper_id, data.change_type,
        data.points_before, data.points_change, data.points_after,
        data.tier_before, data.tier_after,
        data.bol_id, data.occurred_at or GetServerTime(),
    })
end

-- ============================================================================
-- BOARD STATE
-- ============================================================================

--- Get the board state row for a region
---@param region string
---@return table|nil
function DB.GetBoardState(region)
    return MySQL.single.await(
        'SELECT * FROM truck_board_state WHERE region = ?',
        { region }
    )
end

--- Update the board state row for a region
---@param region string
---@param fields table
---@return number affectedRows
function DB.UpdateBoardState(region, fields)
    local setClauses = {}
    local params = {}
    for k, v in pairs(fields) do
        setClauses[#setClauses + 1] = k .. ' = ?'
        params[#params + 1] = v
    end
    params[#params + 1] = region

    -- Upsert: if the row does not exist yet, insert it
    local existing = DB.GetBoardState(region)
    if not existing then
        fields.region = region
        fields.updated_at = GetServerTime()
        local cols = {}
        local placeholders = {}
        local insertParams = {}
        for k, v in pairs(fields) do
            cols[#cols + 1] = k
            placeholders[#placeholders + 1] = '?'
            insertParams[#insertParams + 1] = v
        end
        return MySQL.insert.await(
            'INSERT INTO truck_board_state (' .. table.concat(cols, ', ') .. ') VALUES (' .. table.concat(placeholders, ', ') .. ')',
            insertParams
        )
    end

    setClauses[#setClauses + 1] = 'updated_at = ?'
    params[#params] = nil -- remove the trailing region we added
    params[#params + 1] = GetServerTime()
    params[#params + 1] = region
    return MySQL.update.await(
        'UPDATE truck_board_state SET ' .. table.concat(setClauses, ', ') .. ' WHERE region = ?',
        params
    )
end

-- ============================================================================
-- SURGE
-- ============================================================================

--- Insert a new surge event
---@param data table
---@return number insertId
function DB.InsertSurge(data)
    return MySQL.insert.await([[
        INSERT INTO truck_surge_events
            (region, surge_type, cargo_type_filter, shipper_filter,
             surge_percentage, trigger_data, status, started_at, expires_at)
        VALUES (?, ?, ?, ?, ?, ?, 'active', ?, ?)
    ]], {
        data.region,
        data.surge_type,
        data.cargo_type_filter,
        data.shipper_filter,
        data.surge_percentage,
        data.trigger_data and json.encode(data.trigger_data) or nil,
        data.started_at or GetServerTime(),
        data.expires_at,
    })
end

--- Fetch all active surges, optionally filtered by region
---@param region string|nil
---@return table[]
function DB.GetActiveSurges(region)
    if region then
        return MySQL.query.await([[
            SELECT * FROM truck_surge_events
            WHERE status = 'active'
              AND (region = ? OR region = 'server_wide')
            ORDER BY started_at DESC
        ]], { region })
    end
    return MySQL.query.await(
        "SELECT * FROM truck_surge_events WHERE status = 'active' ORDER BY started_at DESC",
        {}
    )
end

--- Expire all surges past their expiration time
---@return number affectedRows
function DB.ExpireSurges()
    return MySQL.update.await([[
        UPDATE truck_surge_events
        SET status = 'expired', ended_at = ?
        WHERE status = 'active' AND expires_at < ?
    ]], { GetServerTime(), GetServerTime() })
end

-- ============================================================================
-- ROUTES
-- ============================================================================

--- Insert a generated route
---@param data table
---@return number insertId
function DB.InsertRoute(data)
    return MySQL.insert.await([[
        INSERT INTO truck_routes
            (route_name, shipper_id, region, tier, cargo_type,
             stop_count, stops, total_distance_miles,
             required_license, base_payout_rental, base_payout_owner_op,
             multi_stop_premium_pct, deposit_amount, window_minutes,
             posted_at, expires_at)
        VALUES (?,?,?,?,?, ?,?,?, ?,?,?, ?,?,?, ?,?)
    ]], {
        data.route_name, data.shipper_id, data.region, data.tier, data.cargo_type,
        data.stop_count, json.encode(data.stops), data.total_distance_miles,
        data.required_license, data.base_payout_rental, data.base_payout_owner_op,
        data.multi_stop_premium_pct, data.deposit_amount, data.window_minutes,
        data.posted_at or GetServerTime(), data.expires_at,
    })
end

--- Fetch available routes for a region
---@param region string
---@return table[]
function DB.GetAvailableRoutes(region)
    return MySQL.query.await([[
        SELECT * FROM truck_routes
        WHERE region = ? AND route_status = 'available' AND expires_at > ?
        ORDER BY tier ASC
    ]], { region, GetServerTime() })
end

-- ============================================================================
-- CONTRACTS
-- ============================================================================

--- Insert a supplier contract
---@param data table
---@return number insertId
function DB.InsertContract(data)
    return MySQL.insert.await([[
        INSERT INTO truck_supplier_contracts
            (client_id, client_name, region, required_item, required_quantity,
             destination_label, destination_coords, window_hours, base_payout,
             partial_allowed, posted_at, expires_at, is_leon)
        VALUES (?,?,?,?,?, ?,?,?,?, ?,?,?,?)
    ]], {
        data.client_id, data.client_name, data.region,
        data.required_item, data.required_quantity,
        data.destination_label, json.encode(data.destination_coords),
        data.window_hours, data.base_payout,
        data.partial_allowed ~= false,
        data.posted_at or GetServerTime(), data.expires_at,
        data.is_leon or false,
    })
end

--- Fetch available supplier contracts for a region
---@param region string
---@return table[]
function DB.GetAvailableContracts(region)
    return MySQL.query.await([[
        SELECT * FROM truck_supplier_contracts
        WHERE region = ? AND contract_status = 'available' AND expires_at > ?
        ORDER BY posted_at DESC
    ]], { region, GetServerTime() })
end

-- ============================================================================
-- OPEN CONTRACTS
-- ============================================================================

--- Fetch active open contracts (server-wide)
---@return table[]
function DB.GetOpenContracts()
    return MySQL.query.await([[
        SELECT * FROM truck_open_contracts
        WHERE contract_status = 'active' AND expires_at > ?
        ORDER BY posted_at DESC
    ]], { GetServerTime() })
end

--- Update a contribution to an open contract
---@param contractId number
---@param citizenid string
---@param companyId number|nil
---@param quantityAdded number
---@return number affectedRows
function DB.UpdateContribution(contractId, citizenid, companyId, quantityAdded)
    -- Fetch current contract to calculate percentage
    local contract = MySQL.single.await(
        'SELECT * FROM truck_open_contracts WHERE id = ?',
        { contractId }
    )
    if not contract then return 0 end

    -- Upsert the contribution row
    MySQL.insert.await([[
        INSERT INTO truck_open_contract_contributions
            (contract_id, citizenid, company_id, quantity_contributed, last_contribution_at)
        VALUES (?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            quantity_contributed = quantity_contributed + VALUES(quantity_contributed),
            last_contribution_at = VALUES(last_contribution_at)
    ]], { contractId, citizenid, companyId, quantityAdded, GetServerTime() })

    -- Update the contract total
    MySQL.update.await([[
        UPDATE truck_open_contracts
        SET quantity_fulfilled = quantity_fulfilled + ?
        WHERE id = ?
    ]], { quantityAdded, contractId })

    -- Recalculate contribution percentages for all contributors
    return MySQL.update.await([[
        UPDATE truck_open_contract_contributions c
        JOIN truck_open_contracts oc ON c.contract_id = oc.id
        SET c.contribution_pct = c.quantity_contributed / oc.total_quantity_needed
        WHERE c.contract_id = ?
    ]], { contractId })
end

-- ============================================================================
-- MAINTENANCE QUERIES (Section 4.3)
-- Run on resource start and every 15 minutes
-- ============================================================================

--- Expire stale reservations (3-minute hold expired)
---@return number affectedRows
function DB.ExpireReservations()
    return MySQL.update.await([[
        UPDATE truck_loads
        SET board_status = 'available', reserved_by = NULL, reserved_until = NULL
        WHERE board_status = 'reserved' AND reserved_until < ?
    ]], { GetServerTime() })
end

--- Expire board loads past their expiry time
---@return number affectedRows
function DB.ExpireBoardLoads()
    return MySQL.update.await([[
        UPDATE truck_loads SET board_status = 'expired'
        WHERE board_status = 'available' AND expires_at < ?
    ]], { GetServerTime() })
end

--- Expire insurance policies past their valid_until
---@return number affectedRows
function DB.ExpireInsurancePolicies()
    return MySQL.update.await([[
        UPDATE truck_insurance_policies SET status = 'expired'
        WHERE status = 'active' AND valid_until IS NOT NULL AND valid_until < ?
    ]], { GetServerTime() })
end

--- Lift driver suspensions that have expired
---@return number affectedRows
function DB.LiftExpiredSuspensions()
    return MySQL.update.await([[
        UPDATE truck_drivers
        SET reputation_tier = 'restricted', reputation_score = 1, suspended_until = NULL
        WHERE reputation_tier = 'suspended' AND suspended_until IS NOT NULL AND suspended_until < ?
    ]], { GetServerTime() })
end

--- Decay preferred shipper tier for inactive drivers (14 days)
---@return number affectedRows
function DB.DecayPreferredTier()
    local cutoff = GetServerTime() - 1209600 -- 14 days in seconds
    -- First, warn drivers approaching decay (already warned = ready to decay)
    MySQL.update.await([[
        UPDATE truck_shipper_reputation
        SET tier = 'trusted', points = LEAST(points, 699)
        WHERE tier = 'preferred'
          AND last_delivery_at < ?
          AND preferred_decay_warned = TRUE
    ]], { cutoff })

    -- Set warning flag for drivers who have not been warned yet
    return MySQL.update.await([[
        UPDATE truck_shipper_reputation
        SET preferred_decay_warned = TRUE
        WHERE tier = 'preferred'
          AND last_delivery_at < ?
          AND preferred_decay_warned = FALSE
    ]], { cutoff })
end

--- Fetch pending insurance claim payouts that are due
---@return table[]
function DB.GetPendingClaimPayouts()
    return MySQL.query.await([[
        SELECT ic.* FROM truck_insurance_claims ic
        WHERE ic.status = 'approved' AND ic.payout_at <= ?
    ]], { GetServerTime() })
end
