--[[
    Free Trucking — FiveM QBX Trucking Script
    Resource Manifest (FiveM Cerulean)

    Stack: QBox / ox_lib / ox_inventory / oxmysql
    NUI:   Svelte (nui/dist/index.html)
]]

fx_version 'cerulean'
game 'gta5'

name 'free-trucking'
author 'Free Trucking Contributors'
description 'Comprehensive trucking and freight hauling script for QBX'
version '1.0.0'
lua54 'yes'

-- ─────────────────────────────────────────────
-- DEPENDENCIES
-- ─────────────────────────────────────────────

dependencies {
    'oxmysql',
    'ox_lib',
    'ox_inventory',
    'qbx_core',
}

-- ─────────────────────────────────────────────
-- SHARED SCRIPTS (loaded before server/client)
-- ─────────────────────────────────────────────

shared_scripts {
    '@ox_lib/init.lua',
    'shared/utils.lua',
}

-- ─────────────────────────────────────────────
-- SERVER SCRIPTS
-- ─────────────────────────────────────────────

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'config/config.lua',
    'config/economy.lua',
    'config/shippers.lua',
    'config/cargo.lua',
    'config/board.lua',
    'config/vehicles.lua',
    'config/cdl.lua',
    'config/leon.lua',
    'config/explosions.lua',
    'server/main.lua',
    'server/database.lua',
    'server/loads.lua',
    'server/missions.lua',
    'server/payout.lua',
    'server/bol.lua',
    'server/reputation.lua',
    'server/insurance.lua',
    'server/company.lua',
    'server/convoy.lua',
    'server/cdl.lua',
    'server/leon.lua',
    'server/military.lua',
    'server/explosions.lua',
    'server/admin.lua',
    'server/temperature.lua',
    'server/webhooks.lua',
    'server/exports.lua',
}

-- ─────────────────────────────────────────────
-- CLIENT SCRIPTS
-- ─────────────────────────────────────────────

client_scripts {
    'config/config.lua',
    'config/economy.lua',
    'config/shippers.lua',
    'config/cargo.lua',
    'config/board.lua',
    'config/vehicles.lua',
    'config/cdl.lua',
    'config/leon.lua',
    'config/explosions.lua',
    'client/main.lua',
    'client/interactions.lua',
    'client/missions.lua',
    'client/vehicles.lua',
    'client/bol.lua',
    'client/seals.lua',
    'client/temperature.lua',
    'client/livestock.lua',
    'client/securing.lua',
    'client/weighstation.lua',
    'client/cdl.lua',
    'client/company.lua',
    'client/convoy.lua',
    'client/leon.lua',
    'client/military.lua',
    'client/tanker.lua',
    'client/hazmat.lua',
    'client/explosions.lua',
    'client/hud.lua',
    'client/admin.lua',
}

-- ─────────────────────────────────────────────
-- FILES (accessible to both sides, NUI assets)
-- ─────────────────────────────────────────────

files {
    'locales/*.json',
    'nui/dist/**/*',
}

-- ─────────────────────────────────────────────
-- NUI
-- ─────────────────────────────────────────────

ui_page 'nui/dist/index.html'

-- ─────────────────────────────────────────────
-- LOCALE
-- ─────────────────────────────────────────────

ox_libs {
    'locale',
}
