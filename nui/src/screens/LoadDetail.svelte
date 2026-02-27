<script>
  import { createEventDispatcher } from 'svelte';
  import { playerData } from '../lib/stores.js';
  import { fetchNUI } from '../lib/nui.js';
  import TierBadge from '../components/TierBadge.svelte';
  import PayoutBreakdown from '../components/PayoutBreakdown.svelte';
  import StatusBadge from '../components/StatusBadge.svelte';

  /**
   * @prop {object} load - Full load detail data
   */
  export let load = null;

  const dispatch = createEventDispatcher();

  let accepting = false;

  function goBack() {
    dispatch('back');
  }

  async function handleAccept() {
    if (!load || accepting) return;
    accepting = true;
    await fetchNUI('acceptLoad', { loadId: load.id });
    accepting = false;
  }

  function formatDollar(n) {
    if (n == null) return '—';
    return '$' + Number(n).toLocaleString('en-US');
  }

  function formatDistance(d) {
    if (d == null) return '—';
    return Number(d).toFixed(1) + ' mi';
  }

  function formatWeight(w) {
    if (w == null) return '—';
    return Number(w).toLocaleString() + ' lbs';
  }

  $: player = $playerData;

  // Requirements checklist
  $: requirements = buildRequirements(load, player);

  function buildRequirements(l, p) {
    if (!l) return [];
    const reqs = [];

    // CDL class
    if (l.requiredLicense && l.requiredLicense !== 'none') {
      const hasLicense = p.licenses?.some(
        lic => lic.type === l.requiredLicense && lic.status === 'active'
      );
      reqs.push({
        label: `CDL ${l.requiredLicense.replace('_', ' ').toUpperCase()}`,
        met: hasLicense,
      });
    }

    // Endorsement
    if (l.requiredEndorsement) {
      const hasEndorsement = p.licenses?.some(
        lic => lic.type === l.requiredEndorsement && lic.status === 'active'
      );
      reqs.push({
        label: `Endorsement: ${l.requiredEndorsement.replace('_', ' ').toUpperCase()}`,
        met: hasEndorsement,
      });
    }

    // Certification
    if (l.requiredCertification) {
      const hasCert = p.certifications?.some(
        cert => cert.type === l.requiredCertification && cert.status === 'active'
      );
      reqs.push({
        label: `Certification: ${l.requiredCertification.replace(/_/g, ' ')}`,
        met: hasCert,
      });
    }

    return reqs;
  }

  $: allRequirementsMet = requirements.every(r => r.met);
  $: isMultiStop = load?.isMultiStop || (load?.stops && load.stops.length > 1);
</script>

{#if load}
  <div class="load-detail-screen">
    <!-- Back button -->
    <button class="back-btn" on:click={goBack}>
      <span class="back-arrow">&larr;</span> Back to Board
    </button>

    <!-- Header -->
    <div class="detail-header">
      <div class="header-left">
        <TierBadge tier={load.tier} />
        <h2 class="cargo-title">{load.cargoType || 'Cargo'}</h2>
        {#if load.cargoSubtype}
          <span class="cargo-sub text-muted">({load.cargoSubtype})</span>
        {/if}
      </div>
      {#if load.surgeActive}
        <span class="badge badge-surge">SURGE +{load.surgePercentage}%</span>
      {/if}
    </div>

    <!-- Route display -->
    <div class="card route-card">
      <h3 class="card-title">Route</h3>
      <div class="route-display">
        {#if isMultiStop}
          <div class="multi-stop-route">
            <div class="route-point origin">
              <span class="route-dot"></span>
              <span class="route-location">{load.originLabel}</span>
            </div>
            {#each (load.stops || []) as stop, i}
              <div class="route-connector"></div>
              <div class="route-point stop">
                <span class="route-dot stop-dot"></span>
                <span class="route-location">{stop.label || `Stop ${i + 1}`}</span>
              </div>
            {/each}
            <div class="route-connector"></div>
            <div class="route-point destination">
              <span class="route-dot dest-dot"></span>
              <span class="route-location">{load.destinationLabel}</span>
            </div>
          </div>
        {:else}
          <div class="single-route">
            <div class="route-point origin">
              <span class="route-dot"></span>
              <span class="route-location">{load.originLabel || '—'}</span>
            </div>
            <div class="route-connector"></div>
            <div class="route-point destination">
              <span class="route-dot dest-dot"></span>
              <span class="route-location">{load.destinationLabel || '—'}</span>
            </div>
          </div>
        {/if}
      </div>
      <div class="route-distance">
        <span class="text-muted">Total Distance:</span>
        <span class="mono">{formatDistance(load.distanceMiles)}</span>
      </div>
    </div>

    <!-- Cargo details -->
    <div class="card cargo-card">
      <h3 class="card-title">Cargo Details</h3>
      <div class="detail-grid">
        <div class="detail-item">
          <span class="detail-label">Type</span>
          <span class="detail-value">{load.cargoType || '—'}</span>
        </div>
        <div class="detail-item">
          <span class="detail-label">Weight</span>
          <span class="detail-value mono">{formatWeight(load.weightLbs)}</span>
        </div>
        {#if load.tempMinF != null && load.tempMaxF != null}
          <div class="detail-item">
            <span class="detail-label">Temperature Range</span>
            <span class="detail-value mono">{load.tempMinF}&deg;F - {load.tempMaxF}&deg;F</span>
          </div>
        {/if}
        {#if load.hazmatClass}
          <div class="detail-item">
            <span class="detail-label">Hazmat Class</span>
            <span class="detail-value">
              <StatusBadge status="warning" label="Class {load.hazmatClass}" />
              {#if load.hazmatUnNumber}
                <span class="mono text-muted" style="margin-left: 6px;">UN{load.hazmatUnNumber}</span>
              {/if}
            </span>
          </div>
        {/if}
        <div class="detail-item">
          <span class="detail-label">Shipper</span>
          <span class="detail-value">{load.shipperName || '—'}</span>
        </div>
        <div class="detail-item">
          <span class="detail-label">Vehicle Type</span>
          <span class="detail-value">{load.requiredVehicleType || 'Any'}</span>
        </div>
      </div>
    </div>

    <!-- Payout breakdown -->
    {#if load.payoutBreakdown}
      <PayoutBreakdown breakdown={load.payoutBreakdown} startExpanded={true} />
    {:else}
      <div class="card payout-card">
        <h3 class="card-title">Estimated Payout</h3>
        <span class="payout-figure mono" style="font-size: 20px;">
          {formatDollar(load.basePayout || load.basePayoutRental)}
        </span>
      </div>
    {/if}

    <!-- Requirements checklist -->
    {#if requirements.length > 0}
      <div class="card requirements-card">
        <h3 class="card-title">Requirements</h3>
        <div class="requirements-list">
          {#each requirements as req}
            <div class="req-row" class:req-met={req.met} class:req-unmet={!req.met}>
              <span class="req-icon">{req.met ? '\u2713' : '\u2717'}</span>
              <span class="req-label">{req.label}</span>
            </div>
          {/each}
        </div>
      </div>
    {/if}

    <!-- Deposit and delivery window -->
    <div class="card info-card">
      <div class="info-row">
        <div class="detail-item">
          <span class="detail-label">Deposit</span>
          <span class="detail-value mono">{formatDollar(load.depositAmount)}</span>
        </div>
        <div class="detail-item">
          <span class="detail-label">Delivery Window</span>
          <span class="detail-value mono">
            {load.deliveryWindowMinutes ? load.deliveryWindowMinutes + ' min' : '—'}
          </span>
        </div>
      </div>
    </div>

    <!-- Actions -->
    <div class="detail-actions">
      <button class="btn btn-secondary" on:click={goBack}>Back</button>
      <button
        class="btn btn-primary"
        on:click={handleAccept}
        disabled={!allRequirementsMet || accepting}
      >
        {accepting ? 'Accepting...' : 'Accept Load'}
      </button>
    </div>
  </div>
{:else}
  <div class="empty-state">
    <span class="text-muted">No load selected.</span>
    <button class="btn btn-secondary" on:click={goBack}>Back to Board</button>
  </div>
{/if}

<style>
  .load-detail-screen {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-md);
  }

  .back-btn {
    display: inline-flex;
    align-items: center;
    gap: var(--spacing-xs);
    background: none;
    border: none;
    color: var(--muted);
    font-size: 13px;
    cursor: pointer;
    padding: 0;
    margin-bottom: var(--spacing-xs);
    transition: color 0.15s ease;
  }

  .back-btn:hover {
    color: var(--white);
  }

  .back-arrow {
    font-size: 16px;
  }

  .detail-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
  }

  .header-left {
    display: flex;
    align-items: center;
    gap: var(--spacing-sm);
  }

  .cargo-title {
    margin: 0;
    font-size: 20px;
  }

  .cargo-sub {
    font-size: 14px;
    font-family: var(--font-body);
    text-transform: none;
    letter-spacing: normal;
  }

  .badge-surge {
    padding: 3px 10px;
    border-radius: var(--radius-sm);
    background: var(--orange);
    color: var(--white);
    font-family: var(--font-heading);
    font-weight: 700;
    font-size: 12px;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    animation: surgeGlow 2s ease-in-out infinite;
  }

  @keyframes surgeGlow {
    0%, 100% { box-shadow: 0 0 4px rgba(200, 56, 3, 0.3); }
    50% { box-shadow: 0 0 12px rgba(200, 56, 3, 0.6); }
  }

  /* Route display */
  .route-display {
    margin: var(--spacing-md) 0;
  }

  .single-route,
  .multi-stop-route {
    display: flex;
    flex-direction: column;
    padding-left: var(--spacing-sm);
  }

  .route-point {
    display: flex;
    align-items: center;
    gap: var(--spacing-sm);
    padding: var(--spacing-xs) 0;
  }

  .route-dot {
    width: 10px;
    height: 10px;
    border-radius: 50%;
    background: var(--border);
    flex-shrink: 0;
  }

  .route-point.origin .route-dot {
    background: var(--success);
  }

  .dest-dot {
    background: var(--orange);
  }

  .stop-dot {
    background: var(--warning);
  }

  .route-location {
    font-size: 14px;
    color: var(--white);
  }

  .route-connector {
    width: 2px;
    height: 16px;
    background: var(--border);
    margin-left: 4px;
  }

  .route-distance {
    display: flex;
    align-items: center;
    gap: var(--spacing-sm);
    font-size: 13px;
    padding-top: var(--spacing-sm);
    border-top: 1px solid var(--border);
  }

  /* Detail grid */
  .detail-grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: var(--spacing-sm);
  }

  .detail-item {
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .detail-label {
    font-size: 10px;
    color: var(--muted);
    text-transform: uppercase;
    letter-spacing: 0.04em;
    font-family: var(--font-heading);
    font-weight: 700;
  }

  .detail-value {
    font-size: 13px;
    color: var(--white);
    display: flex;
    align-items: center;
  }

  .payout-figure {
    color: var(--success);
    font-weight: 500;
  }

  /* Requirements */
  .requirements-list {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-xs);
  }

  .req-row {
    display: flex;
    align-items: center;
    gap: var(--spacing-sm);
    padding: var(--spacing-xs) 0;
  }

  .req-icon {
    font-size: 14px;
    width: 18px;
    text-align: center;
  }

  .req-met .req-icon {
    color: var(--success);
  }

  .req-unmet .req-icon {
    color: var(--orange);
  }

  .req-label {
    font-size: 13px;
  }

  .req-met .req-label {
    color: var(--white);
  }

  .req-unmet .req-label {
    color: var(--muted);
  }

  /* Info row */
  .info-row {
    display: flex;
    gap: var(--spacing-xl);
  }

  /* Actions */
  .detail-actions {
    display: flex;
    justify-content: flex-end;
    gap: var(--spacing-sm);
    padding-top: var(--spacing-sm);
  }

  .empty-state {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: var(--spacing-lg);
    padding: var(--spacing-xl);
  }
</style>
