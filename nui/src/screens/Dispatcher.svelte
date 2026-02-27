<script>
  import { onMount, onDestroy } from 'svelte';
  import { companyData, boardData } from '../lib/stores.js';
  import { fetchNUI, onNUIMessage } from '../lib/nui.js';
  import ConfirmDialog from '../components/ConfirmDialog.svelte';

  let selectedDriver = null;
  let activePanel = 'board'; // 'board' | 'detail'
  let selectedLoad = null;
  let showAssignDropdown = false;
  let assignTargetLoad = null;
  let pendingTransfers = [];

  let confirmVisible = false;
  let confirmTitle = '';
  let confirmMessage = '';
  let confirmAction = null;

  $: members = $companyData.members || [];
  $: drivers = members.filter(m => m.role === 'driver' || m.role === 'owner');
  $: onlineDrivers = drivers.filter(d => d.status !== 'offline');
  $: availableDrivers = onlineDrivers.filter(d => !d.activeLoad);

  $: boardLoads = [
    ...($boardData.standard || []),
    ...($boardData.supplier || []),
  ];

  function selectDriver(driver) {
    selectedDriver = driver;
    if (driver.activeLoad) {
      selectedLoad = driver.activeLoad;
      activePanel = 'detail';
    } else {
      selectedLoad = null;
      activePanel = 'board';
    }
  }

  function showBoard() {
    selectedLoad = null;
    activePanel = 'board';
  }

  function getStatusClass(status) {
    if (status === 'online') return 'dot-online';
    if (status === 'on_delivery') return 'dot-delivery';
    return 'dot-offline';
  }

  function getStatusLabel(status) {
    if (status === 'online') return 'Available';
    if (status === 'on_delivery') return 'On Delivery';
    return 'Offline';
  }

  function formatMoney(amount) {
    return '$' + (amount || 0).toLocaleString('en-US');
  }

  function openAssignDropdown(load) {
    assignTargetLoad = load;
    showAssignDropdown = true;
  }

  function closeAssignDropdown() {
    showAssignDropdown = false;
    assignTargetLoad = null;
  }

  function assignLoadToDriver(driver) {
    if (!assignTargetLoad) return;
    confirmTitle = 'Assign Load';
    confirmMessage = `Assign "${assignTargetLoad.cargoType}" to ${driver.name}?`;
    confirmAction = async () => {
      await fetchNUI('assignLoadToDriver', {
        loadId: assignTargetLoad.id,
        citizenid: driver.citizenid,
      });
      closeAssignDropdown();
    };
    confirmVisible = true;
  }

  function approveTransfer(transfer) {
    confirmTitle = 'Approve Transfer';
    confirmMessage = `Approve transfer of BOL #${transfer.bolNumber} from ${transfer.fromName} to ${transfer.toName}?`;
    confirmAction = () => fetchNUI('approveTransfer', { transferId: transfer.id });
    confirmVisible = true;
  }

  function denyTransfer(transfer) {
    confirmTitle = 'Deny Transfer';
    confirmMessage = `Deny transfer of BOL #${transfer.bolNumber}?`;
    confirmAction = () => fetchNUI('denyTransfer', { transferId: transfer.id });
    confirmVisible = true;
  }

  async function createConvoy() {
    await fetchNUI('createConvoy', { type: 'company' });
  }

  function handleConfirm() {
    confirmVisible = false;
    if (confirmAction) confirmAction();
    confirmAction = null;
  }

  function handleCancel() {
    confirmVisible = false;
    confirmAction = null;
  }

  let cleanup;
  onMount(() => {
    cleanup = onNUIMessage((action, data) => {
      if (action === 'updateCompany') {
        companyData.set({
          company: data.company || null,
          members: data.members || [],
          activeClaims: data.activeClaims || [],
        });
      }
      if (action === 'updateBoard') {
        boardData.set(data);
      }
      if (action === 'updateTransfers') {
        pendingTransfers = data.transfers || [];
      }
    });

    fetchNUI('getCompanyData');
    fetchNUI('getBoard');
    fetchNUI('getPendingTransfers');
  });

  onDestroy(() => {
    if (cleanup) cleanup();
  });
</script>

<div class="dispatcher-screen">
  <!-- Left Panel: Driver List -->
  <div class="panel-left">
    <div class="panel-header">
      <h2 class="panel-title">DRIVERS</h2>
      <span class="driver-count">{onlineDrivers.length} online</span>
    </div>

    <div class="driver-list">
      {#each drivers as driver}
        <button
          class="driver-card"
          class:selected={selectedDriver?.citizenid === driver.citizenid}
          class:offline={driver.status === 'offline'}
          on:click={() => selectDriver(driver)}
        >
          <div class="driver-dot {getStatusClass(driver.status)}"></div>
          <div class="driver-info">
            <span class="driver-name">{driver.name}</span>
            <span class="driver-status">{getStatusLabel(driver.status)}</span>
            {#if driver.activeLoad}
              <span class="driver-load-summary">
                {driver.activeLoad.cargoType} &rarr; {driver.activeLoad.destination}
              </span>
            {/if}
          </div>
        </button>
      {/each}
    </div>

    <!-- Convoy Button -->
    <div class="panel-footer">
      <button class="btn-convoy" on:click={createConvoy}>
        <svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><path d="M20 8h-3V4H3c-1.1 0-2 .9-2 2v11h2c0 1.66 1.34 3 3 3s3-1.34 3-3h6c0 1.66 1.34 3 3 3s3-1.34 3-3h2v-5l-3-4z"/></svg>
        Create Convoy
      </button>
    </div>
  </div>

  <!-- Right Panel: Board or Detail -->
  <div class="panel-right">
    {#if activePanel === 'detail' && selectedLoad}
      <!-- Load Detail View -->
      <div class="detail-header">
        <button class="btn-back" on:click={showBoard}>
          <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor"><path d="M20 11H7.83l5.59-5.59L12 4l-8 8 8 8 1.41-1.41L7.83 13H20v-2z"/></svg>
          Board
        </button>
        <h2 class="detail-title">{selectedDriver?.name}'s Active Load</h2>
      </div>

      <div class="load-detail-card">
        <div class="detail-row">
          <span class="detail-label">BOL</span>
          <span class="detail-value mono">#{selectedLoad.bolNumber}</span>
        </div>
        <div class="detail-row">
          <span class="detail-label">Cargo</span>
          <span class="detail-value">{selectedLoad.cargoType}</span>
        </div>
        <div class="detail-row">
          <span class="detail-label">Origin</span>
          <span class="detail-value">{selectedLoad.origin}</span>
        </div>
        <div class="detail-row">
          <span class="detail-label">Destination</span>
          <span class="detail-value">{selectedLoad.destination}</span>
        </div>
        <div class="detail-row">
          <span class="detail-label">Distance</span>
          <span class="detail-value mono">{selectedLoad.distance || '--'} mi</span>
        </div>
        <div class="detail-row">
          <span class="detail-label">Status</span>
          <span class="detail-value status-badge">{selectedLoad.status || 'In Transit'}</span>
        </div>
        {#if selectedLoad.integrity !== undefined}
          <div class="detail-row">
            <span class="detail-label">Integrity</span>
            <span class="detail-value mono" class:integrity-low={selectedLoad.integrity < 50}>{selectedLoad.integrity}%</span>
          </div>
        {/if}
        {#if selectedLoad.timeRemaining}
          <div class="detail-row">
            <span class="detail-label">Time Remaining</span>
            <span class="detail-value mono">{selectedLoad.timeRemaining}</span>
          </div>
        {/if}
        {#if selectedLoad.estimatedPayout}
          <div class="detail-row">
            <span class="detail-label">Est. Payout</span>
            <span class="detail-value mono payout">{formatMoney(selectedLoad.estimatedPayout)}</span>
          </div>
        {/if}
      </div>

    {:else}
      <!-- Board View -->
      <div class="detail-header">
        <h2 class="detail-title">FREIGHT BOARD</h2>
        <span class="load-count">{boardLoads.length} loads</span>
      </div>

      {#if boardLoads.length === 0}
        <div class="empty-state">
          <p>No loads currently available on the board.</p>
        </div>
      {:else}
        <div class="board-list">
          {#each boardLoads as load}
            <div class="board-load-card">
              <div class="board-load-info">
                <div class="board-load-top">
                  <span class="board-tier">T{load.tier}</span>
                  <span class="board-cargo">{load.cargoType}</span>
                  {#if load.surgeActive}
                    <span class="surge-badge">+{load.surgePercentage}%</span>
                  {/if}
                </div>
                <div class="board-load-route">
                  <span class="board-origin">{load.origin}</span>
                  <span class="board-arrow">&rarr;</span>
                  <span class="board-dest">{load.destination}</span>
                </div>
                <div class="board-load-meta">
                  <span class="board-distance mono">{load.distance} mi</span>
                  <span class="board-payout mono">{formatMoney(load.estimatedPayout)}</span>
                </div>
              </div>
              <button class="btn-assign" on:click={() => openAssignDropdown(load)}>
                Assign to...
              </button>
            </div>
          {/each}
        </div>
      {/if}
    {/if}

    <!-- Assign Dropdown -->
    {#if showAssignDropdown}
      <div class="assign-overlay" on:click={closeAssignDropdown}>
        <div class="assign-dropdown" on:click|stopPropagation>
          <h3 class="assign-title">ASSIGN TO DRIVER</h3>
          {#if availableDrivers.length === 0}
            <p class="assign-empty">No available drivers online.</p>
          {:else}
            {#each availableDrivers as driver}
              <button class="assign-driver-btn" on:click={() => assignLoadToDriver(driver)}>
                <span class="assign-driver-name">{driver.name}</span>
                <span class="assign-driver-status">{getStatusLabel(driver.status)}</span>
              </button>
            {/each}
          {/if}
          <button class="btn-assign-cancel" on:click={closeAssignDropdown}>Cancel</button>
        </div>
      </div>
    {/if}

    <!-- Pending Transfers -->
    {#if pendingTransfers.length > 0}
      <div class="transfers-section">
        <h3 class="transfers-title">PENDING TRANSFERS</h3>
        {#each pendingTransfers as transfer}
          <div class="transfer-card">
            <div class="transfer-info">
              <span class="transfer-bol mono">BOL #{transfer.bolNumber}</span>
              <span class="transfer-route">{transfer.fromName} &rarr; {transfer.toName}</span>
            </div>
            <div class="transfer-actions">
              <button class="btn-approve" on:click={() => approveTransfer(transfer)}>Approve</button>
              <button class="btn-deny" on:click={() => denyTransfer(transfer)}>Deny</button>
            </div>
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
  on:confirm={handleConfirm}
  on:cancel={handleCancel}
/>

<style>
  .dispatcher-screen {
    display: flex;
    height: 100%;
    overflow: hidden;
  }

  .mono {
    font-family: 'JetBrains Mono', monospace;
  }

  /* Left Panel */
  .panel-left {
    width: 260px;
    flex-shrink: 0;
    background: var(--navy-dark, #051229);
    border-right: 1px solid var(--border, #1E3A6E);
    display: flex;
    flex-direction: column;
  }

  .panel-header {
    padding: 16px 14px 12px;
    border-bottom: 1px solid var(--border, #1E3A6E);
    display: flex;
    justify-content: space-between;
    align-items: center;
  }

  .panel-title {
    font-family: 'Barlow Condensed', sans-serif;
    font-weight: 700;
    font-size: 16px;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    color: var(--white, #FFFFFF);
    margin: 0;
  }

  .driver-count {
    font-family: 'Inter', sans-serif;
    font-size: 11px;
    color: var(--success, #2D7A3E);
  }

  .driver-list {
    flex: 1;
    overflow-y: auto;
    padding: 8px;
  }

  .driver-card {
    width: 100%;
    display: flex;
    align-items: flex-start;
    gap: 10px;
    padding: 10px 12px;
    background: transparent;
    border: 1px solid transparent;
    border-radius: 6px;
    cursor: pointer;
    text-align: left;
    transition: background 0.15s, border-color 0.15s;
    margin-bottom: 4px;
  }

  .driver-card:hover {
    background: rgba(30, 58, 110, 0.3);
  }

  .driver-card.selected {
    background: rgba(200, 56, 3, 0.08);
    border-color: var(--orange, #C83803);
  }

  .driver-card.offline {
    opacity: 0.5;
  }

  .driver-dot {
    width: 8px;
    height: 8px;
    border-radius: 50%;
    margin-top: 5px;
    flex-shrink: 0;
  }

  .dot-online {
    background: var(--success, #2D7A3E);
    box-shadow: 0 0 4px rgba(45, 122, 62, 0.5);
  }

  .dot-delivery {
    background: var(--orange, #C83803);
    box-shadow: 0 0 4px rgba(200, 56, 3, 0.5);
  }

  .dot-offline {
    background: var(--disabled, #3A4A5C);
  }

  .driver-info {
    display: flex;
    flex-direction: column;
    gap: 1px;
    min-width: 0;
  }

  .driver-name {
    font-family: 'Inter', sans-serif;
    font-size: 13px;
    font-weight: 600;
    color: var(--white, #FFFFFF);
  }

  .driver-status {
    font-family: 'Inter', sans-serif;
    font-size: 11px;
    color: var(--muted, #A8B4C8);
  }

  .driver-load-summary {
    font-family: 'Inter', sans-serif;
    font-size: 10px;
    color: var(--disabled, #3A4A5C);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .panel-footer {
    padding: 10px 12px;
    border-top: 1px solid var(--border, #1E3A6E);
  }

  .btn-convoy {
    width: 100%;
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 6px;
    font-family: 'Barlow Condensed', sans-serif;
    font-weight: 700;
    font-size: 12px;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    background: var(--navy-mid, #132E5C);
    color: var(--muted, #A8B4C8);
    border: 1px solid var(--border, #1E3A6E);
    border-radius: 4px;
    padding: 10px;
    cursor: pointer;
    transition: background 0.15s;
  }

  .btn-convoy:hover {
    background: var(--border, #1E3A6E);
    color: var(--white, #FFFFFF);
  }

  /* Right Panel */
  .panel-right {
    flex: 1;
    overflow-y: auto;
    padding: 16px 18px;
    position: relative;
  }

  .detail-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 16px;
  }

  .detail-title {
    font-family: 'Barlow Condensed', sans-serif;
    font-weight: 700;
    font-size: 18px;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    color: var(--white, #FFFFFF);
    margin: 0;
  }

  .load-count {
    font-family: 'Inter', sans-serif;
    font-size: 12px;
    color: var(--muted, #A8B4C8);
  }

  .btn-back {
    display: flex;
    align-items: center;
    gap: 4px;
    font-family: 'Barlow Condensed', sans-serif;
    font-weight: 700;
    font-size: 12px;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    background: transparent;
    color: var(--muted, #A8B4C8);
    border: none;
    cursor: pointer;
    padding: 4px 0;
    transition: color 0.15s;
  }

  .btn-back:hover {
    color: var(--white, #FFFFFF);
  }

  /* Load Detail */
  .load-detail-card {
    background: var(--navy-dark, #051229);
    border: 1px solid var(--border, #1E3A6E);
    border-radius: 8px;
    padding: 16px;
  }

  .detail-row {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 8px 0;
    border-bottom: 1px solid rgba(30, 58, 110, 0.3);
  }

  .detail-row:last-child {
    border-bottom: none;
  }

  .detail-label {
    font-family: 'Inter', sans-serif;
    font-size: 13px;
    color: var(--muted, #A8B4C8);
  }

  .detail-value {
    font-family: 'Inter', sans-serif;
    font-size: 13px;
    color: var(--white, #FFFFFF);
  }

  .detail-value.status-badge {
    font-family: 'Barlow Condensed', sans-serif;
    font-weight: 700;
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    color: var(--success, #2D7A3E);
    background: rgba(45, 122, 62, 0.12);
    padding: 3px 8px;
    border-radius: 3px;
  }

  .integrity-low {
    color: var(--orange, #C83803);
  }

  .payout {
    color: var(--success, #2D7A3E);
  }

  /* Board List */
  .board-list {
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  .board-load-card {
    background: var(--navy-dark, #051229);
    border: 1px solid var(--border, #1E3A6E);
    border-radius: 6px;
    padding: 12px 14px;
    display: flex;
    align-items: center;
    gap: 14px;
  }

  .board-load-info {
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  .board-load-top {
    display: flex;
    align-items: center;
    gap: 8px;
  }

  .board-tier {
    font-family: 'Barlow Condensed', sans-serif;
    font-weight: 700;
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    color: var(--orange, #C83803);
    background: rgba(200, 56, 3, 0.12);
    padding: 2px 6px;
    border-radius: 3px;
  }

  .board-cargo {
    font-family: 'Inter', sans-serif;
    font-size: 13px;
    font-weight: 600;
    color: var(--white, #FFFFFF);
  }

  .surge-badge {
    font-family: 'JetBrains Mono', monospace;
    font-size: 10px;
    color: var(--success, #2D7A3E);
    background: rgba(45, 122, 62, 0.12);
    padding: 2px 6px;
    border-radius: 3px;
  }

  .board-load-route {
    display: flex;
    align-items: center;
    gap: 6px;
    font-family: 'Inter', sans-serif;
    font-size: 12px;
  }

  .board-origin {
    color: var(--muted, #A8B4C8);
  }

  .board-arrow {
    color: var(--orange, #C83803);
  }

  .board-dest {
    color: var(--muted, #A8B4C8);
  }

  .board-load-meta {
    display: flex;
    align-items: center;
    gap: 12px;
    font-size: 11px;
  }

  .board-distance {
    color: var(--disabled, #3A4A5C);
  }

  .board-payout {
    color: var(--success, #2D7A3E);
  }

  .btn-assign {
    font-family: 'Barlow Condensed', sans-serif;
    font-weight: 700;
    font-size: 12px;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    background: var(--orange, #C83803);
    color: var(--white, #FFFFFF);
    border: none;
    border-radius: 4px;
    padding: 8px 14px;
    cursor: pointer;
    flex-shrink: 0;
    transition: background 0.15s;
    white-space: nowrap;
  }

  .btn-assign:hover {
    background: var(--orange-dim, #8A2702);
  }

  /* Assign Dropdown */
  .assign-overlay {
    position: fixed;
    top: 0;
    left: 0;
    width: 100%;
    height: 100%;
    background: rgba(5, 18, 41, 0.7);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 9998;
  }

  .assign-dropdown {
    background: var(--navy, #0B1F45);
    border: 2px solid var(--border, #1E3A6E);
    border-radius: 8px;
    padding: 20px;
    min-width: 280px;
    max-width: 360px;
  }

  .assign-title {
    font-family: 'Barlow Condensed', sans-serif;
    font-weight: 700;
    font-size: 16px;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    color: var(--white, #FFFFFF);
    margin: 0 0 14px 0;
  }

  .assign-empty {
    font-family: 'Inter', sans-serif;
    font-size: 13px;
    color: var(--disabled, #3A4A5C);
    margin: 0 0 14px 0;
  }

  .assign-driver-btn {
    width: 100%;
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 10px 12px;
    background: var(--navy-dark, #051229);
    border: 1px solid var(--border, #1E3A6E);
    border-radius: 4px;
    cursor: pointer;
    margin-bottom: 6px;
    transition: border-color 0.15s;
  }

  .assign-driver-btn:hover {
    border-color: var(--orange, #C83803);
  }

  .assign-driver-name {
    font-family: 'Inter', sans-serif;
    font-size: 13px;
    font-weight: 600;
    color: var(--white, #FFFFFF);
  }

  .assign-driver-status {
    font-family: 'Inter', sans-serif;
    font-size: 11px;
    color: var(--success, #2D7A3E);
  }

  .btn-assign-cancel {
    width: 100%;
    font-family: 'Barlow Condensed', sans-serif;
    font-weight: 700;
    font-size: 13px;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    background: var(--navy-mid, #132E5C);
    color: var(--muted, #A8B4C8);
    border: 1px solid var(--border, #1E3A6E);
    border-radius: 4px;
    padding: 10px;
    cursor: pointer;
    margin-top: 8px;
    transition: background 0.15s;
  }

  .btn-assign-cancel:hover {
    background: var(--border, #1E3A6E);
  }

  /* Transfers */
  .transfers-section {
    margin-top: 24px;
    padding-top: 16px;
    border-top: 1px solid var(--border, #1E3A6E);
  }

  .transfers-title {
    font-family: 'Barlow Condensed', sans-serif;
    font-weight: 700;
    font-size: 14px;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    color: var(--muted, #A8B4C8);
    margin: 0 0 12px 0;
  }

  .transfer-card {
    display: flex;
    align-items: center;
    gap: 14px;
    background: var(--navy-dark, #051229);
    border: 1px solid var(--warning, #C87B03);
    border-radius: 6px;
    padding: 10px 14px;
    margin-bottom: 8px;
  }

  .transfer-info {
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .transfer-bol {
    font-size: 12px;
    color: var(--white, #FFFFFF);
  }

  .transfer-route {
    font-family: 'Inter', sans-serif;
    font-size: 11px;
    color: var(--muted, #A8B4C8);
  }

  .transfer-actions {
    display: flex;
    gap: 6px;
  }

  .btn-approve {
    font-family: 'Barlow Condensed', sans-serif;
    font-weight: 700;
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    background: var(--success, #2D7A3E);
    color: var(--white, #FFFFFF);
    border: none;
    border-radius: 4px;
    padding: 6px 12px;
    cursor: pointer;
    transition: background 0.15s;
  }

  .btn-approve:hover {
    background: #236B32;
  }

  .btn-deny {
    font-family: 'Barlow Condensed', sans-serif;
    font-weight: 700;
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    background: transparent;
    color: var(--orange, #C83803);
    border: 1px solid var(--orange, #C83803);
    border-radius: 4px;
    padding: 6px 12px;
    cursor: pointer;
    transition: background 0.15s;
  }

  .btn-deny:hover {
    background: rgba(200, 56, 3, 0.1);
  }

  /* Empty State */
  .empty-state {
    text-align: center;
    padding: 40px 20px;
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
