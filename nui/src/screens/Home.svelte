<script>
  import { createEventDispatcher } from 'svelte';
  import { playerData, activeLoad, insuranceData, boardData } from '../lib/stores.js';
  import TierBadge from '../components/TierBadge.svelte';
  import StatusBadge from '../components/StatusBadge.svelte';
  import CountdownTimer from '../components/CountdownTimer.svelte';
  import ProgressRing from '../components/ProgressRing.svelte';

  const dispatch = createEventDispatcher();

  function navigateTo(screen, data = null) {
    dispatch('navigate', { screen, data });
  }

  function formatDollar(n) {
    if (n == null) return '$0';
    return '$' + Number(n).toLocaleString('en-US');
  }

  function getTierFromRep(score) {
    if (score >= 900) return 3;
    if (score >= 700) return 2;
    if (score >= 500) return 1;
    return 0;
  }

  function getRepTierLabel(tier) {
    const labels = {
      suspended: 'Suspended',
      restricted: 'Restricted',
      probationary: 'Probationary',
      developing: 'Developing',
      established: 'Established',
      professional: 'Professional',
      elite: 'Elite',
    };
    return labels[tier] || tier;
  }

  $: player = $playerData;
  $: load = $activeLoad;
  $: insurance = $insuranceData;
  $: board = $boardData;

  $: activePolicy = insurance.policies?.find(p => p.status === 'active') || null;

  // Count available board loads by tier
  $: boardCounts = (() => {
    const standard = board.standard || [];
    const counts = { 0: 0, 1: 0, 2: 0, 3: 0 };
    standard.forEach(l => {
      if (counts[l.tier] !== undefined) counts[l.tier]++;
    });
    return counts;
  })();

  $: totalBoardLoads = Object.values(boardCounts).reduce((a, b) => a + b, 0);
</script>

<div class="home-screen">
  <!-- Active Load Summary Card -->
  {#if load}
    <div class="card active-load-card">
      <div class="card-header">
        <h3 class="card-title">Active Load</h3>
        <StatusBadge status={load.status || 'in_transit'} />
      </div>
      <div class="card-body">
        <div class="active-load-top">
          <div class="active-load-info">
            <span class="bol-number mono">BOL #{load.bolNumber || '—'}</span>
            <span class="cargo-label">{load.cargoType || 'Cargo'}</span>
            <span class="dest-label text-muted">{load.destinationLabel || '—'}</span>
          </div>
          <div class="active-load-meters">
            {#if load.windowExpiresAt}
              <CountdownTimer targetTime={load.windowExpiresAt} />
            {/if}
            <ProgressRing
              value={load.cargoIntegrity ?? 100}
              label="%"
              size={52}
              strokeWidth={4}
              variant="integrity"
            />
          </div>
        </div>
        <button class="btn btn-primary btn-sm" on:click={() => navigateTo('activeLoad')}>
          View Active Load
        </button>
      </div>
    </div>
  {/if}

  <!-- Driver Standing Card -->
  <div class="card standing-card">
    <div class="card-header">
      <h3 class="card-title">Driver Standing</h3>
      <span class="rep-tier-badge heading">{getRepTierLabel(player.reputationTier)}</span>
    </div>
    <div class="card-body">
      <div class="standing-stats">
        <div class="stat-item">
          <span class="stat-label">Reputation</span>
          <span class="stat-value mono">{player.reputationScore}</span>
        </div>
        <div class="stat-item">
          <span class="stat-label">Total Deliveries</span>
          <span class="stat-value mono">{player.totalLoadsCompleted}</span>
        </div>
        <div class="stat-item">
          <span class="stat-label">Total Earnings</span>
          <span class="stat-value mono">{formatDollar(player.totalEarnings)}</span>
        </div>
        <div class="stat-item">
          <span class="stat-label">Distance Driven</span>
          <span class="stat-value mono">{player.totalDistanceDriven?.toLocaleString() || '0'} mi</span>
        </div>
      </div>

      {#if player.licenses?.length > 0}
        <div class="standing-licenses">
          <span class="section-label">Licenses</span>
          <div class="license-list">
            {#each player.licenses as lic}
              <div class="license-item">
                <span class="license-type">{lic.type?.replace('_', ' ').toUpperCase()}</span>
                <StatusBadge status={lic.status} />
              </div>
            {/each}
          </div>
        </div>
      {/if}
    </div>
  </div>

  <!-- Insurance Status Card -->
  <div class="card insurance-card">
    <div class="card-header">
      <h3 class="card-title">Insurance</h3>
      {#if activePolicy}
        <StatusBadge status="active" />
      {:else}
        <StatusBadge status="inactive" label="No Policy" />
      {/if}
    </div>
    <div class="card-body">
      {#if activePolicy}
        <div class="insurance-info">
          <span class="insurance-type">{activePolicy.policyType || 'Standard'}</span>
          {#if activePolicy.expiresAt}
            <span class="insurance-expiry text-muted">
              Expires: <span class="mono">{new Date(activePolicy.expiresAt * 1000).toLocaleDateString()}</span>
            </span>
          {/if}
        </div>
      {:else}
        <p class="text-muted" style="font-size: 13px;">No active insurance policy. Consider purchasing coverage before your next haul.</p>
      {/if}
    </div>
  </div>

  <!-- Nearby Board Summary -->
  <div class="card board-summary-card">
    <div class="card-header">
      <h3 class="card-title">Available Loads</h3>
      <span class="board-count mono">{totalBoardLoads}</span>
    </div>
    <div class="card-body">
      <div class="tier-counts">
        {#each [0, 1, 2, 3] as t}
          <div class="tier-count-item">
            <TierBadge tier={t} size="small" />
            <span class="tier-count-value mono">{boardCounts[t]}</span>
          </div>
        {/each}
      </div>
    </div>
  </div>

  <!-- Quick Actions -->
  <div class="quick-actions">
    <button class="btn btn-primary" on:click={() => navigateTo('board')}>
      View Board
    </button>
    <button class="btn btn-secondary" on:click={() => navigateTo('profile')}>
      View Profile
    </button>
    <button class="btn btn-secondary" on:click={() => navigateTo('insurance')}>
      Buy Insurance
    </button>
  </div>
</div>

<style>
  .home-screen {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-lg);
  }

  .active-load-card {
    border-color: var(--orange);
  }

  .active-load-top {
    display: flex;
    justify-content: space-between;
    align-items: flex-start;
    gap: var(--spacing-md);
    margin-bottom: var(--spacing-md);
  }

  .active-load-info {
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  .bol-number {
    font-size: 12px;
    color: var(--muted);
  }

  .cargo-label {
    font-family: var(--font-heading);
    font-weight: 700;
    font-size: 16px;
    text-transform: uppercase;
    letter-spacing: 0.03em;
  }

  .dest-label {
    font-size: 13px;
  }

  .active-load-meters {
    display: flex;
    align-items: center;
    gap: var(--spacing-md);
  }

  .standing-stats {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: var(--spacing-sm);
    margin-bottom: var(--spacing-md);
  }

  .stat-item {
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .stat-label {
    font-size: 10px;
    color: var(--muted);
    text-transform: uppercase;
    letter-spacing: 0.04em;
    font-family: var(--font-heading);
    font-weight: 700;
  }

  .stat-value {
    font-size: 16px;
    color: var(--white);
    font-weight: 500;
  }

  .rep-tier-badge {
    font-size: 12px;
    color: var(--orange);
  }

  .standing-licenses {
    border-top: 1px solid var(--border);
    padding-top: var(--spacing-sm);
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

  .license-list {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-xs);
  }

  .license-item {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: var(--spacing-xs) 0;
  }

  .license-type {
    font-size: 12px;
    font-family: var(--font-heading);
    font-weight: 700;
    letter-spacing: 0.03em;
  }

  .insurance-info {
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  .insurance-type {
    font-family: var(--font-heading);
    font-weight: 700;
    font-size: 14px;
    text-transform: uppercase;
    letter-spacing: 0.03em;
  }

  .insurance-expiry {
    font-size: 12px;
  }

  .board-count {
    font-size: 16px;
    color: var(--white);
  }

  .tier-counts {
    display: flex;
    gap: var(--spacing-lg);
  }

  .tier-count-item {
    display: flex;
    align-items: center;
    gap: var(--spacing-sm);
  }

  .tier-count-value {
    font-size: 16px;
    color: var(--white);
  }

  .quick-actions {
    display: flex;
    gap: var(--spacing-sm);
  }

  .quick-actions .btn {
    flex: 1;
  }
</style>
