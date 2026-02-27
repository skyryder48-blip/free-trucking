<script>
  import { createEventDispatcher } from 'svelte';
  import { boardData, playerData } from '../lib/stores.js';
  import { fetchNUI } from '../lib/nui.js';
  import TabBar from '../components/TabBar.svelte';
  import LoadCard from '../components/LoadCard.svelte';
  import TierBadge from '../components/TierBadge.svelte';
  import StatusBadge from '../components/StatusBadge.svelte';

  const dispatch = createEventDispatcher();

  let activeTab = 'standard';
  let tierFilter = 'all';
  let regionFilter = 'all';
  let showConfirmDialog = false;
  let pendingAcceptLoad = null;

  const tabs = [
    { id: 'standard', label: 'Standard' },
    { id: 'supplier', label: 'Supplier' },
    { id: 'open', label: 'Open' },
    { id: 'routes', label: 'Routes' },
  ];

  function handleTabChange(e) {
    activeTab = e.detail.tab;
  }

  function navigateTo(screen, data = null) {
    dispatch('navigate', { screen, data });
  }

  function handleViewDetail(e) {
    navigateTo('loadDetail', e.detail.load);
  }

  async function handleReserve(e) {
    const load = e.detail.load;
    await fetchNUI('reserveLoad', { loadId: load.id });
  }

  function handleAccept(e) {
    pendingAcceptLoad = e.detail.load;
    showConfirmDialog = true;
  }

  async function confirmAccept() {
    if (pendingAcceptLoad) {
      await fetchNUI('acceptLoad', { loadId: pendingAcceptLoad.id });
    }
    showConfirmDialog = false;
    pendingAcceptLoad = null;
  }

  function cancelAccept() {
    showConfirmDialog = false;
    pendingAcceptLoad = null;
  }

  function formatDollar(n) {
    if (n == null) return '$0';
    return '$' + Number(n).toLocaleString('en-US');
  }

  function formatDistance(d) {
    if (d == null) return '—';
    return Number(d).toFixed(1) + ' mi';
  }

  $: board = $boardData;
  $: player = $playerData;

  // Is Professional+ for cross-region
  $: canCrossRegion = ['professional', 'elite'].includes(player.reputationTier);

  // Filter standard loads
  $: filteredStandard = (() => {
    let loads = board.standard || [];
    if (tierFilter !== 'all') {
      loads = loads.filter(l => l.tier === Number(tierFilter));
    }
    if (regionFilter !== 'all') {
      loads = loads.filter(l => l.boardRegion === regionFilter);
    }
    return loads;
  })();

  // Update tab counts
  $: tabsWithCounts = tabs.map(t => ({
    ...t,
    count: t.id === 'standard' ? (board.standard || []).length
         : t.id === 'supplier' ? (board.supplier || []).length
         : t.id === 'open' ? (board.open || []).length
         : t.id === 'routes' ? (board.routes || []).length
         : 0,
  }));
</script>

<div class="board-screen">
  <TabBar tabs={tabsWithCounts} {activeTab} on:tabChange={handleTabChange} />

  <!-- Standard Tab -->
  {#if activeTab === 'standard'}
    <div class="board-filters">
      <div class="filter-group">
        <label class="filter-label" for="tier-filter">Tier</label>
        <select id="tier-filter" class="filter-select" bind:value={tierFilter}>
          <option value="all">All Tiers</option>
          <option value="0">T0 — Entry</option>
          <option value="1">T1 — Standard</option>
          <option value="2">T2 — Specialized</option>
          <option value="3">T3 — Premium</option>
        </select>
      </div>

      {#if canCrossRegion}
        <div class="filter-group">
          <label class="filter-label" for="region-filter">Region</label>
          <select id="region-filter" class="filter-select" bind:value={regionFilter}>
            <option value="all">All Regions</option>
            <option value="los_santos">Chicago (LS)</option>
            <option value="sandy_shores">Gary (SS)</option>
            <option value="paleto">Wisconsin (Paleto)</option>
            <option value="grapeseed">W. Michigan (GS)</option>
          </select>
        </div>
      {/if}
    </div>

    <div class="load-list">
      {#if filteredStandard.length === 0}
        <div class="empty-state">
          <span class="empty-text text-muted">No loads available matching your filters.</span>
        </div>
      {:else}
        {#each filteredStandard as load (load.id)}
          <LoadCard
            {load}
            on:viewDetail={handleViewDetail}
            on:reserve={handleReserve}
            on:accept={handleAccept}
          />
        {/each}
      {/if}
    </div>
  {/if}

  <!-- Supplier Tab -->
  {#if activeTab === 'supplier'}
    <div class="load-list">
      {#if (board.supplier || []).length === 0}
        <div class="empty-state">
          <span class="empty-text text-muted">No supplier contracts available.</span>
        </div>
      {:else}
        {#each board.supplier as contract (contract.id)}
          <div class="card supplier-card">
            <div class="card-header">
              <h4 class="supplier-name">{contract.supplierName || 'Supplier'}</h4>
              <StatusBadge status={contract.status || 'active'} />
            </div>
            <div class="card-body">
              <div class="supplier-details">
                <div class="detail-row">
                  <span class="detail-label">Items Required</span>
                  <span class="detail-value">{contract.itemRequired || '—'}</span>
                </div>
                <div class="detail-row">
                  <span class="detail-label">Quantity</span>
                  <span class="detail-value mono">{contract.quantity || 0} / {contract.quantityRequired || 0}</span>
                </div>
                <div class="detail-row">
                  <span class="detail-label">Payout</span>
                  <span class="detail-value mono payout-figure">{formatDollar(contract.payout)}</span>
                </div>
                {#if contract.deadline}
                  <div class="detail-row">
                    <span class="detail-label">Deadline</span>
                    <span class="detail-value mono">{new Date(contract.deadline * 1000).toLocaleString()}</span>
                  </div>
                {/if}
              </div>
              {#if contract.quantityRequired}
                <div class="progress-bar-container">
                  <div
                    class="progress-bar-fill"
                    style="width: {Math.min(100, ((contract.quantity || 0) / contract.quantityRequired) * 100)}%"
                  ></div>
                </div>
              {/if}
            </div>
          </div>
        {/each}
      {/if}
    </div>
  {/if}

  <!-- Open Tab -->
  {#if activeTab === 'open'}
    <div class="load-list">
      {#if (board.open || []).length === 0}
        <div class="empty-state">
          <span class="empty-text text-muted">No open contracts available.</span>
        </div>
      {:else}
        {#each board.open as contract (contract.id)}
          <div class="card open-card">
            <div class="card-header">
              <h4 class="contract-title">{contract.title || 'Open Contract'}</h4>
              <StatusBadge status={contract.status || 'active'} />
            </div>
            <div class="card-body">
              <p class="contract-desc text-muted">{contract.description || ''}</p>
              <div class="detail-row">
                <span class="detail-label">Progress</span>
                <span class="detail-value mono">{contract.currentProgress || 0} / {contract.targetProgress || 0}</span>
              </div>
              <div class="detail-row">
                <span class="detail-label">Payout per Unit</span>
                <span class="detail-value mono payout-figure">{formatDollar(contract.payoutPerUnit)}</span>
              </div>
              {#if contract.targetProgress}
                <div class="progress-bar-container">
                  <div
                    class="progress-bar-fill"
                    style="width: {Math.min(100, ((contract.currentProgress || 0) / contract.targetProgress) * 100)}%"
                  ></div>
                </div>
              {/if}
            </div>
          </div>
        {/each}
      {/if}
    </div>
  {/if}

  <!-- Routes Tab -->
  {#if activeTab === 'routes'}
    <div class="load-list">
      {#if (board.routes || []).length === 0}
        <div class="empty-state">
          <span class="empty-text text-muted">No multi-stop routes available.</span>
        </div>
      {:else}
        {#each board.routes as route (route.id)}
          <div class="card route-card">
            <div class="card-header">
              <div class="route-header-left">
                <TierBadge tier={route.tier || 2} size="small" />
                <h4 class="route-name">{route.name || 'Route'}</h4>
              </div>
              <span class="payout-figure mono">{formatDollar(route.totalPayout)}</span>
            </div>
            <div class="card-body">
              <div class="route-stops">
                {#each (route.stops || []) as stop, i}
                  <div class="route-stop" class:stop-completed={stop.completed}>
                    <span class="stop-number mono">{i + 1}</span>
                    <span class="stop-label">{stop.label || 'Stop'}</span>
                    {#if stop.completed}
                      <span class="stop-check text-success">&#10003;</span>
                    {/if}
                  </div>
                {/each}
              </div>
              <div class="route-summary">
                <div class="detail-row">
                  <span class="detail-label">Total Distance</span>
                  <span class="detail-value mono">{formatDistance(route.totalDistance)}</span>
                </div>
                <div class="detail-row">
                  <span class="detail-label">Stops</span>
                  <span class="detail-value mono">{route.stops?.length || 0}</span>
                </div>
                {#if route.premium}
                  <div class="detail-row">
                    <span class="detail-label">Route Premium</span>
                    <span class="detail-value mono text-orange">+{route.premium}%</span>
                  </div>
                {/if}
              </div>
              <button class="btn btn-primary btn-sm" on:click={() => navigateTo('loadDetail', route)}>
                View Route Details
              </button>
            </div>
          </div>
        {/each}
      {/if}
    </div>
  {/if}

  <!-- Confirmation Dialog -->
  {#if showConfirmDialog}
    <div class="dialog-overlay" on:click={cancelAccept} on:keydown={(e) => e.key === 'Escape' && cancelAccept()} role="dialog" tabindex="-1">
      <div class="dialog-panel" on:click|stopPropagation on:keydown|stopPropagation role="document">
        <h3>Confirm Accept</h3>
        <p class="text-muted">
          Accept this load? A deposit of
          <span class="mono">{formatDollar(pendingAcceptLoad?.depositAmount)}</span>
          will be placed.
        </p>
        <div class="dialog-actions">
          <button class="btn btn-secondary" on:click={cancelAccept}>Cancel</button>
          <button class="btn btn-primary" on:click={confirmAccept}>Accept Load</button>
        </div>
      </div>
    </div>
  {/if}
</div>

<style>
  .board-screen {
    display: flex;
    flex-direction: column;
  }

  .board-filters {
    display: flex;
    gap: var(--spacing-md);
    margin-bottom: var(--spacing-md);
  }

  .filter-group {
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  .filter-label {
    font-size: 10px;
    color: var(--muted);
    text-transform: uppercase;
    letter-spacing: 0.04em;
    font-family: var(--font-heading);
    font-weight: 700;
  }

  .filter-select {
    background: var(--navy-dark);
    border: 1px solid var(--border);
    border-radius: var(--radius-sm);
    color: var(--white);
    font-family: var(--font-body);
    font-size: 13px;
    padding: var(--spacing-xs) var(--spacing-sm);
    outline: none;
    cursor: pointer;
  }

  .filter-select:focus {
    border-color: var(--orange);
  }

  .filter-select option {
    background: var(--navy-dark);
    color: var(--white);
  }

  .load-list {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-sm);
  }

  .empty-state {
    display: flex;
    align-items: center;
    justify-content: center;
    padding: var(--spacing-xl);
    background: var(--navy-dark);
    border: 1px dashed var(--border);
    border-radius: var(--radius-md);
  }

  .empty-text {
    font-size: 14px;
  }

  /* Supplier cards */
  .supplier-name {
    font-size: 14px;
    margin: 0;
  }

  .supplier-details {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-xs);
    margin-bottom: var(--spacing-sm);
  }

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

  .payout-figure {
    color: var(--success);
    font-weight: 500;
  }

  .contract-desc {
    font-size: 13px;
    margin-bottom: var(--spacing-sm);
    line-height: 1.4;
  }

  /* Progress bar */
  .progress-bar-container {
    width: 100%;
    height: 4px;
    background: var(--navy-dark);
    border-radius: 2px;
    overflow: hidden;
    margin-top: var(--spacing-sm);
  }

  .progress-bar-fill {
    height: 100%;
    background: var(--orange);
    border-radius: 2px;
    transition: width 0.4s ease;
  }

  /* Route cards */
  .route-header-left {
    display: flex;
    align-items: center;
    gap: var(--spacing-sm);
  }

  .route-name {
    font-size: 14px;
    margin: 0;
  }

  .route-stops {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-xs);
    margin-bottom: var(--spacing-md);
    padding-left: var(--spacing-sm);
    border-left: 2px solid var(--border);
  }

  .route-stop {
    display: flex;
    align-items: center;
    gap: var(--spacing-sm);
    padding: 2px 0;
  }

  .stop-number {
    font-size: 11px;
    color: var(--muted);
    min-width: 18px;
  }

  .stop-label {
    font-size: 13px;
    color: var(--white);
    flex: 1;
  }

  .stop-completed {
    opacity: 0.5;
  }

  .stop-check {
    font-size: 14px;
  }

  .route-summary {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-xs);
    margin-bottom: var(--spacing-md);
  }

  .contract-title {
    font-size: 14px;
    margin: 0;
  }

  /* Dialog */
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
