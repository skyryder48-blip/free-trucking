<script>
  import { createEventDispatcher } from 'svelte';
  import { activeLoad } from '../lib/stores.js';
  import { fetchNUI } from '../lib/nui.js';
  import TierBadge from '../components/TierBadge.svelte';
  import StatusBadge from '../components/StatusBadge.svelte';
  import CountdownTimer from '../components/CountdownTimer.svelte';
  import ProgressRing from '../components/ProgressRing.svelte';
  import PayoutBreakdown from '../components/PayoutBreakdown.svelte';

  const dispatch = createEventDispatcher();

  let showAbandonConfirm = false;
  let abandoning = false;

  function formatDollar(n) {
    if (n == null) return '—';
    return '$' + Number(n).toLocaleString('en-US');
  }

  function formatDistance(d) {
    if (d == null) return '—';
    return Number(d).toFixed(1) + ' mi';
  }

  async function handleDistress() {
    await fetchNUI('distressSignal', { bolId: $activeLoad?.bolId });
  }

  function requestAbandon() {
    showAbandonConfirm = true;
  }

  async function confirmAbandon() {
    abandoning = true;
    await fetchNUI('abandonLoad', { bolId: $activeLoad?.bolId });
    abandoning = false;
    showAbandonConfirm = false;
  }

  function cancelAbandon() {
    showAbandonConfirm = false;
  }

  $: load = $activeLoad;
  $: hasTemp = load?.tempMonitoringActive;
  $: tempInRange = hasTemp && load?.currentTempF != null
    ? (load.currentTempF >= (load.tempMinF ?? -999) && load.currentTempF <= (load.tempMaxF ?? 999))
    : true;
  $: hasLivestock = load?.welfareRating != null;
  $: isMultiStop = load?.isMultiStop || (load?.stops && load.stops.length > 1);

  // Compliance items
  $: compliance = load ? [
    { label: 'Pre-Trip Inspection', done: load.preTripCompleted },
    { label: 'Manifest Verified', done: load.manifestVerified },
    { label: 'Weigh Station', done: load.weighStationStamped },
    { label: 'Seal Applied', done: load.sealStatus === 'sealed' },
  ] : [];

  // Welfare star display
  $: welfareStars = hasLivestock ? Array.from({ length: 5 }, (_, i) => i < (load.welfareRating || 0)) : [];
</script>

{#if load}
  <div class="active-load-screen">
    <!-- Header -->
    <div class="load-header">
      <div class="header-info">
        <span class="bol-number mono">BOL #{load.bolNumber || '—'}</span>
        <h2 class="cargo-title">{load.cargoType || 'Cargo'}</h2>
        <StatusBadge status={load.status || 'in_transit'} />
      </div>
    </div>

    <!-- Destination & distance -->
    <div class="card destination-card">
      <div class="dest-row">
        <div class="dest-info">
          <span class="dest-label text-muted">Destination</span>
          <span class="dest-name">{load.destinationLabel || '—'}</span>
        </div>
        <div class="dest-distance">
          <span class="dest-label text-muted">Distance Remaining</span>
          <span class="dest-value mono">{formatDistance(load.distanceRemaining)}</span>
        </div>
      </div>
    </div>

    <!-- Delivery window countdown -->
    <div class="card timer-card">
      {#if load.windowExpiresAt}
        <CountdownTimer
          targetTime={load.windowExpiresAt}
          large={true}
          warningMinutes={15}
          criticalMinutes={5}
        />
      {:else}
        <span class="text-muted">No delivery window set</span>
      {/if}
    </div>

    <!-- Live meters -->
    <div class="meters-row">
      <!-- Temperature gauge (if reefer) -->
      {#if hasTemp}
        <div class="card meter-card">
          <h4 class="card-title">Temperature</h4>
          <div class="temp-display">
            <span class="temp-value mono" class:temp-ok={tempInRange} class:temp-bad={!tempInRange}>
              {load.currentTempF != null ? load.currentTempF + '\u00B0F' : '—'}
            </span>
            <span class="temp-range text-muted mono">
              Target: {load.tempMinF ?? '—'}&deg;F - {load.tempMaxF ?? '—'}&deg;F
            </span>
            <StatusBadge status={tempInRange ? 'active' : 'critical'} label={tempInRange ? 'In Range' : 'Out of Range'} />
          </div>
        </div>
      {/if}

      <!-- Cargo integrity -->
      <div class="card meter-card">
        <h4 class="card-title">Cargo Integrity</h4>
        <div class="integrity-display">
          <ProgressRing
            value={load.cargoIntegrity ?? 100}
            label="%"
            size={72}
            strokeWidth={5}
            variant="integrity"
            criticalThreshold={40}
            warningThreshold={70}
          />
          <div class="integrity-info">
            <span class="integrity-value mono" style="font-size: 14px;">
              {load.cargoIntegrity ?? 100}%
            </span>
            {#if (load.cargoIntegrity ?? 100) <= 40}
              <span class="integrity-warning text-orange" style="font-size: 11px;">
                Below rejection threshold
              </span>
            {/if}
          </div>
          <!-- Rejection threshold marker description -->
          <div class="threshold-marker text-muted" style="font-size: 10px; margin-top: 4px;">
            Rejection threshold: <span class="mono">40%</span>
          </div>
        </div>
      </div>

      <!-- Welfare rating (if livestock) -->
      {#if hasLivestock}
        <div class="card meter-card">
          <h4 class="card-title">Welfare Rating</h4>
          <div class="welfare-stars">
            {#each welfareStars as filled}
              <span class="star" class:star-filled={filled} class:star-empty={!filled}>
                &#9733;
              </span>
            {/each}
          </div>
        </div>
      {/if}
    </div>

    <!-- Seal status -->
    <div class="card seal-card">
      <div class="card-header">
        <h4 class="card-title">Seal Status</h4>
        <StatusBadge status={load.sealStatus || 'not_applied'} />
      </div>
      {#if load.sealNumber}
        <span class="seal-number mono text-muted">Seal #{load.sealNumber}</span>
      {/if}
    </div>

    <!-- Compliance checklist -->
    <div class="card compliance-card">
      <h4 class="card-title">Compliance Checklist</h4>
      <div class="compliance-list">
        {#each compliance as item}
          <div class="compliance-item" class:item-done={item.done}>
            <span class="compliance-icon">{item.done ? '\u2713' : '\u2717'}</span>
            <span class="compliance-label">{item.label}</span>
          </div>
        {/each}
      </div>
    </div>

    <!-- Payout tracker -->
    <div class="card payout-card">
      <div class="card-header">
        <h4 class="card-title">Estimated Payout</h4>
        <span class="payout-value payout-figure mono">{formatDollar(load.estimatedPayout)}</span>
      </div>
      {#if load.payoutBreakdown}
        <PayoutBreakdown breakdown={load.payoutBreakdown} />
      {/if}
    </div>

    <!-- Multi-stop progress -->
    {#if isMultiStop && load.stops}
      <div class="card stops-card">
        <h4 class="card-title">Route Progress</h4>
        <div class="stops-list">
          {#each load.stops as stop, i}
            <div
              class="stop-item"
              class:stop-completed={i < (load.currentStop || 1) - 1}
              class:stop-current={i === (load.currentStop || 1) - 1}
              class:stop-remaining={i > (load.currentStop || 1) - 1}
            >
              <span class="stop-indicator">
                {#if i < (load.currentStop || 1) - 1}
                  <span class="text-success">&#10003;</span>
                {:else if i === (load.currentStop || 1) - 1}
                  <span class="text-orange">&#9679;</span>
                {:else}
                  <span class="text-muted">&#9675;</span>
                {/if}
              </span>
              <span class="stop-name">{stop.label || `Stop ${i + 1}`}</span>
            </div>
          {/each}
        </div>
      </div>
    {/if}

    <!-- Action buttons -->
    <div class="load-actions">
      <button class="btn btn-secondary" on:click={handleDistress}>
        Distress Signal
      </button>
      <button class="btn btn-danger" on:click={requestAbandon}>
        Abandon Load
      </button>
    </div>

    <!-- Abandon confirmation dialog -->
    {#if showAbandonConfirm}
      <div class="dialog-overlay" on:click={cancelAbandon} on:keydown={(e) => e.key === 'Escape' && cancelAbandon()} role="dialog" tabindex="-1">
        <div class="dialog-panel" on:click|stopPropagation on:keydown|stopPropagation role="document">
          <h3>Abandon Load?</h3>
          <p class="text-muted">
            Abandoning this load will forfeit your deposit of
            <span class="mono">{formatDollar(load.depositPosted)}</span>
            and impact your reputation score. This action cannot be undone.
          </p>
          <div class="dialog-actions">
            <button class="btn btn-secondary" on:click={cancelAbandon}>Cancel</button>
            <button class="btn btn-danger" on:click={confirmAbandon} disabled={abandoning}>
              {abandoning ? 'Abandoning...' : 'Confirm Abandon'}
            </button>
          </div>
        </div>
      </div>
    {/if}
  </div>
{:else}
  <div class="empty-state">
    <span class="text-muted" style="font-size: 14px;">No active load. Visit the board to pick up a job.</span>
  </div>
{/if}

<style>
  .active-load-screen {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-md);
  }

  .load-header {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
  }

  .header-info {
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  .bol-number {
    font-size: 12px;
    color: var(--muted);
  }

  .cargo-title {
    margin: 0;
    font-size: 20px;
  }

  /* Destination card */
  .dest-row {
    display: flex;
    justify-content: space-between;
    align-items: flex-start;
  }

  .dest-info,
  .dest-distance {
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  .dest-label {
    font-size: 10px;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    font-family: var(--font-heading);
    font-weight: 700;
  }

  .dest-name {
    font-size: 16px;
    font-family: var(--font-heading);
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.03em;
  }

  .dest-value {
    font-size: 16px;
    color: var(--white);
  }

  /* Timer card */
  .timer-card {
    display: flex;
    align-items: center;
    justify-content: center;
    padding: var(--spacing-lg);
  }

  /* Meters */
  .meters-row {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
    gap: var(--spacing-sm);
  }

  .meter-card {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: var(--spacing-sm);
    text-align: center;
  }

  .temp-display {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: var(--spacing-xs);
  }

  .temp-value {
    font-size: 24px;
    font-weight: 500;
  }

  .temp-ok {
    color: var(--success);
  }

  .temp-bad {
    color: var(--orange);
  }

  .temp-range {
    font-size: 11px;
  }

  .integrity-display {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: var(--spacing-xs);
  }

  .integrity-info {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 2px;
  }

  .welfare-stars {
    display: flex;
    gap: 4px;
    font-size: 24px;
  }

  .star-filled {
    color: var(--warning);
  }

  .star-empty {
    color: var(--disabled);
  }

  /* Seal */
  .seal-number {
    font-size: 12px;
    margin-top: var(--spacing-xs);
  }

  /* Compliance */
  .compliance-list {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-xs);
  }

  .compliance-item {
    display: flex;
    align-items: center;
    gap: var(--spacing-sm);
    padding: var(--spacing-xs) 0;
  }

  .compliance-icon {
    font-size: 14px;
    width: 18px;
    text-align: center;
    color: var(--orange);
  }

  .item-done .compliance-icon {
    color: var(--success);
  }

  .compliance-label {
    font-size: 13px;
    color: var(--muted);
  }

  .item-done .compliance-label {
    color: var(--white);
  }

  /* Payout */
  .payout-value {
    font-size: 18px;
    color: var(--success);
    font-weight: 500;
  }

  /* Stops progress */
  .stops-list {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-xs);
    padding-left: var(--spacing-sm);
    border-left: 2px solid var(--border);
  }

  .stop-item {
    display: flex;
    align-items: center;
    gap: var(--spacing-sm);
    padding: var(--spacing-xs) 0;
  }

  .stop-indicator {
    font-size: 14px;
    width: 18px;
    text-align: center;
  }

  .stop-name {
    font-size: 13px;
    color: var(--white);
  }

  .stop-completed .stop-name {
    color: var(--muted);
    text-decoration: line-through;
  }

  .stop-current .stop-name {
    color: var(--orange);
    font-weight: 600;
  }

  .stop-remaining .stop-name {
    color: var(--muted);
  }

  /* Actions */
  .load-actions {
    display: flex;
    justify-content: space-between;
    gap: var(--spacing-sm);
    padding-top: var(--spacing-sm);
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

  .empty-state {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    padding: var(--spacing-xl);
    text-align: center;
  }
</style>
