<script>
  import { createEventDispatcher } from 'svelte';
  import TierBadge from './TierBadge.svelte';
  import StatusBadge from './StatusBadge.svelte';
  import PayoutBreakdown from './PayoutBreakdown.svelte';

  /**
   * LoadCard — Reusable load card with collapsed/expanded state.
   * @prop {object} load - Load data object
   * @prop {boolean} [expandable=true] - Allow expanding
   */
  export let load = {};
  export let expandable = true;

  const dispatch = createEventDispatcher();

  let expanded = false;

  function toggleExpand() {
    if (expandable) {
      expanded = !expanded;
    }
  }

  function handleViewDetail() {
    dispatch('viewDetail', { load });
  }

  function handleReserve() {
    dispatch('reserve', { load });
  }

  function handleAccept() {
    dispatch('accept', { load });
  }

  function formatDollar(n) {
    if (n == null) return '—';
    return '$' + Number(n).toLocaleString('en-US');
  }

  function formatDistance(d) {
    if (d == null) return '—';
    return Number(d).toFixed(1) + ' mi';
  }

  $: hasRequirements = load.requiredLicense !== 'none' || load.requiredEndorsement || load.requiredCertification;
  $: isReserved = load.boardStatus === 'reserved';
  $: isSurge = load.surgeActive;
</script>

<div class="load-card" class:surge-active={isSurge} class:card-expanded={expanded}>
  <!-- Collapsed view -->
  <button class="card-main" on:click={toggleExpand}>
    <div class="card-row-top">
      <div class="card-left">
        <TierBadge tier={load.tier} size="small" />
        <span class="cargo-type">{load.cargoType || 'Cargo'}</span>
        {#if load.cargoSubtype}
          <span class="cargo-subtype text-muted">({load.cargoSubtype})</span>
        {/if}
      </div>
      <div class="card-right">
        {#if isSurge}
          <span class="badge badge-surge">+{load.surgePercentage}%</span>
        {/if}
        <span class="payout-figure mono">{formatDollar(load.basePayout || load.basePayoutRental)}</span>
      </div>
    </div>

    <div class="card-row-route">
      <span class="route-text text-muted">
        {load.originLabel || '—'}
        <span class="route-arrow">&rarr;</span>
        {load.destinationLabel || '—'}
      </span>
      <span class="distance mono text-muted">{formatDistance(load.distanceMiles)}</span>
    </div>

    {#if hasRequirements}
      <div class="card-row-reqs">
        {#if load.requiredLicense && load.requiredLicense !== 'none'}
          <span class="req-icon" title="CDL Required: {load.requiredLicense}">CDL</span>
        {/if}
        {#if load.requiredEndorsement}
          <span class="req-icon" title="Endorsement: {load.requiredEndorsement}">
            {#if load.requiredEndorsement === 'tanker'}TKR
            {:else if load.requiredEndorsement === 'hazmat'}HAZ
            {:else}{load.requiredEndorsement.substring(0, 3).toUpperCase()}
            {/if}
          </span>
        {/if}
        {#if load.requiredCertification}
          <span class="req-icon" title="Cert: {load.requiredCertification}">CERT</span>
        {/if}
      </div>
    {/if}

    {#if expandable}
      <span class="expand-indicator">{expanded ? '\u25B2' : '\u25BC'}</span>
    {/if}
  </button>

  <!-- Expanded view -->
  {#if expanded}
    <div class="card-expanded-body fade-in">
      <div class="detail-grid">
        <div class="detail-item">
          <span class="detail-label">Shipper</span>
          <span class="detail-value">{load.shipperName || '—'}</span>
        </div>
        <div class="detail-item">
          <span class="detail-label">Weight</span>
          <span class="detail-value mono">{load.weightLbs ? load.weightLbs.toLocaleString() + ' lbs' : '—'}</span>
        </div>
        <div class="detail-item">
          <span class="detail-label">Vehicle Type</span>
          <span class="detail-value">{load.requiredVehicleType || 'Any'}</span>
        </div>
        <div class="detail-item">
          <span class="detail-label">License</span>
          <span class="detail-value">{load.requiredLicense === 'none' ? 'None' : load.requiredLicense?.toUpperCase()}</span>
        </div>
        {#if load.requiredCertification}
          <div class="detail-item">
            <span class="detail-label">Certification</span>
            <span class="detail-value">{load.requiredCertification}</span>
          </div>
        {/if}
        <div class="detail-item">
          <span class="detail-label">Deposit</span>
          <span class="detail-value mono">{formatDollar(load.depositAmount)}</span>
        </div>
      </div>

      {#if load.payoutBreakdown}
        <PayoutBreakdown breakdown={load.payoutBreakdown} />
      {/if}

      <div class="card-actions">
        <button class="btn btn-secondary btn-sm" on:click|stopPropagation={handleViewDetail}>
          View Details
        </button>
        {#if isReserved}
          <button class="btn btn-primary btn-sm" on:click|stopPropagation={handleAccept}>
            Accept Load
          </button>
        {:else}
          <button class="btn btn-primary btn-sm" on:click|stopPropagation={handleReserve}>
            Reserve (3:00)
          </button>
        {/if}
      </div>
    </div>
  {/if}
</div>

<style>
  .load-card {
    background: var(--navy-mid);
    border: 1px solid var(--border);
    border-radius: var(--radius-md);
    overflow: hidden;
    transition: border-color 0.2s ease, box-shadow 0.2s ease;
  }

  .load-card:hover {
    border-color: rgba(30, 58, 110, 0.8);
  }

  .surge-active {
    border-color: var(--orange);
    box-shadow: 0 0 8px rgba(200, 56, 3, 0.15);
  }

  .card-main {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-xs);
    width: 100%;
    padding: var(--spacing-md);
    background: none;
    border: none;
    color: var(--white);
    cursor: pointer;
    text-align: left;
    position: relative;
  }

  .card-row-top {
    display: flex;
    align-items: center;
    justify-content: space-between;
  }

  .card-left {
    display: flex;
    align-items: center;
    gap: var(--spacing-sm);
  }

  .cargo-type {
    font-family: var(--font-heading);
    font-weight: 700;
    font-size: 14px;
    text-transform: uppercase;
    letter-spacing: 0.03em;
  }

  .cargo-subtype {
    font-size: 12px;
    font-family: var(--font-body);
    text-transform: none;
    letter-spacing: normal;
  }

  .card-right {
    display: flex;
    align-items: center;
    gap: var(--spacing-sm);
  }

  .payout-figure {
    font-size: 15px;
    color: var(--success);
    font-weight: 500;
  }

  .card-row-route {
    display: flex;
    align-items: center;
    justify-content: space-between;
  }

  .route-text {
    font-size: 13px;
  }

  .route-arrow {
    color: var(--orange);
    margin: 0 4px;
  }

  .distance {
    font-size: 12px;
  }

  .card-row-reqs {
    display: flex;
    gap: var(--spacing-xs);
    margin-top: 2px;
  }

  .req-icon {
    display: inline-flex;
    align-items: center;
    padding: 1px 5px;
    border-radius: 3px;
    background: rgba(30, 58, 110, 0.5);
    color: var(--muted);
    font-family: var(--font-heading);
    font-weight: 700;
    font-size: 9px;
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }

  .expand-indicator {
    position: absolute;
    bottom: 6px;
    right: var(--spacing-md);
    font-size: 10px;
    color: var(--muted);
  }

  .card-expanded-body {
    padding: 0 var(--spacing-md) var(--spacing-md);
    border-top: 1px solid var(--border);
    display: flex;
    flex-direction: column;
    gap: var(--spacing-md);
    padding-top: var(--spacing-md);
  }

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
  }

  .card-actions {
    display: flex;
    justify-content: flex-end;
    gap: var(--spacing-sm);
  }

  .badge-surge {
    padding: 2px 6px;
    border-radius: var(--radius-sm);
    background: var(--orange);
    color: var(--white);
    font-family: var(--font-heading);
    font-weight: 700;
    font-size: 10px;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    animation: surgeGlow 2s ease-in-out infinite;
  }

  @keyframes surgeGlow {
    0%, 100% { box-shadow: 0 0 4px rgba(200, 56, 3, 0.3); }
    50% { box-shadow: 0 0 12px rgba(200, 56, 3, 0.6); }
  }
</style>
