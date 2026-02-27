<script>
  import { onMount, onDestroy } from 'svelte';
  import { playerData, insuranceData } from '../lib/stores.js';
  import { fetchNUI, onNUIMessage } from '../lib/nui.js';
  import ConfirmDialog from '../components/ConfirmDialog.svelte';

  /** Day policy prices by cargo tier */
  const DAY_PRICES = {
    0: 0,
    1: 200,
    2: 600,
    3: 1200,
    4: 1800,
  };

  /** Week policy prices by cargo tier */
  const WEEK_PRICES = {
    0: 0,
    1: 1000,
    2: 3200,
    3: 6500,
    4: 9500,
  };

  /** Tier labels for display */
  const TIER_NAMES = {
    suspended: 0,
    restricted: 0,
    probationary: 1,
    developing: 2,
    established: 3,
    professional: 3,
    elite: 4,
  };

  let activePolicy = null;
  let claims = [];
  let policyExpiry = 0;
  let confirmVisible = false;
  let confirmTitle = '';
  let confirmMessage = '';
  let pendingPurchase = null;

  $: repTier = $playerData.reputationTier;
  $: playerTierLevel = TIER_NAMES[repTier] ?? 2;
  $: dayPrice = DAY_PRICES[playerTierLevel] || 200;
  $: weekPrice = WEEK_PRICES[playerTierLevel] || 1000;

  $: hasActivePolicy = activePolicy !== null;
  $: policyTypeLabel = getPolicyTypeLabel(activePolicy?.type);

  function getPolicyTypeLabel(type) {
    if (type === 'single_load') return 'Single Load';
    if (type === 'day') return 'Day Policy';
    if (type === 'week') return 'Week Policy';
    return '--';
  }

  function formatMoney(amount) {
    return '$' + (amount || 0).toLocaleString('en-US');
  }

  function formatCountdown(seconds) {
    if (seconds <= 0) return 'Expired';
    const h = Math.floor(seconds / 3600);
    const m = Math.floor((seconds % 3600) / 60);
    if (h > 0) return `${h}h ${m}m remaining`;
    return `${m}m remaining`;
  }

  function formatClaimTime(seconds) {
    if (seconds <= 0) return 'Ready';
    const m = Math.floor(seconds / 60);
    const s = seconds % 60;
    return `${m}:${String(s).padStart(2, '0')}`;
  }

  function getClaimStatusClass(status) {
    if (status === 'pending') return 'claim-pending';
    if (status === 'approved') return 'claim-approved';
    if (status === 'paid') return 'claim-paid';
    if (status === 'denied') return 'claim-denied';
    return '';
  }

  function getClaimStatusLabel(status) {
    return (status || 'unknown').charAt(0).toUpperCase() + (status || 'unknown').slice(1);
  }

  function getTierCoverage(tier) {
    if (tier === 0) return 'Not Required';
    if (tier === 1) return 'Tier 1';
    if (tier === 2) return 'Tier 1-2';
    if (tier === 3) return 'Tier 1-3';
    if (tier === 4) return 'All Tiers';
    return 'Standard';
  }

  function promptPurchase(type) {
    let price = 0;
    let label = '';
    if (type === 'single_load') {
      price = 0;
      label = 'Single Load (8% of next load)';
    } else if (type === 'day') {
      price = dayPrice;
      label = 'Day Policy';
    } else if (type === 'week') {
      price = weekPrice;
      label = 'Week Policy';
    }

    confirmTitle = 'Purchase Insurance';
    confirmMessage = `Purchase ${label}${price > 0 ? ' for ' + formatMoney(price) : ''}? Coverage begins immediately.`;
    pendingPurchase = { type, price };
    confirmVisible = true;
  }

  async function confirmPurchase() {
    confirmVisible = false;
    if (pendingPurchase) {
      await fetchNUI('purchaseInsurance', pendingPurchase);
      pendingPurchase = null;
    }
  }

  function cancelPurchase() {
    confirmVisible = false;
    pendingPurchase = null;
  }

  // Countdown timer
  let countdownInterval;
  let claimCountdowns = {};

  function startCountdowns() {
    countdownInterval = setInterval(() => {
      if (policyExpiry > 0) policyExpiry = Math.max(0, policyExpiry - 1);

      claims = claims.map(c => {
        if (c.status === 'approved' && c.payoutCountdown > 0) {
          return { ...c, payoutCountdown: c.payoutCountdown - 1 };
        }
        return c;
      });
    }, 1000);
  }

  let cleanup;
  onMount(() => {
    cleanup = onNUIMessage((action, data) => {
      if (action === 'updateInsurance') {
        activePolicy = data.activePolicy || null;
        claims = data.claims || [];
        policyExpiry = data.policyExpiry || 0;
      }
      if (action === 'insurancePurchased') {
        activePolicy = data.policy;
        policyExpiry = data.expiry || 0;
      }
      if (action === 'claimUpdate') {
        claims = data.claims || claims;
      }
    });

    fetchNUI('getInsuranceData');
    startCountdowns();
  });

  onDestroy(() => {
    if (cleanup) cleanup();
    if (countdownInterval) clearInterval(countdownInterval);
  });
</script>

<div class="insurance-screen">
  <h1 class="screen-title">INSURANCE</h1>

  <!-- Current Policy Status -->
  <div class="section">
    <h2 class="section-title">CURRENT POLICY</h2>
    {#if hasActivePolicy}
      <div class="policy-card active">
        <div class="policy-header">
          <span class="policy-type">{policyTypeLabel}</span>
          <span class="policy-status status-active">Active</span>
        </div>
        <div class="policy-details">
          <div class="policy-row">
            <span class="policy-label">Coverage</span>
            <span class="policy-value">{getTierCoverage(playerTierLevel)}</span>
          </div>
          <div class="policy-row">
            <span class="policy-label">Expires</span>
            <span class="policy-value mono">{formatCountdown(policyExpiry)}</span>
          </div>
        </div>
      </div>
    {:else}
      <div class="policy-card warning">
        <div class="warning-icon">
          <svg width="24" height="24" viewBox="0 0 24 24" fill="var(--warning, #C87B03)">
            <path d="M1 21h22L12 2 1 21zm12-3h-2v-2h2v2zm0-4h-2v-4h2v4z"/>
          </svg>
        </div>
        <div class="warning-text">
          <span class="warning-title">No Active Policy</span>
          <span class="warning-desc">Tier 1+ loads require insurance before acceptance.</span>
        </div>
        <button class="btn-cta" on:click={() => document.querySelector('.purchase-section')?.scrollIntoView({ behavior: 'smooth' })}>
          Get Covered
        </button>
      </div>
    {/if}
  </div>

  <!-- Purchase Section -->
  <div class="section purchase-section">
    <h2 class="section-title">PURCHASE COVERAGE</h2>
    <div class="info-note">
      <svg width="14" height="14" viewBox="0 0 24 24" fill="var(--muted, #A8B4C8)">
        <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm1 15h-2v-6h2v6zm0-8h-2V7h2v2z"/>
      </svg>
      <span>T0 loads do not require insurance</span>
    </div>

    <div class="policy-cards">
      <!-- Single Load -->
      <div class="purchase-card">
        <div class="purchase-header">
          <h3 class="purchase-label">SINGLE LOAD</h3>
        </div>
        <div class="purchase-body">
          <p class="purchase-desc">Covers your next accepted load only. Premium calculated as a percentage of the load value.</p>
          <div class="purchase-price">
            <span class="price-value mono">8%</span>
            <span class="price-note">of next load value</span>
          </div>
          <ul class="purchase-features">
            <li>One load coverage</li>
            <li>Theft and abandonment</li>
            <li>Premium varies by load</li>
          </ul>
        </div>
        <button class="btn-purchase" on:click={() => promptPurchase('single_load')}>
          Purchase
        </button>
      </div>

      <!-- Day Policy -->
      <div class="purchase-card featured">
        <div class="purchase-header">
          <h3 class="purchase-label">DAY POLICY</h3>
          <span class="featured-badge">POPULAR</span>
        </div>
        <div class="purchase-body">
          <p class="purchase-desc">Covers all loads accepted within 24 hours. Best value for active drivers.</p>
          <div class="purchase-price">
            <span class="price-value mono">{formatMoney(dayPrice)}</span>
            <span class="price-note">24 hours</span>
          </div>
          <ul class="purchase-features">
            <li>All loads for 24 hours</li>
            <li>Theft and abandonment</li>
            <li>Multiple loads covered</li>
          </ul>
          <div class="tier-price-table">
            <span class="tier-table-title">Price by Tier Level:</span>
            <div class="tier-rows">
              <span class="tier-row"><span class="tier-label">T1</span><span class="tier-val mono">{formatMoney(DAY_PRICES[1])}</span></span>
              <span class="tier-row"><span class="tier-label">T2</span><span class="tier-val mono">{formatMoney(DAY_PRICES[2])}</span></span>
              <span class="tier-row"><span class="tier-label">T3</span><span class="tier-val mono">{formatMoney(DAY_PRICES[3])}</span></span>
              <span class="tier-row"><span class="tier-label">T4</span><span class="tier-val mono">{formatMoney(DAY_PRICES[4])}</span></span>
            </div>
          </div>
        </div>
        <button class="btn-purchase" on:click={() => promptPurchase('day')}>
          Purchase {formatMoney(dayPrice)}
        </button>
      </div>

      <!-- Week Policy -->
      <div class="purchase-card">
        <div class="purchase-header">
          <h3 class="purchase-label">WEEK POLICY</h3>
        </div>
        <div class="purchase-body">
          <p class="purchase-desc">Full week of coverage. Best for professional drivers running multiple loads daily.</p>
          <div class="purchase-price">
            <span class="price-value mono">{formatMoney(weekPrice)}</span>
            <span class="price-note">7 days</span>
          </div>
          <ul class="purchase-features">
            <li>All loads for 7 days</li>
            <li>Theft and abandonment</li>
            <li>Best per-load rate</li>
          </ul>
          <div class="tier-price-table">
            <span class="tier-table-title">Price by Tier Level:</span>
            <div class="tier-rows">
              <span class="tier-row"><span class="tier-label">T1</span><span class="tier-val mono">{formatMoney(WEEK_PRICES[1])}</span></span>
              <span class="tier-row"><span class="tier-label">T2</span><span class="tier-val mono">{formatMoney(WEEK_PRICES[2])}</span></span>
              <span class="tier-row"><span class="tier-label">T3</span><span class="tier-val mono">{formatMoney(WEEK_PRICES[3])}</span></span>
              <span class="tier-row"><span class="tier-label">T4</span><span class="tier-val mono">{formatMoney(WEEK_PRICES[4])}</span></span>
            </div>
          </div>
        </div>
        <button class="btn-purchase" on:click={() => promptPurchase('week')}>
          Purchase {formatMoney(weekPrice)}
        </button>
      </div>
    </div>
  </div>

  <!-- Claims Section -->
  <div class="section">
    <h2 class="section-title">CLAIMS</h2>
    <div class="claims-instruction">
      <svg width="14" height="14" viewBox="0 0 24 24" fill="var(--muted, #A8B4C8)">
        <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm1 15h-2v-6h2v6zm0-8h-2V7h2v2z"/>
      </svg>
      <span>File a claim at any Vapid Commercial Insurance office. Bring your BOL.</span>
    </div>

    {#if claims.length === 0}
      <div class="empty-state">
        <p>No recent claims.</p>
      </div>
    {:else}
      <div class="claims-list">
        {#each claims as claim}
          <div class="claim-row {getClaimStatusClass(claim.status)}">
            <div class="claim-info">
              <div class="claim-bol mono">BOL #{claim.bolNumber}</div>
              <div class="claim-type">{claim.claimType === 'theft' ? 'Theft' : 'Abandonment'}</div>
            </div>
            <div class="claim-amount">
              <span class="claim-money mono">{formatMoney(claim.amount)}</span>
              <span class="claim-status-badge">{getClaimStatusLabel(claim.status)}</span>
            </div>
            {#if claim.status === 'approved' && claim.payoutCountdown > 0}
              <div class="claim-countdown">
                <span class="countdown-label">Payout in</span>
                <span class="countdown-value mono">{formatClaimTime(claim.payoutCountdown)}</span>
              </div>
            {/if}
          </div>
        {/each}
      </div>
    {/if}
  </div>
</div>

<ConfirmDialog
  visible={confirmVisible}
  title={confirmTitle}
  message={confirmMessage}
  confirmText="Purchase"
  on:confirm={confirmPurchase}
  on:cancel={cancelPurchase}
/>

<style>
  .insurance-screen {
    padding: 20px;
    overflow-y: auto;
    max-height: 100%;
  }

  .screen-title {
    font-family: 'Barlow Condensed', sans-serif;
    font-weight: 700;
    font-size: 22px;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    color: var(--white, #FFFFFF);
    margin: 0 0 16px 0;
  }

  .section {
    margin-bottom: 24px;
  }

  .section-title {
    font-family: 'Barlow Condensed', sans-serif;
    font-weight: 700;
    font-size: 14px;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    color: var(--muted, #A8B4C8);
    margin: 0 0 12px 0;
    padding-bottom: 8px;
    border-bottom: 1px solid var(--border, #1E3A6E);
  }

  .mono {
    font-family: 'JetBrains Mono', monospace;
  }

  /* Policy Status Card */
  .policy-card {
    background: var(--navy-dark, #051229);
    border: 1px solid var(--border, #1E3A6E);
    border-radius: 6px;
    padding: 16px;
  }

  .policy-card.active {
    border-color: var(--success, #2D7A3E);
  }

  .policy-card.warning {
    border-color: var(--warning, #C87B03);
    display: flex;
    align-items: center;
    gap: 14px;
  }

  .policy-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 12px;
  }

  .policy-type {
    font-family: 'Barlow Condensed', sans-serif;
    font-weight: 700;
    font-size: 16px;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    color: var(--white, #FFFFFF);
  }

  .policy-status {
    font-family: 'Barlow Condensed', sans-serif;
    font-weight: 700;
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    padding: 3px 10px;
    border-radius: 3px;
  }

  .status-active {
    color: var(--success, #2D7A3E);
    background: rgba(45, 122, 62, 0.15);
  }

  .policy-details {
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  .policy-row {
    display: flex;
    justify-content: space-between;
    align-items: center;
  }

  .policy-label {
    font-family: 'Inter', sans-serif;
    font-size: 13px;
    color: var(--muted, #A8B4C8);
  }

  .policy-value {
    font-family: 'Inter', sans-serif;
    font-size: 13px;
    color: var(--white, #FFFFFF);
  }

  /* Warning State */
  .warning-icon {
    flex-shrink: 0;
    display: flex;
    align-items: center;
  }

  .warning-text {
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .warning-title {
    font-family: 'Barlow Condensed', sans-serif;
    font-weight: 700;
    font-size: 14px;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    color: var(--warning, #C87B03);
  }

  .warning-desc {
    font-family: 'Inter', sans-serif;
    font-size: 12px;
    color: var(--muted, #A8B4C8);
  }

  .btn-cta {
    font-family: 'Barlow Condensed', sans-serif;
    font-weight: 700;
    font-size: 13px;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    background: var(--orange, #C83803);
    color: var(--white, #FFFFFF);
    border: none;
    border-radius: 4px;
    padding: 10px 18px;
    cursor: pointer;
    flex-shrink: 0;
    transition: background 0.15s;
  }

  .btn-cta:hover {
    background: var(--orange-dim, #8A2702);
  }

  /* Info Note */
  .info-note {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 8px 12px;
    background: rgba(30, 58, 110, 0.3);
    border-radius: 4px;
    margin-bottom: 14px;
    font-family: 'Inter', sans-serif;
    font-size: 12px;
    color: var(--muted, #A8B4C8);
  }

  /* Purchase Cards */
  .policy-cards {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 12px;
  }

  .purchase-card {
    background: var(--navy-dark, #051229);
    border: 1px solid var(--border, #1E3A6E);
    border-radius: 8px;
    display: flex;
    flex-direction: column;
    overflow: hidden;
  }

  .purchase-card.featured {
    border-color: var(--orange, #C83803);
  }

  .purchase-header {
    padding: 12px 14px;
    display: flex;
    justify-content: space-between;
    align-items: center;
    border-bottom: 1px solid var(--border, #1E3A6E);
  }

  .purchase-label {
    font-family: 'Barlow Condensed', sans-serif;
    font-weight: 700;
    font-size: 14px;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    color: var(--white, #FFFFFF);
    margin: 0;
  }

  .featured-badge {
    font-family: 'Barlow Condensed', sans-serif;
    font-weight: 700;
    font-size: 9px;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: var(--orange, #C83803);
    background: rgba(200, 56, 3, 0.12);
    padding: 2px 8px;
    border-radius: 3px;
  }

  .purchase-body {
    padding: 14px;
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 10px;
  }

  .purchase-desc {
    font-family: 'Inter', sans-serif;
    font-size: 12px;
    color: var(--muted, #A8B4C8);
    line-height: 1.4;
    margin: 0;
  }

  .purchase-price {
    display: flex;
    align-items: baseline;
    gap: 6px;
  }

  .price-value {
    font-size: 24px;
    font-weight: 700;
    color: var(--white, #FFFFFF);
  }

  .price-note {
    font-family: 'Inter', sans-serif;
    font-size: 12px;
    color: var(--disabled, #3A4A5C);
  }

  .purchase-features {
    list-style: none;
    padding: 0;
    margin: 0;
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  .purchase-features li {
    font-family: 'Inter', sans-serif;
    font-size: 11px;
    color: var(--muted, #A8B4C8);
    padding-left: 14px;
    position: relative;
  }

  .purchase-features li::before {
    content: '\2713';
    position: absolute;
    left: 0;
    color: var(--success, #2D7A3E);
    font-size: 10px;
  }

  .tier-price-table {
    margin-top: 4px;
    padding: 8px 10px;
    background: rgba(30, 58, 110, 0.2);
    border-radius: 4px;
  }

  .tier-table-title {
    font-family: 'Inter', sans-serif;
    font-size: 10px;
    color: var(--disabled, #3A4A5C);
    display: block;
    margin-bottom: 4px;
  }

  .tier-rows {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 2px 12px;
  }

  .tier-row {
    display: flex;
    justify-content: space-between;
    align-items: center;
    font-size: 10px;
  }

  .tier-label {
    font-family: 'Barlow Condensed', sans-serif;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    color: var(--muted, #A8B4C8);
  }

  .tier-val {
    font-size: 10px;
    color: var(--white, #FFFFFF);
  }

  .btn-purchase {
    font-family: 'Barlow Condensed', sans-serif;
    font-weight: 700;
    font-size: 14px;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    background: var(--orange, #C83803);
    color: var(--white, #FFFFFF);
    border: none;
    padding: 12px 16px;
    cursor: pointer;
    transition: background 0.15s;
  }

  .btn-purchase:hover {
    background: var(--orange-dim, #8A2702);
  }

  /* Claims */
  .claims-instruction {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 8px 12px;
    background: rgba(30, 58, 110, 0.3);
    border-radius: 4px;
    margin-bottom: 12px;
    font-family: 'Inter', sans-serif;
    font-size: 12px;
    color: var(--muted, #A8B4C8);
  }

  .claims-list {
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  .claim-row {
    background: var(--navy-dark, #051229);
    border: 1px solid var(--border, #1E3A6E);
    border-radius: 6px;
    padding: 12px 14px;
    display: flex;
    align-items: center;
    gap: 16px;
  }

  .claim-row.claim-pending {
    border-left: 3px solid var(--warning, #C87B03);
  }

  .claim-row.claim-approved {
    border-left: 3px solid var(--success, #2D7A3E);
  }

  .claim-row.claim-paid {
    border-left: 3px solid var(--muted, #A8B4C8);
  }

  .claim-row.claim-denied {
    border-left: 3px solid var(--orange, #C83803);
  }

  .claim-info {
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .claim-bol {
    font-size: 13px;
    font-weight: 600;
    color: var(--white, #FFFFFF);
  }

  .claim-type {
    font-family: 'Inter', sans-serif;
    font-size: 11px;
    color: var(--muted, #A8B4C8);
    text-transform: capitalize;
  }

  .claim-amount {
    display: flex;
    flex-direction: column;
    align-items: flex-end;
    gap: 2px;
  }

  .claim-money {
    font-size: 14px;
    font-weight: 600;
    color: var(--white, #FFFFFF);
  }

  .claim-status-badge {
    font-family: 'Barlow Condensed', sans-serif;
    font-weight: 700;
    font-size: 10px;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    color: var(--muted, #A8B4C8);
  }

  .claim-countdown {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 2px;
    padding-left: 12px;
    border-left: 1px solid var(--border, #1E3A6E);
  }

  .countdown-label {
    font-family: 'Inter', sans-serif;
    font-size: 10px;
    color: var(--disabled, #3A4A5C);
  }

  .countdown-value {
    font-size: 14px;
    font-weight: 600;
    color: var(--warning, #C87B03);
  }

  .empty-state {
    text-align: center;
    padding: 24px 20px;
    background: var(--navy-dark, #051229);
    border: 1px solid var(--border, #1E3A6E);
    border-radius: 6px;
  }

  .empty-state p {
    font-family: 'Inter', sans-serif;
    font-size: 14px;
    color: var(--disabled, #3A4A5C);
    margin: 0;
  }
</style>
