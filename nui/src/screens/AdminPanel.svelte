<script>
  import { createEventDispatcher, onMount } from 'svelte';
  import { adminData } from '../lib/stores.js';
  import { fetchNUI } from '../lib/nui.js';
  import TabBar from '../components/TabBar.svelte';
  import StatusBadge from '../components/StatusBadge.svelte';

  const dispatch = createEventDispatcher();

  let activeTab = 'dashboard';

  // --- Player lookup ---
  let playerQuery = '';
  let playerSearching = false;
  let repAdjustValue = '';
  let suspendDuration = '';
  let suspendReason = '';
  let showSuspendForm = false;

  // --- Economy ---
  let multiplierValue = 1.0;
  let surgeRegion = 'los_santos';
  let surgePercentage = '';
  let surgeDuration = '';
  let surgeCargoFilter = 'all';

  // --- Insurance deny ---
  let denyReasonMap = {};

  // --- Confirmation dialog ---
  let showConfirmDialog = false;
  let confirmTitle = '';
  let confirmMessage = '';
  let confirmCallback = null;

  const tabs = [
    { id: 'dashboard', label: 'Dashboard' },
    { id: 'players', label: 'Players' },
    { id: 'economy', label: 'Economy' },
    { id: 'loads', label: 'Loads' },
    { id: 'insurance', label: 'Insurance' },
  ];

  const regionOptions = [
    { id: 'los_santos', label: 'Chicago (LS)' },
    { id: 'sandy_shores', label: 'Gary (SS)' },
    { id: 'paleto', label: 'Wisconsin (Paleto)' },
    { id: 'grapeseed', label: 'W. Michigan (GS)' },
  ];

  const cargoFilterOptions = [
    { id: 'all', label: 'All Cargo' },
    { id: 'general', label: 'General' },
    { id: 'refrigerated', label: 'Refrigerated' },
    { id: 'hazmat', label: 'HAZMAT' },
    { id: 'oversized', label: 'Oversized' },
    { id: 'livestock', label: 'Livestock' },
  ];

  function handleTabChange(e) {
    activeTab = e.detail.tab;
  }

  function navigateTo(screen, data = null) {
    dispatch('navigate', { screen, data });
  }

  function formatDollar(n) {
    if (n == null) return '$0';
    return '$' + Number(n).toLocaleString('en-US');
  }

  function formatTime(seconds) {
    if (!seconds) return '--';
    const h = Math.floor(seconds / 3600);
    const m = Math.floor((seconds % 3600) / 60);
    if (h > 0) return `${h}h ${m}m`;
    return `${m}m`;
  }

  // --- Confirmation dialog helpers ---
  function requestConfirm(title, message, callback) {
    confirmTitle = title;
    confirmMessage = message;
    confirmCallback = callback;
    showConfirmDialog = true;
  }

  function handleConfirm() {
    if (confirmCallback) confirmCallback();
    showConfirmDialog = false;
    confirmCallback = null;
  }

  function handleCancelConfirm() {
    showConfirmDialog = false;
    confirmCallback = null;
  }

  // --- Actions ---

  async function refreshAllData() {
    await fetchNUI('trucking:adminRefreshData');
  }

  async function lookupPlayer() {
    if (!playerQuery.trim()) return;
    playerSearching = true;
    await fetchNUI('trucking:adminLookupPlayer', { query: playerQuery.trim() });
    playerSearching = false;
  }

  function handlePlayerKeydown(e) {
    if (e.key === 'Enter') lookupPlayer();
  }

  async function adjustReputation() {
    const profile = $adminData.playerProfile;
    if (!profile || !repAdjustValue) return;
    const newScore = Number(repAdjustValue);
    if (isNaN(newScore) || newScore < 0 || newScore > 1000) return;
    requestConfirm(
      'Adjust Reputation',
      `Set ${profile.name || profile.citizenid}'s reputation to ${newScore}?`,
      async () => {
        await fetchNUI('trucking:adminAdjustReputation', {
          citizenid: profile.citizenid,
          newScore,
        });
        repAdjustValue = '';
        await fetchNUI('trucking:adminLookupPlayer', { query: profile.citizenid });
      }
    );
  }

  async function suspendDriver() {
    const profile = $adminData.playerProfile;
    if (!profile || !suspendDuration || !suspendReason.trim()) return;
    const duration = Number(suspendDuration);
    if (isNaN(duration) || duration <= 0) return;
    requestConfirm(
      'Suspend Driver',
      `Suspend ${profile.name || profile.citizenid} for ${duration} hours? Reason: "${suspendReason.trim()}"`,
      async () => {
        await fetchNUI('trucking:adminSuspendDriver', {
          citizenid: profile.citizenid,
          duration,
          reason: suspendReason.trim(),
        });
        suspendDuration = '';
        suspendReason = '';
        showSuspendForm = false;
        await fetchNUI('trucking:adminLookupPlayer', { query: profile.citizenid });
      }
    );
  }

  async function unsuspendDriver() {
    const profile = $adminData.playerProfile;
    if (!profile) return;
    requestConfirm(
      'Unsuspend Driver',
      `Remove suspension from ${profile.name || profile.citizenid}?`,
      async () => {
        await fetchNUI('trucking:adminUnsuspendDriver', {
          citizenid: profile.citizenid,
        });
        await fetchNUI('trucking:adminLookupPlayer', { query: profile.citizenid });
      }
    );
  }

  async function forceComplete(loadId) {
    requestConfirm(
      'Force Complete',
      `Force complete load ${loadId}? The driver will receive full payout.`,
      async () => {
        await fetchNUI('trucking:adminForceComplete', { loadId });
      }
    );
  }

  async function forceAbandon(loadId) {
    requestConfirm(
      'Force Abandon',
      `Force abandon load ${loadId}? The driver will lose their deposit.`,
      async () => {
        await fetchNUI('trucking:adminForceAbandon', { loadId });
      }
    );
  }

  async function setMultiplier() {
    const val = Number(multiplierValue);
    if (isNaN(val) || val < 0.1 || val > 5.0) return;
    requestConfirm(
      'Set Multiplier',
      `Set the global economy multiplier to ${val.toFixed(1)}x?`,
      async () => {
        await fetchNUI('trucking:adminSetMultiplier', { multiplier: val });
      }
    );
  }

  async function createSurge() {
    const pct = Number(surgePercentage);
    const dur = Number(surgeDuration);
    if (isNaN(pct) || pct <= 0 || isNaN(dur) || dur <= 0) return;
    requestConfirm(
      'Create Surge',
      `Create a ${pct}% surge in ${regionOptions.find(r => r.id === surgeRegion)?.label || surgeRegion} for ${dur} minutes?`,
      async () => {
        await fetchNUI('trucking:adminCreateSurge', {
          region: surgeRegion,
          percentage: pct,
          duration: dur,
          cargoFilter: surgeCargoFilter === 'all' ? null : surgeCargoFilter,
        });
        surgePercentage = '';
        surgeDuration = '';
      }
    );
  }

  async function cancelSurge(surgeId) {
    requestConfirm(
      'Cancel Surge',
      `Cancel surge ${surgeId}?`,
      async () => {
        await fetchNUI('trucking:adminCancelSurge', { surgeId });
      }
    );
  }

  async function refreshBoard(region) {
    await fetchNUI('trucking:adminRefreshBoard', { region });
  }

  async function approveClaim(claimId) {
    requestConfirm(
      'Approve Claim',
      `Approve insurance claim ${claimId}?`,
      async () => {
        await fetchNUI('trucking:adminApproveClaim', { claimId });
      }
    );
  }

  async function denyClaim(claimId) {
    const reason = (denyReasonMap[claimId] || '').trim();
    if (!reason) return;
    requestConfirm(
      'Deny Claim',
      `Deny insurance claim ${claimId}? Reason: "${reason}"`,
      async () => {
        await fetchNUI('trucking:adminDenyClaim', { claimId, reason });
        denyReasonMap[claimId] = '';
      }
    );
  }

  // Sync multiplier slider with store
  $: admin = $adminData;
  $: stats = admin.stats;
  $: activeLoads = Array.isArray(admin.activeLoads) ? admin.activeLoads : [];
  $: activeSurges = Array.isArray(admin.activeSurges) ? admin.activeSurges : [];
  $: boardState = admin.boardState || {};
  $: economySettings = admin.economySettings || { multiplier: 1.0 };
  $: pendingClaims = Array.isArray(admin.pendingClaims) ? admin.pendingClaims : [];
  $: playerProfile = admin.playerProfile;

  // Keep multiplier slider in sync when economy settings update
  $: if (economySettings.multiplier != null) {
    multiplierValue = economySettings.multiplier;
  }

  $: tabsWithCounts = tabs.map(t => {
    if (t.id === 'loads') return { ...t, count: activeLoads.length };
    if (t.id === 'insurance') return { ...t, count: pendingClaims.length };
    if (t.id === 'economy') return { ...t, count: activeSurges.length };
    return t;
  });

  onMount(() => {
    refreshAllData();
  });
</script>

<div class="admin-screen">
  <div class="admin-header">
    <h2 class="admin-title">Admin Panel</h2>
    <button class="btn btn-secondary btn-sm" on:click={refreshAllData}>
      Refresh All
    </button>
  </div>

  <TabBar tabs={tabsWithCounts} {activeTab} on:tabChange={handleTabChange} />

  <!-- ==================== DASHBOARD TAB ==================== -->
  {#if activeTab === 'dashboard'}
    <div class="tab-content">
      {#if stats}
        <div class="stat-grid">
          <div class="stat-card">
            <span class="stat-card-label">Active Loads</span>
            <span class="stat-card-value mono">{stats.activeLoads ?? 0}</span>
          </div>
          <div class="stat-card">
            <span class="stat-card-label">Completed Today</span>
            <span class="stat-card-value mono">{stats.completedToday ?? 0}</span>
          </div>
          <div class="stat-card">
            <span class="stat-card-label">Payouts Today</span>
            <span class="stat-card-value mono">{formatDollar(stats.payoutsToday)}</span>
          </div>
          <div class="stat-card">
            <span class="stat-card-label">Pending Claims</span>
            <span class="stat-card-value mono">{stats.pendingClaims ?? 0}</span>
          </div>
          <div class="stat-card">
            <span class="stat-card-label">Active Surges</span>
            <span class="stat-card-value mono">{stats.activeSurges ?? 0}</span>
          </div>
          <div class="stat-card">
            <span class="stat-card-label">Server Multiplier</span>
            <span class="stat-card-value mono text-orange">{(stats.serverMultiplier ?? 1.0).toFixed(1)}x</span>
          </div>
        </div>
      {:else}
        <div class="empty-state">
          <span class="empty-text text-muted">Loading dashboard statistics...</span>
        </div>
      {/if}
    </div>
  {/if}

  <!-- ==================== PLAYERS TAB ==================== -->
  {#if activeTab === 'players'}
    <div class="tab-content">
      <!-- Search -->
      <div class="search-bar">
        <input
          type="text"
          class="input-field"
          placeholder="Search by Citizen ID or name..."
          bind:value={playerQuery}
          on:keydown={handlePlayerKeydown}
        />
        <button
          class="btn btn-primary btn-sm"
          on:click={lookupPlayer}
          disabled={playerSearching || !playerQuery.trim()}
        >
          {playerSearching ? 'Searching...' : 'Search'}
        </button>
      </div>

      <!-- Player Profile -->
      {#if playerProfile}
        <div class="card player-profile-card">
          <div class="card-header">
            <h3 class="card-title">{playerProfile.name || 'Unknown'}</h3>
            {#if playerProfile.suspendedUntil}
              <StatusBadge status="suspended" />
            {:else}
              <StatusBadge status="active" />
            {/if}
          </div>
          <div class="card-body">
            <div class="detail-row">
              <span class="detail-label">Citizen ID</span>
              <span class="detail-value mono">{playerProfile.citizenid}</span>
            </div>
            <div class="detail-row">
              <span class="detail-label">Reputation</span>
              <span class="detail-value mono">{playerProfile.reputationScore ?? '--'}</span>
            </div>
            <div class="detail-row">
              <span class="detail-label">Reputation Tier</span>
              <span class="detail-value">{playerProfile.reputationTier || '--'}</span>
            </div>
            <div class="detail-row">
              <span class="detail-label">Total Deliveries</span>
              <span class="detail-value mono">{playerProfile.totalLoadsCompleted ?? 0}</span>
            </div>
            <div class="detail-row">
              <span class="detail-label">Total Earnings</span>
              <span class="detail-value mono">{formatDollar(playerProfile.totalEarnings)}</span>
            </div>
            {#if playerProfile.suspendedUntil}
              <div class="detail-row">
                <span class="detail-label">Suspended Until</span>
                <span class="detail-value mono text-orange">
                  {new Date(playerProfile.suspendedUntil * 1000).toLocaleString()}
                </span>
              </div>
            {/if}

            <!-- Licenses -->
            {#if playerProfile.licenses?.length > 0}
              <div class="profile-section">
                <span class="section-label">Licenses</span>
                <div class="tag-list">
                  {#each playerProfile.licenses as lic}
                    <div class="tag-item">
                      <span class="tag-text">{lic.type?.replace('_', ' ').toUpperCase()}</span>
                      <StatusBadge status={lic.status || 'active'} />
                    </div>
                  {/each}
                </div>
              </div>
            {/if}

            <!-- Certifications -->
            {#if playerProfile.certifications?.length > 0}
              <div class="profile-section">
                <span class="section-label">Certifications</span>
                <div class="tag-list">
                  {#each playerProfile.certifications as cert}
                    <div class="tag-item">
                      <span class="tag-text">{cert.type?.replace('_', ' ').toUpperCase()}</span>
                      <StatusBadge status={cert.status || 'active'} />
                    </div>
                  {/each}
                </div>
              </div>
            {/if}

            <!-- Active Load -->
            {#if playerProfile.activeLoad}
              <div class="profile-section">
                <span class="section-label">Active Load</span>
                <div class="detail-row">
                  <span class="detail-label">BOL #</span>
                  <span class="detail-value mono">{playerProfile.activeLoad.bolNumber || '--'}</span>
                </div>
                <div class="detail-row">
                  <span class="detail-label">Cargo</span>
                  <span class="detail-value">{playerProfile.activeLoad.cargoType || '--'}</span>
                </div>
                <div class="detail-row">
                  <span class="detail-label">Status</span>
                  <StatusBadge status={playerProfile.activeLoad.status || 'in_transit'} />
                </div>
              </div>
            {/if}

            <!-- BOL History -->
            {#if playerProfile.bolHistory?.length > 0}
              <div class="profile-section">
                <span class="section-label">Recent BOL History</span>
                <div class="bol-history-list">
                  {#each playerProfile.bolHistory.slice(0, 10) as bol}
                    <div class="bol-history-row">
                      <span class="mono bol-num">#{bol.bolNumber || '--'}</span>
                      <span class="bol-cargo truncate">{bol.cargoType || '--'}</span>
                      <span class="mono bol-payout">{formatDollar(bol.payout)}</span>
                      <StatusBadge status={bol.status || 'completed'} />
                    </div>
                  {/each}
                </div>
              </div>
            {/if}

            <!-- Actions -->
            <div class="divider"></div>
            <div class="player-actions">
              <!-- Adjust Rep -->
              <div class="action-row">
                <input
                  type="number"
                  class="input-field input-sm"
                  placeholder="New rep score (0-1000)"
                  bind:value={repAdjustValue}
                  min="0"
                  max="1000"
                />
                <button
                  class="btn btn-primary btn-sm"
                  on:click={adjustReputation}
                  disabled={!repAdjustValue}
                >
                  Set Rep
                </button>
              </div>

              <!-- Suspend / Unsuspend -->
              {#if playerProfile.suspendedUntil}
                <button class="btn btn-primary btn-sm" on:click={unsuspendDriver}>
                  Unsuspend Driver
                </button>
              {:else}
                <button
                  class="btn btn-danger btn-sm"
                  on:click={() => showSuspendForm = !showSuspendForm}
                >
                  {showSuspendForm ? 'Cancel' : 'Suspend Driver'}
                </button>
                {#if showSuspendForm}
                  <div class="suspend-form">
                    <input
                      type="number"
                      class="input-field input-sm"
                      placeholder="Duration (hours)"
                      bind:value={suspendDuration}
                      min="1"
                    />
                    <input
                      type="text"
                      class="input-field input-sm"
                      placeholder="Reason for suspension"
                      bind:value={suspendReason}
                    />
                    <button
                      class="btn btn-danger btn-sm"
                      on:click={suspendDriver}
                      disabled={!suspendDuration || !suspendReason.trim()}
                    >
                      Confirm Suspend
                    </button>
                  </div>
                {/if}
              {/if}
            </div>
          </div>
        </div>
      {:else}
        <div class="empty-state">
          <span class="empty-text text-muted">Search for a player by Citizen ID or name to view their profile.</span>
        </div>
      {/if}
    </div>
  {/if}

  <!-- ==================== ECONOMY TAB ==================== -->
  {#if activeTab === 'economy'}
    <div class="tab-content">
      <!-- Multiplier Control -->
      <div class="card">
        <div class="card-header">
          <h3 class="card-title">Global Multiplier</h3>
          <span class="mono text-orange multiplier-display">{Number(multiplierValue).toFixed(1)}x</span>
        </div>
        <div class="card-body">
          <div class="slider-row">
            <span class="slider-label mono">0.1x</span>
            <input
              type="range"
              class="slider"
              min="0.1"
              max="5.0"
              step="0.1"
              bind:value={multiplierValue}
            />
            <span class="slider-label mono">5.0x</span>
          </div>
          <button class="btn btn-primary btn-sm" on:click={setMultiplier}>
            Apply Multiplier
          </button>
        </div>
      </div>

      <!-- Active Surges -->
      <div class="card">
        <div class="card-header">
          <h3 class="card-title">Active Surges</h3>
          <span class="mono">{activeSurges.length}</span>
        </div>
        <div class="card-body">
          {#if activeSurges.length === 0}
            <div class="empty-state-inline">
              <span class="empty-text text-muted">No active surges.</span>
            </div>
          {:else}
            <div class="surge-list">
              {#each activeSurges as surge (surge.surgeId || surge.id)}
                <div class="surge-row">
                  <div class="surge-info">
                    <span class="surge-region">{regionOptions.find(r => r.id === surge.region)?.label || surge.region}</span>
                    <span class="mono text-orange">+{surge.percentage}%</span>
                    {#if surge.cargoFilter && surge.cargoFilter !== 'all'}
                      <span class="surge-filter text-muted">{surge.cargoFilter}</span>
                    {/if}
                    {#if surge.timeRemaining}
                      <span class="surge-time text-muted mono">{formatTime(surge.timeRemaining)}</span>
                    {/if}
                  </div>
                  <button
                    class="btn btn-danger btn-sm"
                    on:click={() => cancelSurge(surge.surgeId || surge.id)}
                  >
                    Cancel
                  </button>
                </div>
              {/each}
            </div>
          {/if}
        </div>
      </div>

      <!-- Create Surge -->
      <div class="card">
        <div class="card-header">
          <h3 class="card-title">Create Surge</h3>
        </div>
        <div class="card-body">
          <div class="form-grid">
            <div class="form-group">
              <label class="form-label" for="surge-region">Region</label>
              <select id="surge-region" class="input-field" bind:value={surgeRegion}>
                {#each regionOptions as region}
                  <option value={region.id}>{region.label}</option>
                {/each}
              </select>
            </div>
            <div class="form-group">
              <label class="form-label" for="surge-pct">Percentage (%)</label>
              <input
                id="surge-pct"
                type="number"
                class="input-field"
                placeholder="e.g. 25"
                bind:value={surgePercentage}
                min="1"
                max="200"
              />
            </div>
            <div class="form-group">
              <label class="form-label" for="surge-dur">Duration (minutes)</label>
              <input
                id="surge-dur"
                type="number"
                class="input-field"
                placeholder="e.g. 60"
                bind:value={surgeDuration}
                min="1"
              />
            </div>
            <div class="form-group">
              <label class="form-label" for="surge-cargo">Cargo Filter</label>
              <select id="surge-cargo" class="input-field" bind:value={surgeCargoFilter}>
                {#each cargoFilterOptions as opt}
                  <option value={opt.id}>{opt.label}</option>
                {/each}
              </select>
            </div>
          </div>
          <button
            class="btn btn-primary btn-sm"
            on:click={createSurge}
            disabled={!surgePercentage || !surgeDuration}
          >
            Create Surge
          </button>
        </div>
      </div>

      <!-- Board Refresh -->
      <div class="card">
        <div class="card-header">
          <h3 class="card-title">Board Refresh</h3>
        </div>
        <div class="card-body">
          <div class="region-refresh-grid">
            {#each regionOptions as region}
              <div class="region-refresh-row">
                <div class="region-refresh-info">
                  <span class="region-name">{region.label}</span>
                  {#if boardState[region.id]}
                    <span class="text-muted mono region-meta">
                      {boardState[region.id].loadCount ?? '--'} loads
                    </span>
                  {/if}
                </div>
                <button
                  class="btn btn-secondary btn-sm"
                  on:click={() => refreshBoard(region.id)}
                >
                  Refresh
                </button>
              </div>
            {/each}
          </div>
        </div>
      </div>
    </div>
  {/if}

  <!-- ==================== LOADS TAB ==================== -->
  {#if activeTab === 'loads'}
    <div class="tab-content">
      {#if activeLoads.length === 0}
        <div class="empty-state">
          <span class="empty-text text-muted">No active loads on the server.</span>
        </div>
      {:else}
        <div class="load-list">
          {#each activeLoads as load (load.loadId || load.id || load.bolNumber)}
            <div class="card load-row-card">
              <div class="load-row-top">
                <div class="load-row-info">
                  <span class="mono bol-num">BOL #{load.bolNumber || '--'}</span>
                  <span class="load-driver">{load.driverName || load.driver || '--'}</span>
                </div>
                <StatusBadge status={load.status || 'in_transit'} />
              </div>
              <div class="load-row-details">
                <div class="detail-row">
                  <span class="detail-label">Cargo</span>
                  <span class="detail-value">{load.cargoType || '--'}</span>
                </div>
                {#if load.origin}
                  <div class="detail-row">
                    <span class="detail-label">Origin</span>
                    <span class="detail-value truncate">{load.origin}</span>
                  </div>
                {/if}
                {#if load.destination || load.destinationLabel}
                  <div class="detail-row">
                    <span class="detail-label">Destination</span>
                    <span class="detail-value truncate">{load.destination || load.destinationLabel}</span>
                  </div>
                {/if}
                {#if load.integrity != null}
                  <div class="detail-row">
                    <span class="detail-label">Integrity</span>
                    <span class="detail-value mono">{load.integrity}%</span>
                  </div>
                {/if}
              </div>
              <div class="load-row-actions">
                <button
                  class="btn btn-primary btn-sm"
                  on:click={() => forceComplete(load.loadId || load.id)}
                >
                  Force Complete
                </button>
                <button
                  class="btn btn-danger btn-sm"
                  on:click={() => forceAbandon(load.loadId || load.id)}
                >
                  Force Abandon
                </button>
              </div>
            </div>
          {/each}
        </div>
      {/if}
    </div>
  {/if}

  <!-- ==================== INSURANCE TAB ==================== -->
  {#if activeTab === 'insurance'}
    <div class="tab-content">
      {#if pendingClaims.length === 0}
        <div class="empty-state">
          <span class="empty-text text-muted">No pending insurance claims.</span>
        </div>
      {:else}
        <div class="claims-list">
          {#each pendingClaims as claim (claim.claimId || claim.id)}
            <div class="card claim-card">
              <div class="card-header">
                <h4 class="card-title">Claim #{claim.claimId || claim.id}</h4>
                <StatusBadge status="warning" label="Pending" />
              </div>
              <div class="card-body">
                <div class="detail-row">
                  <span class="detail-label">Driver</span>
                  <span class="detail-value">{claim.driverName || claim.driver || '--'}</span>
                </div>
                <div class="detail-row">
                  <span class="detail-label">BOL #</span>
                  <span class="detail-value mono">{claim.bolNumber || '--'}</span>
                </div>
                <div class="detail-row">
                  <span class="detail-label">Amount</span>
                  <span class="detail-value mono">{formatDollar(claim.amount)}</span>
                </div>
                <div class="detail-row">
                  <span class="detail-label">Reason</span>
                  <span class="detail-value">{claim.reason || '--'}</span>
                </div>
                {#if claim.filedAt}
                  <div class="detail-row">
                    <span class="detail-label">Filed</span>
                    <span class="detail-value mono">{new Date(claim.filedAt * 1000).toLocaleString()}</span>
                  </div>
                {/if}

                <div class="divider"></div>

                <div class="claim-actions">
                  <button
                    class="btn btn-primary btn-sm"
                    on:click={() => approveClaim(claim.claimId || claim.id)}
                  >
                    Approve
                  </button>
                  <div class="deny-row">
                    <input
                      type="text"
                      class="input-field input-sm"
                      placeholder="Denial reason..."
                      bind:value={denyReasonMap[claim.claimId || claim.id]}
                    />
                    <button
                      class="btn btn-danger btn-sm"
                      on:click={() => denyClaim(claim.claimId || claim.id)}
                      disabled={!(denyReasonMap[claim.claimId || claim.id] || '').trim()}
                    >
                      Deny
                    </button>
                  </div>
                </div>
              </div>
            </div>
          {/each}
        </div>
      {/if}
    </div>
  {/if}

  <!-- ==================== CONFIRMATION DIALOG ==================== -->
  {#if showConfirmDialog}
    <div
      class="dialog-overlay"
      on:click={handleCancelConfirm}
      on:keydown={(e) => e.key === 'Escape' && handleCancelConfirm()}
      role="dialog"
      tabindex="-1"
    >
      <div
        class="dialog-panel"
        on:click|stopPropagation
        on:keydown|stopPropagation
        role="document"
      >
        <h3>{confirmTitle}</h3>
        <p class="text-muted">{confirmMessage}</p>
        <div class="dialog-actions">
          <button class="btn btn-secondary" on:click={handleCancelConfirm}>Cancel</button>
          <button class="btn btn-primary" on:click={handleConfirm}>Confirm</button>
        </div>
      </div>
    </div>
  {/if}
</div>

<style>
  .admin-screen {
    display: flex;
    flex-direction: column;
  }

  .admin-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-bottom: var(--spacing-lg);
  }

  .admin-title {
    font-size: 18px;
    color: var(--orange);
    margin: 0;
  }

  .tab-content {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-lg);
  }

  /* ---- Stat Grid (Dashboard) ---- */
  .stat-grid {
    display: grid;
    grid-template-columns: 1fr 1fr 1fr;
    gap: var(--spacing-md);
  }

  .stat-card {
    background: var(--navy-mid);
    border: 1px solid var(--border);
    border-radius: var(--radius-lg);
    padding: var(--spacing-lg);
    display: flex;
    flex-direction: column;
    gap: var(--spacing-xs);
  }

  .stat-card-label {
    font-size: 10px;
    color: var(--muted);
    text-transform: uppercase;
    letter-spacing: 0.04em;
    font-family: var(--font-heading);
    font-weight: 700;
  }

  .stat-card-value {
    font-size: 22px;
    color: var(--white);
    font-weight: 500;
  }

  /* ---- Search Bar ---- */
  .search-bar {
    display: flex;
    gap: var(--spacing-sm);
  }

  .search-bar .input-field {
    flex: 1;
  }

  /* ---- Input Fields ---- */
  .input-field {
    background: var(--navy-dark);
    border: 1px solid var(--border);
    border-radius: var(--radius-sm);
    color: var(--white);
    font-family: var(--font-body);
    font-size: 13px;
    padding: var(--spacing-sm) var(--spacing-md);
    outline: none;
    width: 100%;
  }

  .input-field:focus {
    border-color: var(--orange);
  }

  .input-field::placeholder {
    color: var(--muted);
    opacity: 0.6;
  }

  .input-sm {
    padding: var(--spacing-xs) var(--spacing-sm);
    font-size: 12px;
  }

  select.input-field {
    cursor: pointer;
  }

  select.input-field option {
    background: var(--navy-dark);
    color: var(--white);
  }

  /* ---- Detail Rows ---- */
  .detail-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
  }

  .detail-label {
    font-size: 11px;
    color: var(--muted);
    text-transform: uppercase;
    letter-spacing: 0.04em;
    font-family: var(--font-heading);
    font-weight: 700;
  }

  .detail-value {
    font-size: 13px;
    color: var(--white);
  }

  /* ---- Player Profile ---- */
  .player-profile-card .card-body {
    gap: var(--spacing-xs);
  }

  .profile-section {
    border-top: 1px solid var(--border);
    padding-top: var(--spacing-sm);
    margin-top: var(--spacing-sm);
  }

  .section-label {
    display: block;
    font-size: 10px;
    color: var(--muted);
    text-transform: uppercase;
    letter-spacing: 0.04em;
    font-family: var(--font-heading);
    font-weight: 700;
    margin-bottom: var(--spacing-xs);
  }

  .tag-list {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-xs);
  }

  .tag-item {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: var(--spacing-xs) 0;
  }

  .tag-text {
    font-size: 12px;
    font-family: var(--font-heading);
    font-weight: 700;
    letter-spacing: 0.03em;
  }

  .player-actions {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-sm);
  }

  .action-row {
    display: flex;
    gap: var(--spacing-sm);
    align-items: center;
  }

  .action-row .input-field {
    flex: 1;
  }

  .suspend-form {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-sm);
    padding: var(--spacing-sm);
    background: var(--navy-dark);
    border: 1px solid var(--border);
    border-radius: var(--radius-md);
  }

  /* ---- BOL History ---- */
  .bol-history-list {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-xs);
  }

  .bol-history-row {
    display: flex;
    align-items: center;
    gap: var(--spacing-sm);
    padding: var(--spacing-xs) 0;
    font-size: 12px;
  }

  .bol-num {
    font-size: 11px;
    color: var(--muted);
    min-width: 72px;
  }

  .bol-cargo {
    flex: 1;
    font-size: 12px;
    color: var(--white);
  }

  .bol-payout {
    font-size: 12px;
    color: var(--success);
    min-width: 64px;
    text-align: right;
  }

  /* ---- Multiplier Slider ---- */
  .multiplier-display {
    font-size: 18px;
  }

  .slider-row {
    display: flex;
    align-items: center;
    gap: var(--spacing-sm);
  }

  .slider-label {
    font-size: 11px;
    color: var(--muted);
    flex-shrink: 0;
  }

  .slider {
    flex: 1;
    -webkit-appearance: none;
    appearance: none;
    height: 6px;
    background: var(--navy-dark);
    border-radius: 3px;
    outline: none;
  }

  .slider::-webkit-slider-thumb {
    -webkit-appearance: none;
    appearance: none;
    width: 18px;
    height: 18px;
    border-radius: 50%;
    background: var(--orange);
    cursor: pointer;
    border: 2px solid var(--white);
  }

  .slider::-moz-range-thumb {
    width: 18px;
    height: 18px;
    border-radius: 50%;
    background: var(--orange);
    cursor: pointer;
    border: 2px solid var(--white);
  }

  /* ---- Surge List ---- */
  .surge-list {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-sm);
  }

  .surge-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: var(--spacing-sm);
    background: var(--navy-dark);
    border: 1px solid var(--border);
    border-radius: var(--radius-md);
  }

  .surge-info {
    display: flex;
    align-items: center;
    gap: var(--spacing-sm);
    flex-wrap: wrap;
  }

  .surge-region {
    font-family: var(--font-heading);
    font-weight: 700;
    font-size: 13px;
    text-transform: uppercase;
    letter-spacing: 0.03em;
  }

  .surge-filter {
    font-size: 11px;
    text-transform: uppercase;
  }

  .surge-time {
    font-size: 11px;
  }

  /* ---- Create Surge Form ---- */
  .form-grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: var(--spacing-sm);
  }

  .form-group {
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  .form-label {
    font-size: 10px;
    color: var(--muted);
    text-transform: uppercase;
    letter-spacing: 0.04em;
    font-family: var(--font-heading);
    font-weight: 700;
  }

  /* ---- Board Refresh ---- */
  .region-refresh-grid {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-sm);
  }

  .region-refresh-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: var(--spacing-sm);
    background: var(--navy-dark);
    border: 1px solid var(--border);
    border-radius: var(--radius-md);
  }

  .region-refresh-info {
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .region-name {
    font-family: var(--font-heading);
    font-weight: 700;
    font-size: 13px;
    text-transform: uppercase;
    letter-spacing: 0.03em;
  }

  .region-meta {
    font-size: 11px;
  }

  /* ---- Load List (Loads Tab) ---- */
  .load-list {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-sm);
  }

  .load-row-card {
    padding: var(--spacing-md);
  }

  .load-row-top {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-bottom: var(--spacing-sm);
  }

  .load-row-info {
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .load-driver {
    font-family: var(--font-heading);
    font-weight: 700;
    font-size: 14px;
    text-transform: uppercase;
    letter-spacing: 0.03em;
  }

  .load-row-details {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-xs);
    margin-bottom: var(--spacing-sm);
  }

  .load-row-actions {
    display: flex;
    gap: var(--spacing-sm);
  }

  /* ---- Claims List (Insurance Tab) ---- */
  .claims-list {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-sm);
  }

  .claim-actions {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-sm);
  }

  .deny-row {
    display: flex;
    gap: var(--spacing-sm);
    align-items: center;
  }

  .deny-row .input-field {
    flex: 1;
  }

  /* ---- Empty States ---- */
  .empty-state {
    display: flex;
    align-items: center;
    justify-content: center;
    padding: var(--spacing-xl);
    background: var(--navy-dark);
    border: 1px dashed var(--border);
    border-radius: var(--radius-md);
  }

  .empty-state-inline {
    padding: var(--spacing-md);
    text-align: center;
  }

  .empty-text {
    font-size: 14px;
  }

  /* ---- Confirmation Dialog ---- */
  .dialog-overlay {
    position: fixed;
    top: 0;
    left: 0;
    width: 100vw;
    height: 100vh;
    background: rgba(5, 18, 41, 0.8);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 1000;
  }

  .dialog-panel {
    background: var(--navy);
    border: 1px solid var(--border);
    border-radius: var(--radius-lg);
    padding: var(--spacing-xl);
    max-width: 400px;
    width: 90%;
  }

  .dialog-panel h3 {
    margin-bottom: var(--spacing-md);
    font-size: 16px;
  }

  .dialog-panel p {
    font-size: 14px;
    margin-bottom: var(--spacing-lg);
    line-height: 1.5;
  }

  .dialog-actions {
    display: flex;
    justify-content: flex-end;
    gap: var(--spacing-sm);
  }
</style>
