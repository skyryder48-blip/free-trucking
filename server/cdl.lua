--[[
    server/cdl.lua — CDL License and Certification Issuance

    Handles CDL written tests, HAZMAT briefings, license issuance,
    certification prerequisites, tutorial stage tracking, and
    inventory item management for all trucking credentials.

    License progression:
        No license       -> Tier 0 access only
        Class B CDL      -> Tier 0 + Tier 1
        Class A CDL      -> All tiers (endorsements still required)
        Tanker Endorse.  -> Fuel tanker + liquid bulk
        HAZMAT Endorse.  -> Hazmat cargo
        Oversized Permit -> Oversized loads (monthly)

    Certifications:
        Bilkington Carrier  -> Pharmaceutical loads
        High-Value          -> High-value goods
        Government Clearance -> Military / government loads

    Written test parameters:
        Class B:  10 questions from 40-pool, 80% pass, $150, 3-fail lockout 1hr
        Class A:  10 questions from 40-pool, 80% pass, $300, 3-fail lockout 1hr
        Tanker:   15 questions from pool, 80% pass, $500
        HAZMAT:   Briefing only (5 topics), $750 + $500 background, no pass/fail

    Tutorial (Class A practical):
        5 stages, Class A CDL issued on Stage 5 completion with $850 payout
]]

-- ─────────────────────────────────────────────
-- TEST CONFIGURATION
-- ─────────────────────────────────────────────

local TestConfig = {
    class_b = {
        questionCount = 10,
        passThreshold = 0.80,  -- 80%
        fee = 150,
        maxAttempts = 3,
        lockoutSeconds = 3600,  -- 1 hour
    },
    class_a = {
        questionCount = 10,
        passThreshold = 0.80,
        fee = 300,
        maxAttempts = 3,
        lockoutSeconds = 3600,
    },
    tanker = {
        questionCount = 15,
        passThreshold = 0.80,
        fee = 500,
        maxAttempts = 3,
        lockoutSeconds = 3600,
    },
}

local HAZMATConfig = {
    fee = 750,
    backgroundFee = 500,
    topicCount = 5,
}

local TutorialPayout = 850  -- $850 on Stage 5 completion

-- ─────────────────────────────────────────────
-- CERTIFICATION PREREQUISITES (Section 9.4)
-- ─────────────────────────────────────────────

local CertPrerequisites = {
    bilkington_carrier = {
        license = 'class_a',
        minColdChainDeliveries = 10,
        cleanColdChainStreak = 5,    -- no critical excursions in last 5 cold chain
        noViolationsDays = 14,
        fee = 0,  -- included in LSDOT application
        validDays = 30,
    },
    high_value = {
        license = 'class_a',
        cleanRecordDays = 7,
        noTheftClaimsDays = 30,
        backgroundFee = 1000,
        interviewRequired = true,
        interviewQuestions = 5,
        interviewPassCount = 4,
        validDays = 30,
    },
    government_clearance = {
        license = 'class_a',
        certRequired = 'high_value',
        cleanRecordDays = 30,
        minShipperTier3Count = 3,  -- trusted+ with 3+ different shippers
        applicationFee = 5000,
        validDays = nil,  -- no expiry, but violations reset clean record
    },
}

-- ─────────────────────────────────────────────
-- IN-MEMORY STATE
-- ─────────────────────────────────────────────

--- Active test sessions: [src] = { testType, questions, startedAt }
local ActiveTests = {}

--- Active HAZMAT briefings: [src] = { startedAt, citizenid }
local ActiveBriefings = {}

--- Tutorial progress: [citizenid] = currentStage (1-5)
local TutorialProgress = {}

-- ─────────────────────────────────────────────
-- WRITTEN TEST SYSTEM
-- ─────────────────────────────────────────────

--- Start a written test for a license type
--- Validates fee payment, checks lockout, selects random questions
---@param src number Player server ID
---@param testType string 'class_b', 'class_a', or 'tanker'
---@return boolean success
---@return string|table result Error message or question data for NUI
function StartWrittenTest(src, testType)
    if not src or not testType then
        return false, 'missing_parameters'
    end

    local config = TestConfig[testType]
    if not config then
        return false, 'invalid_test_type'
    end

    local player = exports.qbx_core:GetPlayer(src)
    if not player then
        return false, 'player_not_found'
    end
    local citizenid = player.PlayerData.citizenid

    -- Prevent taking a test while one is already active
    if ActiveTests[src] then
        return false, 'test_already_active'
    end

    -- Fetch driver record (or create one if first interaction)
    local driver = MySQL.single.await(
        'SELECT id FROM truck_drivers WHERE citizenid = ?',
        { citizenid }
    )
    if not driver then
        -- Create driver record on first test attempt
        local playerName = player.PlayerData.charinfo.firstname .. ' ' .. player.PlayerData.charinfo.lastname
        local now = os.time()
        local driverId = MySQL.insert.await([[
            INSERT INTO truck_drivers (citizenid, player_name, reputation_score, reputation_tier, first_seen, last_seen)
            VALUES (?, ?, 500, 'developing', ?, ?)
        ]], { citizenid, playerName, now, now })
        driver = { id = driverId }
    end

    -- Check for existing license of this type
    local existingLicense = MySQL.single.await(
        'SELECT id, status FROM truck_licenses WHERE driver_id = ? AND license_type = ?',
        { driver.id, testType }
    )
    if existingLicense and existingLicense.status == 'active' then
        return false, 'already_licensed'
    end

    -- Check lockout status
    local licenseRecord = MySQL.single.await(
        'SELECT written_test_attempts, locked_until FROM truck_licenses WHERE driver_id = ? AND license_type = ?',
        { driver.id, testType }
    )
    if licenseRecord and licenseRecord.locked_until then
        if os.time() < licenseRecord.locked_until then
            local remaining = licenseRecord.locked_until - os.time()
            return false, ('locked_out:%d'):format(remaining)
        else
            -- Lockout expired — reset attempts
            MySQL.update.await(
                'UPDATE truck_licenses SET written_test_attempts = 0, locked_until = NULL WHERE driver_id = ? AND license_type = ?',
                { driver.id, testType }
            )
        end
    end

    -- Validate fee payment
    local bankBalance = player.PlayerData.money.bank or 0
    if bankBalance < config.fee then
        return false, 'insufficient_funds'
    end

    -- Deduct fee
    local deducted = player.Functions.RemoveMoney('bank', config.fee,
        ('CDL %s test fee'):format(testType))
    if not deducted then
        return false, 'payment_failed'
    end

    -- Select random questions from pool (defined in config/cdl.lua)
    -- CDLQuestionPools is expected to be defined in config/cdl.lua
    local pool = CDLQuestionPools and CDLQuestionPools[testType]
    if not pool or #pool == 0 then
        -- Refund if no question pool available
        player.Functions.AddMoney('bank', config.fee, 'CDL test fee refund - no questions')
        return false, 'no_question_pool'
    end

    -- Shuffle and select questions
    local selectedQuestions = {}
    local indices = {}
    for i = 1, #pool do
        indices[i] = i
    end

    -- Fisher-Yates shuffle
    for i = #indices, 2, -1 do
        local j = math.random(1, i)
        indices[i], indices[j] = indices[j], indices[i]
    end

    local count = math.min(config.questionCount, #pool)
    for i = 1, count do
        local q = pool[indices[i]]
        table.insert(selectedQuestions, {
            index = i,
            question = q.question,
            options = q.options,
            -- Do NOT send correct answer to client
        })
    end

    -- Store answer key server-side
    local answerKey = {}
    for i = 1, count do
        answerKey[i] = pool[indices[i]].correct
    end

    -- Store active test session
    ActiveTests[src] = {
        testType = testType,
        driverId = driver.id,
        citizenid = citizenid,
        questions = pool,
        selectedIndices = {},
        answerKey = answerKey,
        startedAt = os.time(),
        fee = config.fee,
    }
    for i = 1, count do
        ActiveTests[src].selectedIndices[i] = indices[i]
    end

    -- Create or update license record to track attempts
    if not licenseRecord then
        MySQL.insert.await([[
            INSERT INTO truck_licenses (driver_id, citizenid, license_type, status, written_test_attempts, fee_paid, issued_at)
            VALUES (?, ?, ?, 'suspended', 1, ?, ?)
        ]], { driver.id, citizenid, testType, config.fee, os.time() })
    else
        MySQL.update.await(
            'UPDATE truck_licenses SET written_test_attempts = written_test_attempts + 1 WHERE driver_id = ? AND license_type = ?',
            { driver.id, testType }
        )
    end

    lib.notify(src, {
        title = 'CDL Test',
        description = ('$%d fee paid. %d questions, %d%% required to pass.'):format(
            config.fee, count, config.passThreshold * 100),
        type = 'inform',
    })

    print(('[trucking:cdl] %s started %s written test'):format(citizenid, testType))

    return true, selectedQuestions
end

--- Submit test answers and grade the test
---@param src number Player server ID
---@param testType string The test type being submitted
---@param answers table Player's answers (indexed array matching question order)
---@return boolean success
---@return table result { passed, score, required, totalQuestions }
function SubmitTestResults(src, testType, answers)
    if not src or not testType or not answers then
        return false, 'missing_parameters'
    end

    local session = ActiveTests[src]
    if not session then
        return false, 'no_active_test'
    end

    if session.testType ~= testType then
        return false, 'test_type_mismatch'
    end

    local config = TestConfig[testType]
    if not config then
        ActiveTests[src] = nil
        return false, 'invalid_test_type'
    end

    -- Grade the test
    local correct = 0
    local totalQuestions = #session.answerKey
    for i = 1, totalQuestions do
        if answers[i] and answers[i] == session.answerKey[i] then
            correct = correct + 1
        end
    end

    local score = correct / totalQuestions
    local passed = score >= config.passThreshold

    -- Clean up test session
    ActiveTests[src] = nil

    local player = exports.qbx_core:GetPlayer(src)
    if not player then
        return false, 'player_not_found'
    end

    if passed then
        -- Issue the license
        IssueLicense(src, testType)

        lib.notify(src, {
            title = 'CDL Test Passed',
            description = ('%d/%d correct (%d%%). License issued!'):format(
                correct, totalQuestions, math.floor(score * 100)),
            type = 'success',
        })
    else
        -- Check if max attempts reached — apply lockout
        local licenseRecord = MySQL.single.await(
            'SELECT written_test_attempts FROM truck_licenses WHERE driver_id = ? AND license_type = ?',
            { session.driverId, testType }
        )

        if licenseRecord and licenseRecord.written_test_attempts >= config.maxAttempts then
            local lockUntil = os.time() + config.lockoutSeconds
            MySQL.update.await(
                'UPDATE truck_licenses SET locked_until = ? WHERE driver_id = ? AND license_type = ?',
                { lockUntil, session.driverId, testType }
            )

            lib.notify(src, {
                title = 'CDL Test Failed',
                description = ('%d/%d correct. Max attempts reached — locked out for 1 hour.'):format(
                    correct, totalQuestions),
                type = 'error',
            })
        else
            lib.notify(src, {
                title = 'CDL Test Failed',
                description = ('%d/%d correct (%d%% required). Try again.'):format(
                    correct, totalQuestions, math.floor(config.passThreshold * 100)),
                type = 'error',
            })
        end
    end

    print(('[trucking:cdl] %s %s %s test: %d/%d (%d%%)'):format(
        session.citizenid, passed and 'PASSED' or 'FAILED', testType,
        correct, totalQuestions, math.floor(score * 100)))

    return true, {
        passed = passed,
        score = correct,
        required = math.ceil(totalQuestions * config.passThreshold),
        totalQuestions = totalQuestions,
    }
end

-- ─────────────────────────────────────────────
-- LICENSE ISSUANCE
-- ─────────────────────────────────────────────

--- Issue a CDL license to a player
---@param src number Player server ID
---@param licenseType string The license type to issue
---@return boolean success
function IssueLicense(src, licenseType)
    if not src or not licenseType then return false end

    local player = exports.qbx_core:GetPlayer(src)
    if not player then return false end
    local citizenid = player.PlayerData.citizenid

    local driver = MySQL.single.await(
        'SELECT id FROM truck_drivers WHERE citizenid = ?',
        { citizenid }
    )
    if not driver then return false end

    local now = os.time()

    -- Calculate expiry for oversized monthly permit (30 days)
    local expiresAt = nil
    if licenseType == 'oversized_monthly' then
        expiresAt = now + (30 * 86400)  -- 30 days
    end

    -- Update or insert license record
    local existing = MySQL.single.await(
        'SELECT id FROM truck_licenses WHERE driver_id = ? AND license_type = ?',
        { driver.id, licenseType }
    )

    if existing then
        MySQL.update.await([[
            UPDATE truck_licenses
            SET status = 'active', issued_at = ?, expires_at = ?, locked_until = NULL
            WHERE id = ?
        ]], { now, expiresAt, existing.id })
    else
        MySQL.insert.await([[
            INSERT INTO truck_licenses
            (driver_id, citizenid, license_type, status, fee_paid, issued_at, expires_at)
            VALUES (?, ?, ?, 'active', 0, ?, ?)
        ]], { driver.id, citizenid, licenseType, now, expiresAt })
    end

    -- Add physical license item to inventory
    local itemName = 'trucking_cdl_' .. licenseType
    exports.ox_inventory:AddItem(src, itemName, 1, {
        license_type = licenseType,
        citizenid = citizenid,
        issued_at = now,
        expires_at = expiresAt,
    })

    print(('[trucking:cdl] License %s issued to %s'):format(licenseType, citizenid))

    return true
end

--- Check if a player has an active license of the specified type
---@param citizenid string Driver's citizen ID
---@param licenseType string The license type to check
---@return boolean hasLicense
---@return table|nil licenseRecord
function CheckLicense(citizenid, licenseType)
    if not citizenid or not licenseType then return false end

    local license = MySQL.single.await([[
        SELECT tl.* FROM truck_licenses tl
        JOIN truck_drivers td ON tl.driver_id = td.id
        WHERE td.citizenid = ? AND tl.license_type = ? AND tl.status = 'active'
    ]], { citizenid, licenseType })

    if not license then return false end

    -- Check expiry if applicable
    if license.expires_at and os.time() > license.expires_at then
        MySQL.update.await(
            'UPDATE truck_licenses SET status = ? WHERE id = ?',
            { 'suspended', license.id }
        )
        return false
    end

    return true, license
end

--- Check if a player has a specific endorsement (tanker/hazmat)
---@param citizenid string Driver's citizen ID
---@param endorsementType string 'tanker' or 'hazmat'
---@return boolean hasEndorsement
function HasEndorsement(citizenid, endorsementType)
    if not citizenid or not endorsementType then return false end

    -- Endorsements are stored as license types
    local hasIt, _ = CheckLicense(citizenid, endorsementType)
    return hasIt
end

-- ─────────────────────────────────────────────
-- HAZMAT BRIEFING
-- ─────────────────────────────────────────────

--- Start HAZMAT briefing process (no pass/fail — completion grants endorsement)
---@param src number Player server ID
---@return boolean success
---@return string|table result Error or briefing topic data
function StartHAZMATBriefing(src)
    if not src then return false, 'missing_parameters' end

    local player = exports.qbx_core:GetPlayer(src)
    if not player then return false, 'player_not_found' end
    local citizenid = player.PlayerData.citizenid

    -- Check if already has HAZMAT endorsement
    if HasEndorsement(citizenid, 'hazmat') then
        return false, 'already_endorsed'
    end

    -- Check if already in a briefing
    if ActiveBriefings[src] then
        return false, 'briefing_already_active'
    end

    -- Must have Class A CDL first
    local hasClassA = CheckLicense(citizenid, 'class_a')
    if not hasClassA then
        return false, 'class_a_required'
    end

    -- Calculate total fee ($750 briefing + $500 background)
    local totalFee = HAZMATConfig.fee + HAZMATConfig.backgroundFee

    -- Validate funds
    local bankBalance = player.PlayerData.money.bank or 0
    if bankBalance < totalFee then
        return false, 'insufficient_funds'
    end

    -- Deduct fees
    local deducted = player.Functions.RemoveMoney('bank', totalFee,
        'HAZMAT briefing fee ($750) + background check ($500)')
    if not deducted then
        return false, 'payment_failed'
    end

    -- Store briefing session
    ActiveBriefings[src] = {
        citizenid = citizenid,
        startedAt = os.time(),
    }

    -- Return briefing topics (defined in config/cdl.lua or inline)
    local topics = {
        { id = 1, title = 'Hazardous Materials Classification', description = 'DOT hazard classes 1-9 and their transport requirements' },
        { id = 2, title = 'Placarding Requirements', description = 'When and how to display hazmat placards on transport vehicles' },
        { id = 3, title = 'Emergency Response Procedures', description = 'Spill containment, evacuation distances, and first responder coordination' },
        { id = 4, title = 'Route Planning and Restrictions', description = 'Prohibited routes, tunnel restrictions, and populated area avoidance' },
        { id = 5, title = 'Documentation and Shipping Papers', description = 'BOL requirements, emergency contact info, and shipping descriptions' },
    }

    lib.notify(src, {
        title = 'HAZMAT Briefing',
        description = ('$%d paid. Complete all 5 topics to receive endorsement.'):format(totalFee),
        type = 'inform',
    })

    print(('[trucking:cdl] %s started HAZMAT briefing'):format(citizenid))

    return true, topics
end

--- Complete HAZMAT briefing and issue endorsement
---@param src number Player server ID
---@return boolean success
function CompleteHAZMATBriefing(src)
    if not src then return false end

    local session = ActiveBriefings[src]
    if not session then
        return false
    end

    local citizenid = session.citizenid
    ActiveBriefings[src] = nil

    -- Issue HAZMAT endorsement as a license
    IssueLicense(src, 'hazmat')

    lib.notify(src, {
        title = 'HAZMAT Endorsement Issued',
        description = 'You are now certified to transport hazardous materials.',
        type = 'success',
    })

    print(('[trucking:cdl] HAZMAT endorsement issued to %s'):format(citizenid))

    return true
end

-- ─────────────────────────────────────────────
-- CERTIFICATIONS
-- ─────────────────────────────────────────────

--- Apply for a certification — validates all prerequisites
---@param src number Player server ID
---@param certType string 'bilkington_carrier', 'high_value', or 'government_clearance'
---@return boolean success
---@return string|nil error
function ApplyForCertification(src, certType)
    if not src or not certType then
        return false, 'missing_parameters'
    end

    local prereqs = CertPrerequisites[certType]
    if not prereqs then
        return false, 'invalid_cert_type'
    end

    local player = exports.qbx_core:GetPlayer(src)
    if not player then
        return false, 'player_not_found'
    end
    local citizenid = player.PlayerData.citizenid

    local driver = MySQL.single.await(
        'SELECT id, reputation_score FROM truck_drivers WHERE citizenid = ?',
        { citizenid }
    )
    if not driver then
        return false, 'driver_not_found'
    end

    -- Check required license (Class A for all certs)
    if prereqs.license then
        local hasLicense = CheckLicense(citizenid, prereqs.license)
        if not hasLicense then
            return false, 'missing_license'
        end
    end

    -- Check required prerequisite certification (government needs high_value)
    if prereqs.certRequired then
        local hasCert = CheckCertification(citizenid, prereqs.certRequired)
        if not hasCert then
            return false, 'missing_prerequisite_cert'
        end
    end

    -- Check for existing active cert of this type
    local existingCert = MySQL.single.await([[
        SELECT id, status FROM truck_certifications
        WHERE driver_id = ? AND cert_type = ? AND status = 'active'
    ]], { driver.id, certType })
    if existingCert then
        return false, 'already_certified'
    end

    local now = os.time()

    -- ─── BILKINGTON CARRIER prerequisites ───
    if certType == 'bilkington_carrier' then
        -- 10+ cold chain deliveries total
        local coldChainCount = MySQL.single.await([[
            SELECT COUNT(*) as cnt FROM truck_bols
            WHERE citizenid = ? AND cargo_type IN ('cold_chain', 'pharmaceutical', 'pharmaceutical_biologic')
              AND bol_status = 'delivered'
        ]], { citizenid })
        if not coldChainCount or coldChainCount.cnt < prereqs.minColdChainDeliveries then
            return false, 'insufficient_cold_chain_deliveries'
        end

        -- No critical excursions in last 5 cold chain deliveries
        local recentColdChain = MySQL.query.await([[
            SELECT temp_compliance FROM truck_bols
            WHERE citizenid = ? AND cargo_type IN ('cold_chain', 'pharmaceutical', 'pharmaceutical_biologic')
              AND bol_status = 'delivered'
            ORDER BY delivered_at DESC LIMIT ?
        ]], { citizenid, prereqs.cleanColdChainStreak })
        if recentColdChain then
            for _, bol in ipairs(recentColdChain) do
                if bol.temp_compliance == 'significant_excursion' then
                    return false, 'recent_critical_excursion'
                end
            end
        end

        -- No violations in 14 days
        local recentViolations = MySQL.single.await([[
            SELECT COUNT(*) as cnt FROM truck_bol_events
            WHERE citizenid = ? AND event_type IN ('route_violation', 'weigh_station_violation')
              AND occurred_at > ?
        ]], { citizenid, now - (prereqs.noViolationsDays * 86400) })
        if recentViolations and recentViolations.cnt > 0 then
            return false, 'recent_violations'
        end

    -- ─── HIGH-VALUE prerequisites ───
    elseif certType == 'high_value' then
        -- 7-day clean record
        local recentViolations = MySQL.single.await([[
            SELECT COUNT(*) as cnt FROM truck_bol_events
            WHERE citizenid = ? AND event_type IN ('route_violation', 'weigh_station_violation', 'seal_broken', 'load_stolen')
              AND occurred_at > ?
        ]], { citizenid, now - (prereqs.cleanRecordDays * 86400) })
        if recentViolations and recentViolations.cnt > 0 then
            return false, 'recent_violations'
        end

        -- No theft claims in 30 days
        local recentThefts = MySQL.single.await([[
            SELECT COUNT(*) as cnt FROM truck_insurance_claims
            WHERE citizenid = ? AND claim_type = 'theft' AND filed_at > ?
        ]], { citizenid, now - (prereqs.noTheftClaimsDays * 86400) })
        if recentThefts and recentThefts.cnt > 0 then
            return false, 'recent_theft_claims'
        end

        -- Background fee
        local bankBalance = player.PlayerData.money.bank or 0
        if bankBalance < prereqs.backgroundFee then
            return false, 'insufficient_funds'
        end

        local deducted = player.Functions.RemoveMoney('bank', prereqs.backgroundFee,
            'High-Value certification background check')
        if not deducted then
            return false, 'payment_failed'
        end

        -- NPC interview is handled client-side — certification issued on completion
        -- Return pending status so client can start interview
        return true, 'interview_required'

    -- ─── GOVERNMENT CLEARANCE prerequisites ───
    elseif certType == 'government_clearance' then
        -- 30-day clean record (zero violations)
        local recentViolations = MySQL.single.await([[
            SELECT COUNT(*) as cnt FROM truck_bol_events
            WHERE citizenid = ? AND event_type IN (
                'route_violation', 'weigh_station_violation', 'seal_broken',
                'load_stolen', 'load_abandoned'
            ) AND occurred_at > ?
        ]], { citizenid, now - (prereqs.cleanRecordDays * 86400) })
        if recentViolations and recentViolations.cnt > 0 then
            return false, 'recent_violations'
        end

        -- Trusted (tier 3+) reputation with 3+ different shippers
        local trustedShippers = MySQL.single.await([[
            SELECT COUNT(*) as cnt FROM truck_shipper_reputation
            WHERE citizenid = ? AND tier IN ('trusted', 'preferred')
        ]], { citizenid })
        if not trustedShippers or trustedShippers.cnt < prereqs.minShipperTier3Count then
            return false, 'insufficient_shipper_rep'
        end

        -- Application fee
        local bankBalance = player.PlayerData.money.bank or 0
        if bankBalance < prereqs.applicationFee then
            return false, 'insufficient_funds'
        end

        local deducted = player.Functions.RemoveMoney('bank', prereqs.applicationFee,
            'Government Clearance application fee')
        if not deducted then
            return false, 'payment_failed'
        end

        -- Government clearance issues instantly on meeting all requirements
        IssueCertification(src, certType)
        return true
    end

    -- For bilkington_carrier (no interview, no fee beyond LSDOT), issue directly
    if certType == 'bilkington_carrier' then
        IssueCertification(src, certType)
        return true
    end

    return true
end

--- Issue a certification to a player
---@param src number Player server ID
---@param certType string The certification type
---@return boolean success
function IssueCertification(src, certType)
    if not src or not certType then return false end

    local player = exports.qbx_core:GetPlayer(src)
    if not player then return false end
    local citizenid = player.PlayerData.citizenid

    local driver = MySQL.single.await(
        'SELECT id FROM truck_drivers WHERE citizenid = ?',
        { citizenid }
    )
    if not driver then return false end

    local prereqs = CertPrerequisites[certType]
    local now = os.time()
    local expiresAt = nil
    if prereqs and prereqs.validDays then
        expiresAt = now + (prereqs.validDays * 86400)
    end

    local backgroundFee = 0
    if prereqs then
        backgroundFee = prereqs.backgroundFee or prereqs.applicationFee or 0
    end

    -- Check for existing record (may be revoked — update it)
    local existing = MySQL.single.await(
        'SELECT id FROM truck_certifications WHERE driver_id = ? AND cert_type = ?',
        { driver.id, certType }
    )

    if existing then
        MySQL.update.await([[
            UPDATE truck_certifications
            SET status = 'active', revoked_reason = NULL, revoked_at = NULL,
                reinstatement_eligible = NULL, issued_at = ?, expires_at = ?
            WHERE id = ?
        ]], { now, expiresAt, existing.id })
    else
        MySQL.insert.await([[
            INSERT INTO truck_certifications
            (driver_id, citizenid, cert_type, status, background_fee_paid, issued_at, expires_at)
            VALUES (?, ?, ?, 'active', ?, ?, ?)
        ]], { driver.id, citizenid, certType, backgroundFee, now, expiresAt })
    end

    -- Add physical certification item to inventory
    local itemName = 'trucking_cert_' .. certType
    exports.ox_inventory:AddItem(src, itemName, 1, {
        cert_type = certType,
        citizenid = citizenid,
        issued_at = now,
        expires_at = expiresAt,
    })

    lib.notify(src, {
        title = 'Certification Issued',
        description = ('%s certification is now active'):format(certType:gsub('_', ' ')),
        type = 'success',
    })

    print(('[trucking:cdl] Certification %s issued to %s'):format(certType, citizenid))

    return true
end

--- Check if a player has an active certification
---@param citizenid string Driver's citizen ID
---@param certType string The certification type
---@return boolean hasCert
---@return table|nil certRecord
function CheckCertification(citizenid, certType)
    if not citizenid or not certType then return false end

    local cert = MySQL.single.await([[
        SELECT tc.* FROM truck_certifications tc
        JOIN truck_drivers td ON tc.driver_id = td.id
        WHERE td.citizenid = ? AND tc.cert_type = ? AND tc.status = 'active'
    ]], { citizenid, certType })

    if not cert then return false end

    -- Check expiry if applicable
    if cert.expires_at and os.time() > cert.expires_at then
        MySQL.update.await(
            'UPDATE truck_certifications SET status = ? WHERE id = ?',
            { 'expired', cert.id }
        )
        return false
    end

    return true, cert
end

--- Revoke a certification with a reason
---@param citizenid string Driver's citizen ID
---@param certType string The certification type to revoke
---@param reason string The revocation reason
---@return boolean success
function RevokeCertification(citizenid, certType, reason)
    if not citizenid or not certType then return false end

    local now = os.time()
    -- Reinstatement eligible after 30 days
    local reinstatementAt = now + (30 * 86400)

    local updated = MySQL.update.await([[
        UPDATE truck_certifications tc
        JOIN truck_drivers td ON tc.driver_id = td.id
        SET tc.status = 'revoked', tc.revoked_reason = ?, tc.revoked_at = ?,
            tc.reinstatement_eligible = ?
        WHERE td.citizenid = ? AND tc.cert_type = ? AND tc.status = 'active'
    ]], { reason, now, reinstatementAt, citizenid, certType })

    if updated and updated > 0 then
        -- Notify player if online
        local playerSrc = exports.qbx_core:GetPlayerByCitizenId(citizenid)
        if playerSrc then
            lib.notify(playerSrc, {
                title = 'Certification Revoked',
                description = ('%s certification revoked: %s'):format(
                    certType:gsub('_', ' '), reason or 'violation'),
                type = 'error',
            })
        end

        print(('[trucking:cdl] Certification %s revoked for %s: %s'):format(
            certType, citizenid, reason or 'no reason'))

        return true
    end

    return false
end

-- ─────────────────────────────────────────────
-- TUTORIAL STAGE TRACKING
-- ─────────────────────────────────────────────

--- Complete a tutorial stage for the CDL practical exam
--- Stage 5 completion issues Class A CDL and $850 payout
---@param src number Player server ID
---@param stageNumber number The stage number completed (1-5)
---@return boolean success
---@return string|nil error
function CompleteTutorialStage(src, stageNumber)
    if not src or not stageNumber then
        return false, 'missing_parameters'
    end

    if stageNumber < 1 or stageNumber > 5 then
        return false, 'invalid_stage'
    end

    local player = exports.qbx_core:GetPlayer(src)
    if not player then
        return false, 'player_not_found'
    end
    local citizenid = player.PlayerData.citizenid

    -- Ensure stages are completed in order
    local currentProgress = TutorialProgress[citizenid] or 0
    if stageNumber ~= currentProgress + 1 then
        return false, 'stages_must_be_sequential'
    end

    -- Update progress
    TutorialProgress[citizenid] = stageNumber

    lib.notify(src, {
        title = 'Tutorial',
        description = ('Stage %d complete!'):format(stageNumber),
        type = 'success',
    })

    -- Stage 5 completion: issue Class A CDL and $850 payout
    if stageNumber == 5 then
        -- Issue Class A CDL
        IssueLicense(src, 'class_a')

        -- Issue payout
        player.Functions.AddMoney('bank', TutorialPayout,
            'CDL Tutorial completion payout')

        -- Clear tutorial progress
        TutorialProgress[citizenid] = nil

        lib.notify(src, {
            title = 'Class A CDL Issued',
            description = ('CDL practical complete! $%d deposited.'):format(TutorialPayout),
            type = 'success',
        })

        print(('[trucking:cdl] %s completed CDL tutorial — Class A issued, $%d paid'):format(
            citizenid, TutorialPayout))
    end

    return true
end

-- ─────────────────────────────────────────────
-- NET EVENTS
-- ─────────────────────────────────────────────

RegisterNetEvent('trucking:server:startWrittenTest', function(testType)
    local src = source
    if not RateLimitEvent(src, 'startWrittenTest', 5000) then return end

    local success, result = StartWrittenTest(src, testType)
    TriggerClientEvent('trucking:client:writtenTestStarted', src, success, result)
end)

RegisterNetEvent('trucking:server:submitTestResults', function(testType, answers)
    local src = source
    if not RateLimitEvent(src, 'submitTestResults', 5000) then return end

    local success, result = SubmitTestResults(src, testType, answers)
    TriggerClientEvent('trucking:client:testResults', src, success, result)
end)

RegisterNetEvent('trucking:server:startHAZMATBriefing', function()
    local src = source
    if not RateLimitEvent(src, 'startHAZMATBriefing', 10000) then return end

    local success, result = StartHAZMATBriefing(src)
    TriggerClientEvent('trucking:client:hazmatBriefingStarted', src, success, result)
end)

RegisterNetEvent('trucking:server:completeHAZMATBriefing', function()
    local src = source
    if not RateLimitEvent(src, 'completeHAZMATBriefing', 10000) then return end
    CompleteHAZMATBriefing(src)
end)

RegisterNetEvent('trucking:server:applyForCertification', function(certType)
    local src = source
    if not RateLimitEvent(src, 'applyForCertification', 10000) then return end

    local success, result = ApplyForCertification(src, certType)
    TriggerClientEvent('trucking:client:certApplicationResult', src, success, result)
end)

--- Called by client after passing the high-value NPC interview
RegisterNetEvent('trucking:server:completeHighValueInterview', function(passed)
    local src = source
    if not RateLimitEvent(src, 'completeHighValueInterview', 10000) then return end

    if not passed then
        lib.notify(src, {
            title = 'Interview Failed',
            description = 'High-value certification denied. You may reapply.',
            type = 'error',
        })
        return
    end

    IssueCertification(src, 'high_value')
end)

RegisterNetEvent('trucking:server:completeTutorialStage', function(stageNumber)
    local src = source
    if not RateLimitEvent(src, 'completeTutorialStage', 3000) then return end
    CompleteTutorialStage(src, stageNumber)
end)

--- Request license/cert status for NUI
RegisterNetEvent('trucking:server:getCredentials', function()
    local src = source
    local player = exports.qbx_core:GetPlayer(src)
    if not player then return end
    local citizenid = player.PlayerData.citizenid

    local driver = MySQL.single.await(
        'SELECT id FROM truck_drivers WHERE citizenid = ?',
        { citizenid }
    )
    if not driver then
        TriggerClientEvent('trucking:client:credentials', src, { licenses = {}, certifications = {} })
        return
    end

    local licenses = MySQL.query.await(
        'SELECT license_type, status, issued_at, expires_at, locked_until FROM truck_licenses WHERE driver_id = ?',
        { driver.id }
    )

    local certifications = MySQL.query.await(
        'SELECT cert_type, status, issued_at, expires_at, revoked_reason FROM truck_certifications WHERE driver_id = ?',
        { driver.id }
    )

    TriggerClientEvent('trucking:client:credentials', src, {
        licenses = licenses or {},
        certifications = certifications or {},
        tutorialStage = TutorialProgress[citizenid] or 0,
    })
end)

-- ─────────────────────────────────────────────
-- CLEANUP ON PLAYER DROP
-- ─────────────────────────────────────────────

AddEventHandler('playerDropped', function()
    local src = source
    -- Clean up active test and briefing sessions
    ActiveTests[src] = nil
    ActiveBriefings[src] = nil
end)

print('[trucking:cdl] CDL and certification system initialized')
