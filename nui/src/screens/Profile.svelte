<script>
  import { playerData } from '../lib/stores.js';
  import { fetchNUI } from '../lib/nui.js';

  let activeTab = 'credentials';

  /** Reputation tier thresholds for progress bar */
  const TIER_THRESHOLDS = {
    suspended: { min: 0, max: 0 },
    restricted: { min: 1, max: 199 },
    probationary: { min: 200, max: 399 },
    developing: { min: 400, max: 599 },
    established: { min: 600, max: 799 },
    professional: { min: 800, max: 999 },
    elite: { min: 1000, max: 1000 },
  };

  const TIER_LABELS = {
    suspended: 'Suspended',
    restricted: 'Restricted',
    probationary: 'Probationary',
    developing: 'Developing',
    established: 'Established',
    professional: 'Professional',
    elite: 'Elite',
  };

  const TIER_ORDER = ['suspended', 'restricted', 'probationary', 'developing', 'established', 'professional', 'elite'];

  /** Shipper reputation tiers */
  const SHIPPER_TIERS = {
    unknown: { label: 'Unknown', min: 0, max: 49, color: 'var(--disabled)' },
    familiar: { label: 'Familiar', min: 50, max: 149, color: 'var(--muted)' },
    established: { label: 'Established', min: 150, max: 349, color: 'var(--warning)' },
    trusted: { label: 'Trusted', min: 350, max: 699, color: 'var(--success)' },
    preferred: { label: 'Preferred', min: 700, max: 1000, color: 'var(--orange)' },
    blacklisted: { label: 'Blacklisted', min: 0, max: 0, color: '#8B0000' },
  };

  const SHIPPER_TIER_ORDER = ['unknown', 'familiar', 'established', 'trusted', 'preferred'];

  /** Cluster icons for shippers */
  const CLUSTER_ICONS = {
    luxury: '\u2666',
    agricultural: '\u2618',
    industrial: '\u2699',
    government: '\u2605',
    general: '\u25CF',
  };

  /** Shipper reputations (populated via NUI message) */
  let shipperReputations = [];

  /** Certifications available for application */
  let availableCerts = [];

  $: licenses = $playerData.licenses || [];
  $: certifications = $playerData.certifications || [];

  $: classB = licenses.find(l => l.type === 'class_b');
  $: classA = licenses.find(l => l.type === 'class_a');
  $: tanker = licenses.find(l => l.type === 'tanker');
  $: hazmat = licenses.find(l => l.type === 'hazmat');

  $: bilkington = certifications.find(c => c.type === 'bilkington_carrier');
  $: highValue = certifications.find(c => c.type === 'high_value');
  $: govClearance = certifications.find(c => c.type === 'government_clearance');

  $: repScore = $playerData.reputationScore;
  $: repTier = $playerData.reputationTier;
  $: tierInfo = TIER_THRESHOLDS[repTier] || TIER_THRESHOLDS.developing;
  $: tierProgress = tierInfo.max > tierInfo.min
    ? ((repScore - tierInfo.min) / (tierInfo.max - tierInfo.min)) * 100
    : 100;

  $: sortedShippers = [...shipperReputations].sort((a, b) => {
    const aIdx = SHIPPER_TIER_ORDER.indexOf(a.tier);
    const bIdx = SHIPPER_TIER_ORDER.indexOf(b.tier);
    if (aIdx !== bIdx) return bIdx - aIdx;
    return (b.points || 0) - (a.points || 0);
  });

  function formatDate(timestamp) {
    if (!timestamp) return '--';
    const d = new Date(timestamp * 1000);
    return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
  }

  function formatMoney(amount) {
    return '$' + (amount || 0).toLocaleString('en-US');
  }

  function formatMiles(miles) {
    return (miles || 0).toLocaleString('en-US') + ' mi';
  }

  function getStatusClass(status) {
    if (status === 'active') return 'status-active';
    if (status === 'suspended') return 'status-suspended';
    if (status === 'revoked') return 'status-revoked';
    if (status === 'expired') return 'status-expired';
    return 'status-none';
  }

  function getStatusLabel(status) {
    if (!status) return 'Not Held';
    return status.charAt(0).toUpperCase() + status.slice(1);
  }

  function getShipperProgress(shipper) {
    const tier = SHIPPER_TIERS[shipper.tier];
    if (!tier || shipper.tier === 'blacklisted') return 0;
    const range = tier.max - tier.min;
    if (range <= 0) return 100;
    return Math.min(100, ((shipper.points - tier.min) / range) * 100);
  }

  function getNextShipperTier(tier) {
    const idx = SHIPPER_TIER_ORDER.indexOf(tier);
    if (idx < 0 || idx >= SHIPPER_TIER_ORDER.length - 1) return null;
    return SHIPPER_TIER_ORDER[idx + 1];
  }

  async function applyCertification(certType) {
    await fetchNUI('applyCertification', { certType });
  }

  // Listen for shipper reputation data from NUI messages
  import { onMount, onDestroy } from 'svelte';
  import { onNUIMessage } from '../lib/nui.js';

  let cleanup;
  onMount(() => {
    cleanup = onNUIMessage((action, data) => {
      if (action === 'updateShipperReputations') {
        shipperReputations = data.shippers || [];
      }
      if (action === 'updateAvailableCerts') {
        availableCerts = data.certs || [];
      }
    });

    fetchNUI('getShipperReputations');
    fetchNUI('getAvailableCerts');
  });

  onDestroy(() => {
    if (cleanup) cleanup();
  });
</script>

<div class="profile-screen">
  <h1 class="screen-title">DRIVER PROFILE</h1>

  <div class="tab-bar">
    <button
      class="tab-btn"
      class:active={activeTab === 'credentials'}
      on:click={() => activeTab = 'credentials'}
    >Credentials</button>
    <button
      class="tab-btn"
      class:active={activeTab === 'standings'}
      on:click={() => activeTab = 'standings'}
    >Standings</button>
  </div>

  {#if activeTab === 'credentials'}
    <div class="credentials-tab">
      <!-- CDL Section -->
      <div class="section">
        <h2 class="section-title">CDL LICENSES</h2>
        <div class="card-grid">
          <!-- Class B -->
          <div class="credential-card" class:held={classB} class:not-held={!classB}>
            <div class="card-header">
              <span class="card-label">CLASS B CDL</span>
              {#if classB}
                <span class="status-badge {getStatusClass(classB.status)}">{getStatusLabel(classB.status)}</span>
              {:else}
                <span class="status-badge status-none">Not Held</span>
              {/if}
            </div>
            {#if classB}
              <div class="card-details">
                <div class="detail-row">
                  <span class="detail-label">Issued</span>
                  <span class="detail-value mono">{formatDate(classB.issuedAt)}</span>
                </div>
                {#if classB.expiresAt}
                  <div class="detail-row">
                    <span class="detail-label">Expires</span>
                    <span class="detail-value mono">{formatDate(classB.expiresAt)}</span>
                  </div>
                {/if}
              </div>
            {:else}
              <div class="card-empty">Complete written test at LSDOT</div>
            {/if}
          </div>

          <!-- Class A -->
          <div class="credential-card" class:held={classA} class:not-held={!classA}>
            <div class="card-header">
              <span class="card-label">CLASS A CDL</span>
              {#if classA}
                <span class="status-badge {getStatusClass(classA.status)}">{getStatusLabel(classA.status)}</span>
              {:else}
                <span class="status-badge status-none">Not Held</span>
              {/if}
            </div>
            {#if classA}
              <div class="card-details">
                <div class="detail-row">
                  <span class="detail-label">Issued</span>
                  <span class="detail-value mono">{formatDate(classA.issuedAt)}</span>
                </div>
                {#if classA.expiresAt}
                  <div class="detail-row">
                    <span class="detail-label">Expires</span>
                    <span class="detail-value mono">{formatDate(classA.expiresAt)}</span>
                  </div>
                {/if}
              </div>
            {:else}
              <div class="card-empty">Complete practical exam at LSDOT</div>
            {/if}
          </div>
        </div>
      </div>

      <!-- Endorsements Section -->
      <div class="section">
        <h2 class="section-title">ENDORSEMENTS</h2>
        <div class="card-grid">
          <!-- Tanker -->
          <div class="credential-card" class:held={tanker} class:not-held={!tanker}>
            <div class="card-header">
              <span class="card-label">TANKER</span>
              {#if tanker}
                <span class="status-badge {getStatusClass(tanker.status)}">{getStatusLabel(tanker.status)}</span>
              {:else}
                <span class="status-badge status-none">Not Held</span>
              {/if}
            </div>
            {#if tanker}
              <div class="card-details">
                <div class="detail-row">
                  <span class="detail-label">Issued</span>
                  <span class="detail-value mono">{formatDate(tanker.issuedAt)}</span>
                </div>
              </div>
            {:else}
              <div class="card-empty">Pass tanker endorsement test</div>
            {/if}
          </div>

          <!-- HAZMAT -->
          <div class="credential-card" class:held={hazmat} class:not-held={!hazmat}>
            <div class="card-header">
              <span class="card-label">HAZMAT</span>
              {#if hazmat}
                <span class="status-badge {getStatusClass(hazmat.status)}">{getStatusLabel(hazmat.status)}</span>
              {:else}
                <span class="status-badge status-none">Not Held</span>
              {/if}
            </div>
            {#if hazmat}
              <div class="card-details">
                <div class="detail-row">
                  <span class="detail-label">Issued</span>
                  <span class="detail-value mono">{formatDate(hazmat.issuedAt)}</span>
                </div>
              </div>
            {:else}
              <div class="card-empty">Complete HAZMAT briefing</div>
            {/if}
          </div>
        </div>
      </div>

      <!-- Certifications Section -->
      <div class="section">
        <h2 class="section-title">CERTIFICATIONS</h2>
        <div class="card-grid">
          <!-- Bilkington Carrier -->
          <div class="credential-card" class:held={bilkington} class:not-held={!bilkington}>
            <div class="card-header">
              <span class="card-label">BILKINGTON CARRIER</span>
              {#if bilkington}
                <span class="status-badge {getStatusClass(bilkington.status)}">{getStatusLabel(bilkington.status)}</span>
              {:else}
                <span class="status-badge status-none">Not Held</span>
              {/if}
            </div>
            {#if bilkington}
              <div class="card-details">
                <div class="detail-row">
                  <span class="detail-label">Issued</span>
                  <span class="detail-value mono">{formatDate(bilkington.issuedAt)}</span>
                </div>
                {#if bilkington.expiresAt}
                  <div class="detail-row">
                    <span class="detail-label">Expires</span>
                    <span class="detail-value mono">{formatDate(bilkington.expiresAt)}</span>
                  </div>
                {/if}
                {#if bilkington.status === 'revoked' && bilkington.revokedReason}
                  <div class="detail-row revoked-reason">
                    <span class="detail-label">Reason</span>
                    <span class="detail-value">{bilkington.revokedReason}</span>
                  </div>
                {/if}
              </div>
            {:else}
              <div class="card-empty">
                Class A + 10 cold chain deliveries
                {#if availableCerts.includes('bilkington_carrier')}
                  <button class="btn-apply" on:click={() => applyCertification('bilkington_carrier')}>Apply</button>
                {/if}
              </div>
            {/if}
          </div>

          <!-- High-Value -->
          <div class="credential-card" class:held={highValue} class:not-held={!highValue}>
            <div class="card-header">
              <span class="card-label">HIGH-VALUE</span>
              {#if highValue}
                <span class="status-badge {getStatusClass(highValue.status)}">{getStatusLabel(highValue.status)}</span>
              {:else}
                <span class="status-badge status-none">Not Held</span>
              {/if}
            </div>
            {#if highValue}
              <div class="card-details">
                <div class="detail-row">
                  <span class="detail-label">Issued</span>
                  <span class="detail-value mono">{formatDate(highValue.issuedAt)}</span>
                </div>
                {#if highValue.expiresAt}
                  <div class="detail-row">
                    <span class="detail-label">Expires</span>
                    <span class="detail-value mono">{formatDate(highValue.expiresAt)}</span>
                  </div>
                {/if}
                {#if highValue.status === 'revoked' && highValue.revokedReason}
                  <div class="detail-row revoked-reason">
                    <span class="detail-label">Reason</span>
                    <span class="detail-value">{highValue.revokedReason}</span>
                  </div>
                {/if}
              </div>
            {:else}
              <div class="card-empty">
                Class A + 7-day clean record + $1,000 fee
                {#if availableCerts.includes('high_value')}
                  <button class="btn-apply" on:click={() => applyCertification('high_value')}>Apply</button>
                {/if}
              </div>
            {/if}
          </div>

          <!-- Government Clearance -->
          <div class="credential-card" class:held={govClearance} class:not-held={!govClearance}>
            <div class="card-header">
              <span class="card-label">GOV'T CLEARANCE</span>
              {#if govClearance}
                <span class="status-badge {getStatusClass(govClearance.status)}">{getStatusLabel(govClearance.status)}</span>
              {:else}
                <span class="status-badge status-none">Not Held</span>
              {/if}
            </div>
            {#if govClearance}
              <div class="card-details">
                <div class="detail-row">
                  <span class="detail-label">Issued</span>
                  <span class="detail-value mono">{formatDate(govClearance.issuedAt)}</span>
                </div>
                {#if govClearance.expiresAt}
                  <div class="detail-row">
                    <span class="detail-label">Expires</span>
                    <span class="detail-value mono">{formatDate(govClearance.expiresAt)}</span>
                  </div>
                {/if}
                {#if govClearance.status === 'revoked' && govClearance.revokedReason}
                  <div class="detail-row revoked-reason">
                    <span class="detail-label">Reason</span>
                    <span class="detail-value">{govClearance.revokedReason}</span>
                  </div>
                {/if}
              </div>
            {:else}
              <div class="card-empty">
                Class A + High-Value + 30-day clean record + $5,000
                {#if availableCerts.includes('government_clearance')}
                  <button class="btn-apply" on:click={() => applyCertification('government_clearance')}>Apply</button>
                {/if}
              </div>
            {/if}
          </div>
        </div>
      </div>
    </div>

  {:else if activeTab === 'standings'}
    <div class="standings-tab">
      <!-- Overall Reputation -->
      <div class="section reputation-hero">
        <div class="rep-score-display">
          <span class="rep-score mono">{repScore}</span>
          <span class="rep-max">/ 1000</span>
        </div>
        <div class="rep-tier-badge tier-{repTier}">
          {TIER_LABELS[repTier] || repTier}
        </div>
        <div class="rep-progress-container">
          <div class="rep-progress-bar">
            <div class="rep-progress-fill" style="width: {Math.min(100, Math.max(0, tierProgress))}%"></div>
          </div>
          <div class="rep-progress-labels">
            <span class="mono">{tierInfo.min}</span>
            <span class="mono">{tierInfo.max}</span>
          </div>
        </div>
      </div>

      <!-- Stats Grid -->
      <div class="section">
        <h2 class="section-title">CAREER STATS</h2>
        <div class="stats-grid">
          <div class="stat-card">
            <span class="stat-value mono">{$playerData.totalLoadsCompleted}</span>
            <span class="stat-label">Total Deliveries</span>
          </div>
          <div class="stat-card">
            <span class="stat-value mono fail">{$playerData.totalLoadsFailed}</span>
            <span class="stat-label">Total Failed</span>
          </div>
          <div class="stat-card">
            <span class="stat-value mono stolen">{$playerData.totalLoadsStolen}</span>
            <span class="stat-label">Total Stolen</span>
          </div>
          <div class="stat-card">
            <span class="stat-value mono">{formatMiles($playerData.totalDistanceDriven)}</span>
            <span class="stat-label">Total Distance</span>
          </div>
          <div class="stat-card wide">
            <span class="stat-value mono earnings">{formatMoney($playerData.totalEarnings)}</span>
            <span class="stat-label">Total Earnings</span>
          </div>
        </div>
      </div>

      <!-- Shipper Reputations -->
      <div class="section">
        <h2 class="section-title">SHIPPER STANDINGS</h2>
        {#if sortedShippers.length === 0}
          <div class="empty-state">
            <p>No shipper interactions yet. Complete deliveries to build reputation.</p>
          </div>
        {:else}
          <div class="shipper-list">
            {#each sortedShippers as shipper}
              {@const tierData = SHIPPER_TIERS[shipper.tier] || SHIPPER_TIERS.unknown}
              {@const progress = getShipperProgress(shipper)}
              {@const nextTier = getNextShipperTier(shipper.tier)}
              <div class="shipper-row" class:blacklisted={shipper.tier === 'blacklisted'}>
                <div class="shipper-info">
                  <div class="shipper-name-row">
                    <span class="shipper-cluster-icon" title={shipper.cluster || 'general'}>
                      {CLUSTER_ICONS[shipper.cluster] || CLUSTER_ICONS.general}
                    </span>
                    <span class="shipper-name">{shipper.name}</span>
                  </div>
                  <div class="shipper-meta">
                    <span class="shipper-tier-badge" style="color: {tierData.color}">
                      {tierData.label}
                    </span>
                    <span class="shipper-deliveries mono">
                      {shipper.deliveries || 0} deliveries
                    </span>
                    {#if shipper.cleanStreak > 0}
                      <span class="shipper-streak mono">
                        {shipper.cleanStreak} clean
                      </span>
                    {/if}
                  </div>
                </div>
                <div class="shipper-progress-section">
                  <div class="shipper-progress-bar">
                    <div
                      class="shipper-progress-fill"
                      style="width: {progress}%; background: {tierData.color}"
                    ></div>
                  </div>
                  <div class="shipper-progress-label">
                    <span class="mono">{shipper.points || 0} pts</span>
                    {#if nextTier}
                      <span class="next-tier">
                        Next: {SHIPPER_TIERS[nextTier].label} ({SHIPPER_TIERS[nextTier].min})
                      </span>
                    {/if}
                  </div>
                </div>
              </div>
            {/each}
          </div>
        {/if}
      </div>
    </div>
  {/if}
</div>

<style>
  .profile-screen {
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

  /* Tab Bar */
  .tab-bar {
    display: flex;
    gap: 2px;
    margin-bottom: 20px;
    background: var(--navy-dark, #051229);
    border-radius: 6px;
    padding: 3px;
  }

  .tab-btn {
    flex: 1;
    font-family: 'Barlow Condensed', sans-serif;
    font-weight: 700;
    font-size: 14px;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    color: var(--muted, #A8B4C8);
    background: transparent;
    border: none;
    border-radius: 4px;
    padding: 10px 16px;
    cursor: pointer;
    transition: background 0.15s, color 0.15s;
  }

  .tab-btn:hover {
    background: rgba(30, 58, 110, 0.4);
    color: var(--white, #FFFFFF);
  }

  .tab-btn.active {
    background: var(--navy-mid, #132E5C);
    color: var(--orange, #C83803);
  }

  /* Sections */
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

  /* Card Grid */
  .card-grid {
    display: grid;
    grid-template-columns: repeat(2, 1fr);
    gap: 10px;
  }

  .credential-card {
    background: var(--navy-dark, #051229);
    border: 1px solid var(--border, #1E3A6E);
    border-radius: 6px;
    padding: 14px;
    transition: border-color 0.15s;
  }

  .credential-card.held {
    border-color: var(--border, #1E3A6E);
  }

  .credential-card.not-held {
    border-color: var(--disabled, #3A4A5C);
    opacity: 0.7;
  }

  .card-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 10px;
  }

  .card-label {
    font-family: 'Barlow Condensed', sans-serif;
    font-weight: 700;
    font-size: 13px;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    color: var(--white, #FFFFFF);
  }

  .status-badge {
    font-family: 'Barlow Condensed', sans-serif;
    font-weight: 700;
    font-size: 10px;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    padding: 3px 8px;
    border-radius: 3px;
  }

  .status-active {
    color: var(--success, #2D7A3E);
    background: rgba(45, 122, 62, 0.15);
  }

  .status-suspended {
    color: var(--warning, #C87B03);
    background: rgba(200, 123, 3, 0.15);
  }

  .status-revoked {
    color: var(--orange, #C83803);
    background: rgba(200, 56, 3, 0.15);
  }

  .status-expired {
    color: var(--disabled, #3A4A5C);
    background: rgba(58, 74, 92, 0.15);
  }

  .status-none {
    color: var(--disabled, #3A4A5C);
    background: rgba(58, 74, 92, 0.1);
  }

  .card-details {
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  .detail-row {
    display: flex;
    justify-content: space-between;
    align-items: center;
  }

  .detail-label {
    font-family: 'Inter', sans-serif;
    font-size: 12px;
    color: var(--muted, #A8B4C8);
  }

  .detail-value {
    font-family: 'Inter', sans-serif;
    font-size: 12px;
    color: var(--white, #FFFFFF);
  }

  .detail-value.mono, .mono {
    font-family: 'JetBrains Mono', monospace;
  }

  .revoked-reason .detail-value {
    color: var(--orange, #C83803);
    font-size: 11px;
    max-width: 140px;
    text-align: right;
  }

  .card-empty {
    font-family: 'Inter', sans-serif;
    font-size: 12px;
    color: var(--disabled, #3A4A5C);
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  .btn-apply {
    font-family: 'Barlow Condensed', sans-serif;
    font-weight: 700;
    font-size: 12px;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    background: var(--orange, #C83803);
    color: var(--white, #FFFFFF);
    border: none;
    border-radius: 4px;
    padding: 6px 14px;
    cursor: pointer;
    align-self: flex-start;
    transition: background 0.15s;
  }

  .btn-apply:hover {
    background: var(--orange-dim, #8A2702);
  }

  /* Reputation Hero */
  .reputation-hero {
    text-align: center;
    padding: 24px 20px;
    background: var(--navy-dark, #051229);
    border: 1px solid var(--border, #1E3A6E);
    border-radius: 8px;
  }

  .rep-score-display {
    display: flex;
    align-items: baseline;
    justify-content: center;
    gap: 6px;
    margin-bottom: 10px;
  }

  .rep-score {
    font-family: 'JetBrains Mono', monospace;
    font-size: 48px;
    font-weight: 700;
    color: var(--white, #FFFFFF);
    line-height: 1;
  }

  .rep-max {
    font-family: 'JetBrains Mono', monospace;
    font-size: 18px;
    color: var(--disabled, #3A4A5C);
  }

  .rep-tier-badge {
    display: inline-block;
    font-family: 'Barlow Condensed', sans-serif;
    font-weight: 700;
    font-size: 16px;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    padding: 6px 20px;
    border-radius: 4px;
    margin-bottom: 16px;
  }

  .tier-suspended { color: #D32F2F; background: rgba(211, 47, 47, 0.15); }
  .tier-restricted { color: var(--orange, #C83803); background: rgba(200, 56, 3, 0.15); }
  .tier-probationary { color: var(--warning, #C87B03); background: rgba(200, 123, 3, 0.15); }
  .tier-developing { color: var(--muted, #A8B4C8); background: rgba(168, 180, 200, 0.12); }
  .tier-established { color: #4CAF50; background: rgba(76, 175, 80, 0.15); }
  .tier-professional { color: #42A5F5; background: rgba(66, 165, 245, 0.15); }
  .tier-elite { color: #FFD700; background: rgba(255, 215, 0, 0.12); }

  .rep-progress-container {
    max-width: 300px;
    margin: 0 auto;
  }

  .rep-progress-bar {
    height: 8px;
    background: rgba(30, 58, 110, 0.5);
    border-radius: 4px;
    overflow: hidden;
    margin-bottom: 4px;
  }

  .rep-progress-fill {
    height: 100%;
    background: var(--orange, #C83803);
    border-radius: 4px;
    transition: width 0.5s ease;
  }

  .rep-progress-labels {
    display: flex;
    justify-content: space-between;
    font-size: 11px;
    color: var(--disabled, #3A4A5C);
  }

  /* Stats Grid */
  .stats-grid {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 10px;
  }

  .stat-card {
    background: var(--navy-dark, #051229);
    border: 1px solid var(--border, #1E3A6E);
    border-radius: 6px;
    padding: 14px 12px;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 4px;
  }

  .stat-card.wide {
    grid-column: span 3;
  }

  .stat-value {
    font-family: 'JetBrains Mono', monospace;
    font-size: 20px;
    font-weight: 700;
    color: var(--white, #FFFFFF);
    line-height: 1.2;
  }

  .stat-value.fail {
    color: var(--orange, #C83803);
  }

  .stat-value.stolen {
    color: #D32F2F;
  }

  .stat-value.earnings {
    color: var(--success, #2D7A3E);
  }

  .stat-label {
    font-family: 'Barlow Condensed', sans-serif;
    font-weight: 700;
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    color: var(--muted, #A8B4C8);
  }

  /* Shipper List */
  .shipper-list {
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  .shipper-row {
    background: var(--navy-dark, #051229);
    border: 1px solid var(--border, #1E3A6E);
    border-radius: 6px;
    padding: 12px 14px;
    display: flex;
    gap: 16px;
    align-items: center;
  }

  .shipper-row.blacklisted {
    border-color: #8B0000;
    opacity: 0.7;
  }

  .shipper-info {
    flex: 1;
    min-width: 0;
  }

  .shipper-name-row {
    display: flex;
    align-items: center;
    gap: 8px;
    margin-bottom: 4px;
  }

  .shipper-cluster-icon {
    font-size: 14px;
    color: var(--muted, #A8B4C8);
  }

  .shipper-name {
    font-family: 'Inter', sans-serif;
    font-size: 14px;
    font-weight: 600;
    color: var(--white, #FFFFFF);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .shipper-meta {
    display: flex;
    align-items: center;
    gap: 10px;
    flex-wrap: wrap;
  }

  .shipper-tier-badge {
    font-family: 'Barlow Condensed', sans-serif;
    font-weight: 700;
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }

  .shipper-deliveries {
    font-size: 11px;
    color: var(--muted, #A8B4C8);
  }

  .shipper-streak {
    font-size: 11px;
    color: var(--success, #2D7A3E);
  }

  .shipper-progress-section {
    width: 140px;
    flex-shrink: 0;
  }

  .shipper-progress-bar {
    height: 6px;
    background: rgba(30, 58, 110, 0.5);
    border-radius: 3px;
    overflow: hidden;
    margin-bottom: 3px;
  }

  .shipper-progress-fill {
    height: 100%;
    border-radius: 3px;
    transition: width 0.4s ease;
  }

  .shipper-progress-label {
    display: flex;
    justify-content: space-between;
    align-items: center;
  }

  .shipper-progress-label .mono {
    font-size: 10px;
    color: var(--muted, #A8B4C8);
  }

  .next-tier {
    font-family: 'Inter', sans-serif;
    font-size: 9px;
    color: var(--disabled, #3A4A5C);
  }

  .empty-state {
    text-align: center;
    padding: 32px 20px;
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
