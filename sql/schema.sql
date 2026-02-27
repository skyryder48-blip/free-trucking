-- ═══════════════════════════════════════════════════════════════
-- Free Trucking — Complete Database Schema
-- 24 Tables · MySQL/MariaDB · InnoDB · utf8mb4
-- ═══════════════════════════════════════════════════════════════
-- All timestamps stored as UNIX epoch integers (INT UNSIGNED).
-- Server-authoritative: os.time() used exclusively on the server.
-- ═══════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────
-- 1. DRIVER CORE
-- ─────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS `truck_drivers` (
    `id`                      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `citizenid`               VARCHAR(50)      NOT NULL UNIQUE,
    `player_name`             VARCHAR(100)     NOT NULL,
    `reputation_score`        SMALLINT UNSIGNED NOT NULL DEFAULT 500,
    `reputation_tier`         ENUM('suspended','restricted','probationary',
                                   'developing','established',
                                   'professional','elite')
                              NOT NULL DEFAULT 'developing',
    `suspended_until`         INT UNSIGNED     DEFAULT NULL,
    `total_loads_completed`   SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    `total_loads_failed`      SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    `total_loads_stolen`      SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    `total_distance_driven`   INT UNSIGNED     NOT NULL DEFAULT 0,
    `total_earnings`          INT UNSIGNED     NOT NULL DEFAULT 0,
    `reservation_releases`    TINYINT UNSIGNED NOT NULL DEFAULT 0,
    `reservation_cooldown`    INT UNSIGNED     DEFAULT NULL,
    `leon_access`             BOOLEAN          NOT NULL DEFAULT FALSE,
    `leon_tier3_deliveries`   SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    `leon_total_loads`        SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    `first_seen`              INT UNSIGNED     NOT NULL,
    `last_seen`               INT UNSIGNED     NOT NULL,
    INDEX `idx_citizenid`      (`citizenid`),
    INDEX `idx_reputation_tier`(`reputation_tier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


CREATE TABLE IF NOT EXISTS `truck_licenses` (
    `id`                      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `driver_id`               BIGINT UNSIGNED  NOT NULL,
    `citizenid`               VARCHAR(50)      NOT NULL,
    `license_type`            ENUM('class_b','class_a','tanker',
                                   'hazmat','oversized_monthly')
                              NOT NULL,
    `status`                  ENUM('active','suspended','revoked')
                              NOT NULL DEFAULT 'active',
    `written_test_attempts`   TINYINT UNSIGNED NOT NULL DEFAULT 0,
    `practical_passed_at`     INT UNSIGNED     DEFAULT NULL,
    `locked_until`            INT UNSIGNED     DEFAULT NULL,
    `fee_paid`                SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    `issued_at`               INT UNSIGNED     NOT NULL,
    `expires_at`              INT UNSIGNED     DEFAULT NULL,
    UNIQUE KEY `uq_driver_license` (`driver_id`, `license_type`),
    INDEX `idx_citizenid` (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


CREATE TABLE IF NOT EXISTS `truck_certifications` (
    `id`                      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `driver_id`               BIGINT UNSIGNED  NOT NULL,
    `citizenid`               VARCHAR(50)      NOT NULL,
    `cert_type`               ENUM('bilkington_carrier','high_value',
                                   'government_clearance')
                              NOT NULL,
    `status`                  ENUM('active','suspended','revoked','expired')
                              NOT NULL DEFAULT 'active',
    `revoked_reason`          VARCHAR(255)     DEFAULT NULL,
    `revoked_at`              INT UNSIGNED     DEFAULT NULL,
    `reinstatement_eligible`  INT UNSIGNED     DEFAULT NULL,
    `background_fee_paid`     SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    `issued_at`               INT UNSIGNED     NOT NULL,
    `expires_at`              INT UNSIGNED     DEFAULT NULL,
    UNIQUE KEY `uq_driver_cert` (`driver_id`, `cert_type`),
    INDEX `idx_citizenid` (`citizenid`),
    INDEX `idx_status`    (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


-- ─────────────────────────────────────────────
-- 2. LOAD SYSTEM
-- ─────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS `truck_loads` (
    `id`                      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `bol_number`              VARCHAR(20)      NOT NULL UNIQUE,
    `tier`                    TINYINT UNSIGNED NOT NULL,
    `cargo_type`              VARCHAR(50)      NOT NULL,
    `cargo_subtype`           VARCHAR(50)      DEFAULT NULL,
    `shipper_id`              VARCHAR(50)      NOT NULL,
    `shipper_name`            VARCHAR(100)     NOT NULL,
    `origin_region`           ENUM('los_santos','sandy_shores',
                                   'paleto','grapeseed')
                              NOT NULL,
    `origin_label`            VARCHAR(100)     NOT NULL,
    `origin_coords`           JSON             NOT NULL,
    `destination_label`       VARCHAR(100)     NOT NULL,
    `destination_coords`      JSON             NOT NULL,
    `distance_miles`          DECIMAL(6,2)     NOT NULL,
    `weight_lbs`              INT UNSIGNED     NOT NULL DEFAULT 0,
    `weight_multiplier`       DECIMAL(4,2)     NOT NULL DEFAULT 1.00,
    `temp_min_f`              TINYINT          DEFAULT NULL,
    `temp_max_f`              TINYINT          DEFAULT NULL,
    `hazmat_class`            TINYINT UNSIGNED DEFAULT NULL,
    `hazmat_un_number`        VARCHAR(10)      DEFAULT NULL,
    `requires_seal`           BOOLEAN          NOT NULL DEFAULT TRUE,
    `min_vehicle_class`       ENUM('none','class_b','class_a')
                              NOT NULL DEFAULT 'none',
    `required_vehicle_type`   VARCHAR(50)      DEFAULT NULL,
    `required_license`        ENUM('none','class_b','class_a')
                              NOT NULL DEFAULT 'none',
    `required_endorsement`    VARCHAR(50)      DEFAULT NULL,
    `required_certification`  VARCHAR(50)      DEFAULT NULL,
    `base_rate_per_mile`      DECIMAL(8,2)     NOT NULL,
    `base_payout_rental`      INT UNSIGNED     NOT NULL DEFAULT 0,
    `base_payout_owner_op`    INT UNSIGNED     NOT NULL DEFAULT 0,
    `deposit_amount`          INT UNSIGNED     NOT NULL DEFAULT 300,
    `board_status`            ENUM('available','reserved','accepted',
                                   'completed','expired','orphaned')
                              NOT NULL DEFAULT 'available',
    `reserved_by`             VARCHAR(50)      DEFAULT NULL,
    `reserved_until`          INT UNSIGNED     DEFAULT NULL,
    `surge_active`            BOOLEAN          NOT NULL DEFAULT FALSE,
    `surge_percentage`        TINYINT UNSIGNED NOT NULL DEFAULT 0,
    `surge_expires`           INT UNSIGNED     DEFAULT NULL,
    `is_leon_load`            BOOLEAN          NOT NULL DEFAULT FALSE,
    `leon_fee`                INT UNSIGNED     DEFAULT NULL,
    `leon_risk_tier`          ENUM('low','medium','high','critical')
                              DEFAULT NULL,
    `leon_supplier_id`        VARCHAR(50)      DEFAULT NULL,
    `is_multi_stop`           BOOLEAN          NOT NULL DEFAULT FALSE,
    `stop_count`              TINYINT UNSIGNED NOT NULL DEFAULT 1,
    `posted_at`               INT UNSIGNED     NOT NULL,
    `expires_at`              INT UNSIGNED     NOT NULL,
    `board_region`            ENUM('los_santos','sandy_shores',
                                   'paleto','grapeseed')
                              NOT NULL,
    INDEX `idx_board_status` (`board_status`),
    INDEX `idx_board_region` (`board_region`),
    INDEX `idx_tier`         (`tier`),
    INDEX `idx_expires_at`   (`expires_at`),
    INDEX `idx_reserved_by`  (`reserved_by`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


CREATE TABLE IF NOT EXISTS `truck_active_loads` (
    `id`                      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `load_id`                 BIGINT UNSIGNED  NOT NULL,
    `bol_id`                  BIGINT UNSIGNED  NOT NULL,
    `citizenid`               VARCHAR(50)      NOT NULL,
    `driver_id`               BIGINT UNSIGNED  NOT NULL,
    `vehicle_plate`           VARCHAR(20)      DEFAULT NULL,
    `vehicle_model`           VARCHAR(50)      DEFAULT NULL,
    `is_rental`               BOOLEAN          NOT NULL DEFAULT FALSE,
    `status`                  ENUM('at_origin','in_transit','at_stop',
                                   'at_destination','distress_active')
                              NOT NULL DEFAULT 'at_origin',
    `current_stop`            TINYINT UNSIGNED NOT NULL DEFAULT 1,
    `cargo_integrity`         TINYINT UNSIGNED NOT NULL DEFAULT 100,
    `cargo_secured`           BOOLEAN          NOT NULL DEFAULT FALSE,
    `seal_status`             ENUM('sealed','broken','not_applied')
                              NOT NULL DEFAULT 'not_applied',
    `seal_number`             VARCHAR(30)      DEFAULT NULL,
    `seal_broken_at`          INT UNSIGNED     DEFAULT NULL,
    `temp_monitoring_active`  BOOLEAN          NOT NULL DEFAULT FALSE,
    `current_temp_f`          DECIMAL(5,2)     DEFAULT NULL,
    `excursion_active`        BOOLEAN          NOT NULL DEFAULT FALSE,
    `excursion_start`         INT UNSIGNED     DEFAULT NULL,
    `excursion_total_mins`    SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    `reefer_operational`      BOOLEAN          NOT NULL DEFAULT TRUE,
    `welfare_rating`          TINYINT UNSIGNED DEFAULT NULL,
    `permit_number`           VARCHAR(30)      DEFAULT NULL,
    `route_violations`        TINYINT UNSIGNED NOT NULL DEFAULT 0,
    `weigh_station_stamped`   BOOLEAN          NOT NULL DEFAULT FALSE,
    `pre_trip_completed`      BOOLEAN          NOT NULL DEFAULT FALSE,
    `manifest_verified`       BOOLEAN          NOT NULL DEFAULT FALSE,
    `accepted_at`             INT UNSIGNED     NOT NULL,
    `window_expires_at`       INT UNSIGNED     NOT NULL,
    `window_reduction_secs`   INT UNSIGNED     NOT NULL DEFAULT 0,
    `departed_at`             INT UNSIGNED     DEFAULT NULL,
    `deposit_posted`          INT UNSIGNED     NOT NULL DEFAULT 0,
    `insurance_policy_id`     BIGINT UNSIGNED  DEFAULT NULL,
    `estimated_payout`        INT UNSIGNED     NOT NULL DEFAULT 0,
    `company_id`              BIGINT UNSIGNED  DEFAULT NULL,
    `convoy_id`               BIGINT UNSIGNED  DEFAULT NULL,
    INDEX `idx_citizenid`  (`citizenid`),
    INDEX `idx_load_id`    (`load_id`),
    INDEX `idx_company_id` (`company_id`),
    INDEX `idx_convoy_id`  (`convoy_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


CREATE TABLE IF NOT EXISTS `truck_bols` (
    `id`                      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `bol_number`              VARCHAR(20)      NOT NULL UNIQUE,
    `load_id`                 BIGINT UNSIGNED  NOT NULL,
    `citizenid`               VARCHAR(50)      NOT NULL,
    `driver_name`             VARCHAR(100)     NOT NULL,
    `company_id`              BIGINT UNSIGNED  DEFAULT NULL,
    `company_name`            VARCHAR(100)     DEFAULT NULL,
    `shipper_id`              VARCHAR(50)      NOT NULL,
    `shipper_name`            VARCHAR(100)     NOT NULL,
    `origin_label`            VARCHAR(100)     NOT NULL,
    `destination_label`       VARCHAR(100)     NOT NULL,
    `distance_miles`          DECIMAL(6,2)     NOT NULL,
    `cargo_type`              VARCHAR(50)      NOT NULL,
    `cargo_description`       TEXT             DEFAULT NULL,
    `weight_lbs`              INT UNSIGNED     NOT NULL,
    `tier`                    TINYINT UNSIGNED NOT NULL,
    `hazmat_class`            TINYINT UNSIGNED DEFAULT NULL,
    `placard_class`           VARCHAR(50)      DEFAULT NULL,
    `license_class`           VARCHAR(20)      DEFAULT NULL,
    `license_matched`         BOOLEAN          NOT NULL DEFAULT TRUE,
    `seal_number`             VARCHAR(30)      DEFAULT NULL,
    `seal_status`             ENUM('sealed','broken','not_applied',
                                   'delivered_intact')
                              NOT NULL DEFAULT 'not_applied',
    `temp_required_min`       TINYINT          DEFAULT NULL,
    `temp_required_max`       TINYINT          DEFAULT NULL,
    `temp_compliance`         ENUM('not_required','clean',
                                   'minor_excursion','significant_excursion')
                              DEFAULT 'not_required',
    `weigh_station_stamp`     BOOLEAN          NOT NULL DEFAULT FALSE,
    `manifest_verified`       BOOLEAN          NOT NULL DEFAULT FALSE,
    `pre_trip_completed`      BOOLEAN          NOT NULL DEFAULT FALSE,
    `welfare_final_rating`    TINYINT UNSIGNED DEFAULT NULL,
    `bol_status`              ENUM('active','delivered','rejected',
                                   'stolen','abandoned','expired','partial')
                              NOT NULL DEFAULT 'active',
    `item_in_inventory`       BOOLEAN          NOT NULL DEFAULT TRUE,
    `item_disposed_at`        INT UNSIGNED     DEFAULT NULL,
    `final_payout`            INT UNSIGNED     DEFAULT NULL,
    `payout_breakdown`        JSON             DEFAULT NULL,
    `deposit_returned`        BOOLEAN          NOT NULL DEFAULT FALSE,
    `is_leon`                 BOOLEAN          NOT NULL DEFAULT FALSE,
    `issued_at`               INT UNSIGNED     NOT NULL,
    `departed_at`             INT UNSIGNED     DEFAULT NULL,
    `delivered_at`            INT UNSIGNED     DEFAULT NULL,
    INDEX `idx_citizenid`  (`citizenid`),
    INDEX `idx_bol_status` (`bol_status`),
    INDEX `idx_shipper_id` (`shipper_id`),
    INDEX `idx_issued_at`  (`issued_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


CREATE TABLE IF NOT EXISTS `truck_bol_events` (
    `id`                      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `bol_id`                  BIGINT UNSIGNED  NOT NULL,
    `bol_number`              VARCHAR(20)      NOT NULL,
    `citizenid`               VARCHAR(50)      NOT NULL,
    `event_type`              ENUM(
        'load_accepted','departed_origin','seal_applied','seal_broken',
        'cargo_secured','cargo_shift','cargo_shift_resolved',
        'integrity_event','temp_excursion_start','temp_excursion_end',
        'reefer_failure','reefer_restored','welfare_event',
        'weigh_station_stamped','weigh_station_violation',
        'route_violation','stop_completed','distress_signal',
        'robbery_initiated','robbery_completed','load_delivered',
        'load_rejected','load_abandoned','load_stolen',
        'window_expired','window_reduced','transfer_completed',
        'cdl_mismatch_noted','manifest_discrepancy'
    ) NOT NULL,
    `event_data`              JSON             DEFAULT NULL,
    `coords`                  JSON             DEFAULT NULL,
    `occurred_at`             INT UNSIGNED     NOT NULL,
    INDEX `idx_bol_id`      (`bol_id`),
    INDEX `idx_event_type`  (`event_type`),
    INDEX `idx_occurred_at` (`occurred_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


CREATE TABLE IF NOT EXISTS `truck_supplier_contracts` (
    `id`                      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `client_id`               VARCHAR(50)      NOT NULL,
    `client_name`             VARCHAR(100)     NOT NULL,
    `region`                  ENUM('los_santos','sandy_shores',
                                   'paleto','grapeseed')
                              NOT NULL,
    `required_item`           VARCHAR(50)      NOT NULL,
    `required_quantity`       INT UNSIGNED     NOT NULL,
    `destination_label`       VARCHAR(100)     NOT NULL,
    `destination_coords`      JSON             NOT NULL,
    `window_hours`            TINYINT UNSIGNED NOT NULL DEFAULT 4,
    `base_payout`             INT UNSIGNED     NOT NULL,
    `partial_allowed`         BOOLEAN          NOT NULL DEFAULT TRUE,
    `contract_status`         ENUM('available','accepted',
                                   'fulfilled','expired')
                              NOT NULL DEFAULT 'available',
    `accepted_by`             VARCHAR(50)      DEFAULT NULL,
    `accepted_at`             INT UNSIGNED     DEFAULT NULL,
    `window_expires_at`       INT UNSIGNED     DEFAULT NULL,
    `quantity_delivered`      INT UNSIGNED     NOT NULL DEFAULT 0,
    `posted_at`               INT UNSIGNED     NOT NULL,
    `expires_at`              INT UNSIGNED     NOT NULL,
    `is_leon`                 BOOLEAN          NOT NULL DEFAULT FALSE,
    INDEX `idx_contract_status` (`contract_status`),
    INDEX `idx_region`         (`region`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


CREATE TABLE IF NOT EXISTS `truck_open_contracts` (
    `id`                      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `client_id`               VARCHAR(50)      NOT NULL,
    `client_name`             VARCHAR(100)     NOT NULL,
    `cargo_type`              VARCHAR(50)      NOT NULL,
    `total_quantity_needed`   INT UNSIGNED     NOT NULL,
    `quantity_fulfilled`      INT UNSIGNED     NOT NULL DEFAULT 0,
    `total_payout_pool`       INT UNSIGNED     NOT NULL,
    `min_contribution_pct`    DECIMAL(4,2)     NOT NULL DEFAULT 0.10,
    `contract_status`         ENUM('active','fulfilled','expired')
                              NOT NULL DEFAULT 'active',
    `posted_at`               INT UNSIGNED     NOT NULL,
    `expires_at`              INT UNSIGNED     NOT NULL,
    `fulfilled_at`            INT UNSIGNED     DEFAULT NULL,
    INDEX `idx_contract_status` (`contract_status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


CREATE TABLE IF NOT EXISTS `truck_open_contract_contributions` (
    `id`                      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `contract_id`             BIGINT UNSIGNED  NOT NULL,
    `citizenid`               VARCHAR(50)      NOT NULL,
    `company_id`              BIGINT UNSIGNED  DEFAULT NULL,
    `quantity_contributed`    INT UNSIGNED     NOT NULL DEFAULT 0,
    `contribution_pct`        DECIMAL(6,4)     NOT NULL DEFAULT 0.0000,
    `payout_earned`           INT UNSIGNED     DEFAULT NULL,
    `payout_issued`           BOOLEAN          NOT NULL DEFAULT FALSE,
    `last_contribution_at`    INT UNSIGNED     DEFAULT NULL,
    UNIQUE KEY `uq_contract_driver` (`contract_id`, `citizenid`),
    INDEX `idx_citizenid` (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


CREATE TABLE IF NOT EXISTS `truck_routes` (
    `id`                      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `route_name`              VARCHAR(100)     NOT NULL,
    `shipper_id`              VARCHAR(50)      NOT NULL,
    `region`                  ENUM('los_santos','sandy_shores',
                                   'paleto','grapeseed')
                              NOT NULL,
    `tier`                    TINYINT UNSIGNED NOT NULL,
    `cargo_type`              VARCHAR(50)      NOT NULL,
    `stop_count`              TINYINT UNSIGNED NOT NULL,
    `stops`                   JSON             NOT NULL,
    `total_distance_miles`    DECIMAL(6,2)     NOT NULL,
    `required_license`        ENUM('none','class_b','class_a')
                              NOT NULL DEFAULT 'none',
    `base_payout_rental`      INT UNSIGNED     NOT NULL,
    `base_payout_owner_op`    INT UNSIGNED     NOT NULL,
    `multi_stop_premium_pct`  DECIMAL(4,2)     NOT NULL,
    `deposit_amount`          INT UNSIGNED     NOT NULL,
    `window_minutes`          SMALLINT UNSIGNED NOT NULL,
    `route_status`            ENUM('available','accepted',
                                   'completed','expired')
                              NOT NULL DEFAULT 'available',
    `accepted_by`             VARCHAR(50)      DEFAULT NULL,
    `accepted_at`             INT UNSIGNED     DEFAULT NULL,
    `posted_at`               INT UNSIGNED     NOT NULL,
    `expires_at`              INT UNSIGNED     NOT NULL,
    INDEX `idx_region`       (`region`),
    INDEX `idx_route_status` (`route_status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


-- ─────────────────────────────────────────────
-- 3. FINANCIAL
-- ─────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS `truck_deposits` (
    `id`                      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `bol_id`                  BIGINT UNSIGNED  NOT NULL,
    `bol_number`              VARCHAR(20)      NOT NULL,
    `citizenid`               VARCHAR(50)      NOT NULL,
    `amount`                  INT UNSIGNED     NOT NULL,
    `tier`                    TINYINT UNSIGNED NOT NULL,
    `deposit_type`            ENUM('flat','percentage')
                              NOT NULL DEFAULT 'percentage',
    `status`                  ENUM('held','returned','forfeited')
                              NOT NULL DEFAULT 'held',
    `resolved_at`             INT UNSIGNED     DEFAULT NULL,
    `posted_at`               INT UNSIGNED     NOT NULL,
    INDEX `idx_citizenid` (`citizenid`),
    INDEX `idx_bol_id`    (`bol_id`),
    INDEX `idx_status`    (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


CREATE TABLE IF NOT EXISTS `truck_insurance_policies` (
    `id`                      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `citizenid`               VARCHAR(50)      NOT NULL,
    `policy_type`             ENUM('single_load','day','week')
                              NOT NULL,
    `tier_coverage`           TINYINT UNSIGNED NOT NULL DEFAULT 0,
    `premium_paid`            INT UNSIGNED     NOT NULL,
    `status`                  ENUM('active','expired','used')
                              NOT NULL DEFAULT 'active',
    `valid_from`              INT UNSIGNED     NOT NULL,
    `valid_until`             INT UNSIGNED     DEFAULT NULL,
    `bound_bol_id`            BIGINT UNSIGNED  DEFAULT NULL,
    `purchased_at`            INT UNSIGNED     NOT NULL,
    INDEX `idx_citizenid`   (`citizenid`),
    INDEX `idx_status`      (`status`),
    INDEX `idx_valid_until` (`valid_until`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


CREATE TABLE IF NOT EXISTS `truck_insurance_claims` (
    `id`                      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `citizenid`               VARCHAR(50)      NOT NULL,
    `policy_id`               BIGINT UNSIGNED  NOT NULL,
    `bol_id`                  BIGINT UNSIGNED  NOT NULL,
    `bol_number`              VARCHAR(20)      NOT NULL,
    `claim_type`              ENUM('theft','abandonment')
                              NOT NULL,
    `deposit_amount`          INT UNSIGNED     NOT NULL,
    `premium_allocated`       INT UNSIGNED     NOT NULL,
    `claim_amount`            INT UNSIGNED     NOT NULL,
    `status`                  ENUM('pending','approved','paid','denied')
                              NOT NULL DEFAULT 'pending',
    `payout_at`               INT UNSIGNED     DEFAULT NULL,
    `filed_at`                INT UNSIGNED     NOT NULL,
    `resolved_at`             INT UNSIGNED     DEFAULT NULL,
    INDEX `idx_citizenid`   (`citizenid`),
    INDEX `idx_bol_number`  (`bol_number`),
    INDEX `idx_status`      (`status`),
    INDEX `idx_payout_at`   (`payout_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


-- ─────────────────────────────────────────────
-- 4. REPUTATION
-- ─────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS `truck_driver_reputation_log` (
    `id`                      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `driver_id`               BIGINT UNSIGNED  NOT NULL,
    `citizenid`               VARCHAR(50)      NOT NULL,
    `change_type`             VARCHAR(50)      NOT NULL,
    `points_before`           SMALLINT UNSIGNED NOT NULL,
    `points_change`           SMALLINT         NOT NULL,
    `points_after`            SMALLINT UNSIGNED NOT NULL,
    `tier_before`             VARCHAR(20)      DEFAULT NULL,
    `tier_after`              VARCHAR(20)      DEFAULT NULL,
    `bol_id`                  BIGINT UNSIGNED  DEFAULT NULL,
    `bol_number`              VARCHAR(20)      DEFAULT NULL,
    `tier_of_load`            TINYINT UNSIGNED DEFAULT NULL,
    `occurred_at`             INT UNSIGNED     NOT NULL,
    INDEX `idx_citizenid`   (`citizenid`),
    INDEX `idx_occurred_at` (`occurred_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


CREATE TABLE IF NOT EXISTS `truck_shipper_reputation` (
    `id`                      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `driver_id`               BIGINT UNSIGNED  NOT NULL,
    `citizenid`               VARCHAR(50)      NOT NULL,
    `shipper_id`              VARCHAR(50)      NOT NULL,
    `points`                  SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    `tier`                    ENUM('unknown','familiar','established',
                                   'trusted','preferred','blacklisted')
                              NOT NULL DEFAULT 'unknown',
    `deliveries_completed`    SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    `current_clean_streak`    TINYINT UNSIGNED NOT NULL DEFAULT 0,
    `last_delivery_at`        INT UNSIGNED     DEFAULT NULL,
    `preferred_decay_warned`  BOOLEAN          NOT NULL DEFAULT FALSE,
    `blacklisted_at`          INT UNSIGNED     DEFAULT NULL,
    `reinstatement_eligible`  INT UNSIGNED     DEFAULT NULL,
    UNIQUE KEY `uq_driver_shipper` (`driver_id`, `shipper_id`),
    INDEX `idx_citizenid`  (`citizenid`),
    INDEX `idx_shipper_id` (`shipper_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


CREATE TABLE IF NOT EXISTS `truck_shipper_reputation_log` (
    `id`                      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `driver_id`               BIGINT UNSIGNED  NOT NULL,
    `citizenid`               VARCHAR(50)      NOT NULL,
    `shipper_id`              VARCHAR(50)      NOT NULL,
    `change_type`             VARCHAR(50)      NOT NULL,
    `points_before`           SMALLINT UNSIGNED NOT NULL,
    `points_change`           SMALLINT         NOT NULL,
    `points_after`            SMALLINT UNSIGNED NOT NULL,
    `tier_before`             VARCHAR(20)      DEFAULT NULL,
    `tier_after`              VARCHAR(20)      DEFAULT NULL,
    `bol_id`                  BIGINT UNSIGNED  DEFAULT NULL,
    `occurred_at`             INT UNSIGNED     NOT NULL,
    INDEX `idx_citizenid`  (`citizenid`),
    INDEX `idx_shipper_id` (`shipper_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


-- ─────────────────────────────────────────────
-- 5. COMPANY
-- ─────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS `truck_companies` (
    `id`                      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `company_name`            VARCHAR(100)     NOT NULL UNIQUE,
    `owner_citizenid`         VARCHAR(50)      NOT NULL,
    `dispatcher_citizenid`    VARCHAR(50)      DEFAULT NULL,
    `founded_at`              INT UNSIGNED     NOT NULL,
    INDEX `idx_owner` (`owner_citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


CREATE TABLE IF NOT EXISTS `truck_company_members` (
    `id`                      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `company_id`              BIGINT UNSIGNED  NOT NULL,
    `citizenid`               VARCHAR(50)      NOT NULL,
    `role`                    ENUM('owner','driver')
                              NOT NULL DEFAULT 'driver',
    `joined_at`               INT UNSIGNED     NOT NULL,
    UNIQUE KEY `uq_company_driver` (`company_id`, `citizenid`),
    INDEX `idx_citizenid`  (`citizenid`),
    INDEX `idx_company_id` (`company_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


CREATE TABLE IF NOT EXISTS `truck_convoys` (
    `id`                      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `initiated_by`            VARCHAR(50)      NOT NULL,
    `company_id`              BIGINT UNSIGNED  DEFAULT NULL,
    `convoy_type`             ENUM('open','invite','company')
                              NOT NULL,
    `status`                  ENUM('forming','active','completed','disbanded')
                              NOT NULL DEFAULT 'forming',
    `vehicle_count`           TINYINT UNSIGNED NOT NULL DEFAULT 1,
    `started_at`              INT UNSIGNED     DEFAULT NULL,
    `completed_at`            INT UNSIGNED     DEFAULT NULL,
    `created_at`              INT UNSIGNED     NOT NULL,
    INDEX `idx_status`       (`status`),
    INDEX `idx_initiated_by` (`initiated_by`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


-- ─────────────────────────────────────────────
-- 6. CARGO TRACKING
-- ─────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS `truck_integrity_events` (
    `id`                      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `bol_id`                  BIGINT UNSIGNED  NOT NULL,
    `citizenid`               VARCHAR(50)      NOT NULL,
    `event_cause`             ENUM('collision_minor','collision_moderate',
                                   'collision_major','rollover',
                                   'sharp_cornering','off_road',
                                   'cargo_shift','liquid_agitation',
                                   'spill_damage','temperature_damage')
                              NOT NULL,
    `integrity_before`        TINYINT UNSIGNED NOT NULL,
    `integrity_loss`          TINYINT UNSIGNED NOT NULL,
    `integrity_after`         TINYINT UNSIGNED NOT NULL,
    `vehicle_speed`           TINYINT UNSIGNED DEFAULT NULL,
    `vehicle_coords`          JSON             DEFAULT NULL,
    `occurred_at`             INT UNSIGNED     NOT NULL,
    INDEX `idx_bol_id`     (`bol_id`),
    INDEX `idx_citizenid`  (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


CREATE TABLE IF NOT EXISTS `truck_weigh_station_records` (
    `id`                      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `bol_id`                  BIGINT UNSIGNED  NOT NULL,
    `citizenid`               VARCHAR(50)      NOT NULL,
    `station_id`              VARCHAR(50)      NOT NULL,
    `station_label`           VARCHAR(100)     NOT NULL,
    `station_region`          ENUM('los_santos','sandy_shores',
                                   'paleto','grapeseed')
                              NOT NULL,
    `inspection_result`       ENUM('passed','warning',
                                   'violation','impound')
                              NOT NULL DEFAULT 'passed',
    `stamp_issued`            BOOLEAN          NOT NULL DEFAULT FALSE,
    `violations_noted`        JSON             DEFAULT NULL,
    `inspected_at`            INT UNSIGNED     NOT NULL,
    INDEX `idx_bol_id`    (`bol_id`),
    INDEX `idx_citizenid` (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


CREATE TABLE IF NOT EXISTS `truck_livestock_welfare_logs` (
    `id`                      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `bol_id`                  BIGINT UNSIGNED  NOT NULL,
    `citizenid`               VARCHAR(50)      NOT NULL,
    `welfare_rating`          TINYINT UNSIGNED NOT NULL,
    `event_type`              ENUM('sample','hard_brake','sharp_corner',
                                   'collision','off_road','heat_exposure',
                                   'rest_stop_quick','rest_stop_water',
                                   'rest_stop_full','time_decay','recovery')
                              NOT NULL DEFAULT 'sample',
    `rating_change`           TINYINT          NOT NULL DEFAULT 0,
    `occurred_at`             INT UNSIGNED     NOT NULL,
    INDEX `idx_bol_id` (`bol_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


-- ─────────────────────────────────────────────
-- 7. SYSTEM
-- ─────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS `truck_board_state` (
    `id`                      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `region`                  ENUM('los_santos','sandy_shores',
                                   'paleto','grapeseed','server_wide')
                              NOT NULL UNIQUE,
    `last_refresh_at`         INT UNSIGNED     DEFAULT NULL,
    `next_refresh_at`         INT UNSIGNED     DEFAULT NULL,
    `refresh_interval_secs`   SMALLINT UNSIGNED NOT NULL DEFAULT 7200,
    `available_t0`            TINYINT UNSIGNED NOT NULL DEFAULT 0,
    `available_t1`            TINYINT UNSIGNED NOT NULL DEFAULT 0,
    `available_t2`            TINYINT UNSIGNED NOT NULL DEFAULT 0,
    `available_t3`            TINYINT UNSIGNED NOT NULL DEFAULT 0,
    `surge_active_count`      TINYINT UNSIGNED NOT NULL DEFAULT 0,
    `updated_at`              INT UNSIGNED     NOT NULL,
    INDEX `idx_region` (`region`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


CREATE TABLE IF NOT EXISTS `truck_surge_events` (
    `id`                      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `region`                  ENUM('los_santos','sandy_shores',
                                   'paleto','grapeseed','server_wide')
                              NOT NULL,
    `surge_type`              ENUM('open_contract_progress','weather_event',
                                   'robbery_corridor','cold_chain_failure_streak',
                                   'peak_population','shipper_backlog','manual')
                              NOT NULL,
    `cargo_type_filter`       VARCHAR(50)      DEFAULT NULL,
    `shipper_filter`          VARCHAR(50)      DEFAULT NULL,
    `surge_percentage`        TINYINT UNSIGNED NOT NULL,
    `trigger_data`            JSON             DEFAULT NULL,
    `status`                  ENUM('active','expired','cancelled')
                              NOT NULL DEFAULT 'active',
    `started_at`              INT UNSIGNED     NOT NULL,
    `expires_at`              INT UNSIGNED     NOT NULL,
    `ended_at`                INT UNSIGNED     DEFAULT NULL,
    INDEX `idx_status`     (`status`),
    INDEX `idx_expires_at` (`expires_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


CREATE TABLE IF NOT EXISTS `truck_webhook_log` (
    `id`                      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    `webhook_channel`         ENUM('insurance','leon','military',
                                   'claims','surge','admin')
                              NOT NULL,
    `event_type`              VARCHAR(100)     NOT NULL,
    `citizenid`               VARCHAR(50)      DEFAULT NULL,
    `bol_number`              VARCHAR(20)      DEFAULT NULL,
    `payload`                 JSON             NOT NULL,
    `delivered`               BOOLEAN          NOT NULL DEFAULT FALSE,
    `delivery_attempts`       TINYINT UNSIGNED NOT NULL DEFAULT 0,
    `delivered_at`            INT UNSIGNED     DEFAULT NULL,
    `created_at`              INT UNSIGNED     NOT NULL,
    INDEX `idx_delivered`   (`delivered`),
    INDEX `idx_created_at`  (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


-- ═══════════════════════════════════════════════════════════════
-- SEED DATA — Board State Regions
-- ═══════════════════════════════════════════════════════════════
-- Pre-populate board_state rows for each region so the refresh
-- system can UPDATE rather than INSERT on first cycle.

INSERT IGNORE INTO `truck_board_state` (`region`, `updated_at`)
VALUES
    ('los_santos',   UNIX_TIMESTAMP()),
    ('sandy_shores', UNIX_TIMESTAMP()),
    ('paleto',       UNIX_TIMESTAMP()),
    ('grapeseed',    UNIX_TIMESTAMP()),
    ('server_wide',  UNIX_TIMESTAMP());


-- ═══════════════════════════════════════════════════════════════
-- MAINTENANCE QUERIES (Section 4.3)
-- Run on server restart and every 15 minutes via scheduled event.
-- ═══════════════════════════════════════════════════════════════

-- Expire stale reservations (3-minute hold expired)
-- UPDATE truck_loads
-- SET board_status = 'available', reserved_by = NULL, reserved_until = NULL
-- WHERE board_status = 'reserved' AND reserved_until < UNIX_TIMESTAMP();

-- Expire board loads
-- UPDATE truck_loads SET board_status = 'expired'
-- WHERE board_status = 'available' AND expires_at < UNIX_TIMESTAMP();

-- Expire surges
-- UPDATE truck_surge_events SET status = 'expired', ended_at = UNIX_TIMESTAMP()
-- WHERE status = 'active' AND expires_at < UNIX_TIMESTAMP();

-- Expire insurance policies
-- UPDATE truck_insurance_policies SET status = 'expired'
-- WHERE status = 'active' AND valid_until < UNIX_TIMESTAMP();

-- Issue pending claim payouts
-- SELECT ic.id, ic.citizenid, ic.claim_amount FROM truck_insurance_claims ic
-- WHERE ic.status = 'approved' AND ic.payout_at <= UNIX_TIMESTAMP();

-- Lift suspensions
-- UPDATE truck_drivers
-- SET reputation_tier = 'restricted', reputation_score = 1, suspended_until = NULL
-- WHERE reputation_tier = 'suspended' AND suspended_until < UNIX_TIMESTAMP();

-- Preferred tier decay (14 days inactive)
-- UPDATE truck_shipper_reputation
-- SET tier = 'trusted', points = LEAST(points, 699)
-- WHERE tier = 'preferred'
--   AND last_delivery_at < (UNIX_TIMESTAMP() - 1209600)
--   AND preferred_decay_warned = TRUE;
