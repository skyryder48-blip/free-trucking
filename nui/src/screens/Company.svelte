<script>
  import { onMount, onDestroy } from 'svelte';
  import { companyData, playerData } from '../lib/stores.js';
  import { fetchNUI, onNUIMessage } from '../lib/nui.js';
  import ConfirmDialog from '../components/ConfirmDialog.svelte';

  let confirmVisible = false;
  let confirmTitle = '';
  let confirmMessage = '';
  let confirmAction = null;
  let confirmStyle = 'primary';

  let createCompanyName = '';
  let inviteName = '';
  let showInviteInput = false;

  $: company = $companyData.company;
  $: members = $companyData.members || [];
  $: hasCompany = company !== null;

  $: myRole = getMyRole(members, $playerData.citizenid);
  $: isOwner = myRole === 'owner';
  $: isDispatcher = myRole === 'dispatcher';
  $: isOwnerOrDispatcher = isOwner || isDispatcher;

  $: onlineMembers = members.filter(m => m.status !== 'offline');
  $: activeLoads = members.filter(m => m.activeLoad).map(m => ({
    ...m.activeLoad,
    driverName: m.name,
    driverStatus: m.status,
  }));

  function getMyRole(members, citizenid) {
    const me = members.find(m => m.citizenid === citizenid);
    return me?.role || 'driver';
  }

  function getRoleBadgeClass(role) {
    if (role === 'owner') return 'role-owner';
    if (role === 'dispatcher') return 'role-dispatcher';
    return 'role-driver';
  }

  function getRoleLabel(role) {
    return (role || 'driver').charAt(0).toUpperCase() + (role || 'driver').slice(1);
  }

  function getStatusIndicator(status) {
    if (status === 'online') return 'status-online';
    if (status === 'on_delivery') return 'status-delivery';
    return 'status-offline';
  }

  function getStatusLabel(status) {
    if (status === 'online') return 'Online';
    if (status === 'on_delivery') return 'On Delivery';
    return 'Offline';
  }

  async function createCompany() {
    if (!createCompanyName.trim()) return;
    await fetchNUI('createCompany', { name: createCompanyName.trim() });
    createCompanyName = '';
  }

  function promptInvite() {
    showInviteInput = true;
  }

  async function sendInvite() {
    if (!inviteName.trim()) return;
    await fetchNUI('inviteMember', { name: inviteName.trim() });
    inviteName = '';
    showInviteInput = false;
  }

  function promptRemoveMember(member) {
    confirmTitle = 'Remove Member';
    confirmMessage = `Remove ${member.name} from the company?`;
    confirmStyle = 'danger';
    confirmAction = () => fetchNUI('removeMember', { citizenid: member.citizenid });
    confirmVisible = true;
  }

  function promptAssignDispatcher(member) {
    confirmTitle = 'Assign Dispatcher';
    confirmMessage = `Assign ${member.name} as dispatcher?`;
    confirmStyle = 'primary';
    confirmAction = () => fetchNUI('assignDispatcher', { citizenid: member.citizenid });
    confirmVisible = true;
  }

  function promptLeaveCompany() {
    confirmTitle = 'Leave Company';
    confirmMessage = 'Are you sure you want to leave this company?';
    confirmStyle = 'danger';
    confirmAction = () => fetchNUI('leaveCompany');
    confirmVisible = true;
  }

  async function toggleDispatchMode() {
    await fetchNUI('toggleDispatchMode');
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
    });

    fetchNUI('getCompanyData');
  });

  onDestroy(() => {
    if (cleanup) cleanup();
  });
</script>

<div class="company-screen">
  <h1 class="screen-title">COMPANY</h1>

  {#if !hasCompany}
    <!-- No Company State -->
    <div class="no-company">
      <div class="no-company-icon">
        <svg width="48" height="48" viewBox="0 0 24 24" fill="var(--disabled, #3A4A5C)">
          <path d="M16 11c1.66 0 2.99-1.34 2.99-3S17.66 5 16 5c-1.66 0-3 1.34-3 3s1.34 3 3 3zm-8 0c1.66 0 2.99-1.34 2.99-3S9.66 5 8 5C6.34 5 5 6.34 5 8s1.34 3 3 3zm0 2c-2.33 0-7 1.17-7 3.5V19h14v-2.5c0-2.33-4.67-3.5-7-3.5zm8 0c-.29 0-.62.02-.97.05 1.16.84 1.97 1.97 1.97 3.45V19h6v-2.5c0-2.33-4.67-3.5-7-3.5z"/>
        </svg>
      </div>
      <h2 class="no-company-title">Not a member of any trucking company</h2>
      <p class="no-company-desc">Ask a company owner for an invite, or create your own.</p>

      <div class="create-company-form">
        <input
          type="text"
          class="input-field"
          placeholder="Company name..."
          bind:value={createCompanyName}
          maxlength="50"
          on:keydown={(e) => e.key === 'Enter' && createCompany()}
        />
        <button
          class="btn-primary"
          on:click={createCompany}
          disabled={!createCompanyName.trim()}
        >
          Create Company
        </button>
      </div>
    </div>

  {:else if isOwnerOrDispatcher}
    <!-- Owner/Dispatcher View -->
    <div class="company-header-card">
      <div class="company-name-row">
        <h2 class="company-name">{company.name}</h2>
        <span class="member-count">{members.length} members</span>
      </div>
      <div class="company-actions">
        {#if isOwner}
          <button class="btn-action" on:click={promptInvite}>
            <svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><path d="M15 12c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm-9-2V7H4v3H1v2h3v3h2v-3h3v-2H6zm9 4c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z"/></svg>
            Invite Member
          </button>
        {/if}
        {#if isDispatcher}
          <button class="btn-action dispatch" on:click={toggleDispatchMode}>
            <svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><path d="M20 2H4c-1.1 0-2 .9-2 2v16c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2zm-8 2.5c1.93 0 3.5 1.57 3.5 3.5s-1.57 3.5-3.5 3.5S8.5 9.93 8.5 8s1.57-3.5 3.5-3.5zm7 13H5v-.23c0-.62.28-1.2.76-1.58C7.47 14.43 9.64 13.5 12 13.5s4.53.93 6.24 2.19c.48.38.76.97.76 1.58v.23z"/></svg>
            Dispatcher Mode
          </button>
        {/if}
        <button class="btn-action" on:click={createConvoy}>
          <svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><path d="M20 8h-3V4H3c-1.1 0-2 .9-2 2v11h2c0 1.66 1.34 3 3 3s3-1.34 3-3h6c0 1.66 1.34 3 3 3s3-1.34 3-3h2v-5l-3-4z"/></svg>
          Create Convoy
        </button>
      </div>
    </div>

    {#if showInviteInput}
      <div class="invite-input-row">
        <input
          type="text"
          class="input-field"
          placeholder="Player name or ID..."
          bind:value={inviteName}
          on:keydown={(e) => e.key === 'Enter' && sendInvite()}
        />
        <button class="btn-primary small" on:click={sendInvite} disabled={!inviteName.trim()}>Send</button>
        <button class="btn-secondary small" on:click={() => { showInviteInput = false; inviteName = ''; }}>Cancel</button>
      </div>
    {/if}

    <!-- Driver Roster -->
    <div class="section">
      <h2 class="section-title">DRIVER ROSTER</h2>
      <div class="roster-list">
        {#each members as member}
          <div class="roster-row">
            <div class="roster-status-dot {getStatusIndicator(member.status)}"></div>
            <div class="roster-info">
              <div class="roster-name-row">
                <span class="roster-name">{member.name}</span>
                <span class="role-badge {getRoleBadgeClass(member.role)}">{getRoleLabel(member.role)}</span>
              </div>
              <div class="roster-meta">
                <span class="roster-status-label">{getStatusLabel(member.status)}</span>
                {#if member.activeLoad}
                  <span class="roster-load-info">
                    {member.activeLoad.cargoType} &rarr; {member.activeLoad.destination}
                    {#if member.activeLoad.eta}
                      <span class="roster-eta mono">ETA {member.activeLoad.eta}m</span>
                    {/if}
                  </span>
                {/if}
              </div>
            </div>
            {#if isOwner && member.citizenid !== $playerData.citizenid}
              <div class="roster-actions">
                {#if member.role === 'driver'}
                  <button class="btn-icon" title="Assign Dispatcher" on:click={() => promptAssignDispatcher(member)}>
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 15l-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9z"/></svg>
                  </button>
                {/if}
                <button class="btn-icon danger" title="Remove" on:click={() => promptRemoveMember(member)}>
                  <svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><path d="M19 13H5v-2h14v2z"/></svg>
                </button>
              </div>
            {/if}
          </div>
        {/each}
      </div>
    </div>

    <!-- Active Loads -->
    {#if activeLoads.length > 0}
      <div class="section">
        <h2 class="section-title">ACTIVE LOADS ({activeLoads.length})</h2>
        <div class="active-loads-list">
          {#each activeLoads as load}
            <div class="load-row">
              <div class="load-driver">{load.driverName}</div>
              <div class="load-details">
                <span class="load-cargo">{load.cargoType}</span>
                <span class="load-sep">&rarr;</span>
                <span class="load-dest">{load.destination}</span>
              </div>
              <div class="load-status-badge">{load.status || 'In Transit'}</div>
            </div>
          {/each}
        </div>
      </div>
    {/if}

  {:else}
    <!-- Driver View -->
    <div class="company-header-card">
      <div class="company-name-row">
        <h2 class="company-name">{company.name}</h2>
        <span class="role-badge {getRoleBadgeClass(myRole)}">{getRoleLabel(myRole)}</span>
      </div>
    </div>

    <!-- Members List -->
    <div class="section">
      <h2 class="section-title">COMPANY MEMBERS</h2>
      <div class="roster-list">
        {#each members as member}
          <div class="roster-row compact">
            <div class="roster-status-dot {getStatusIndicator(member.status)}"></div>
            <div class="roster-info">
              <div class="roster-name-row">
                <span class="roster-name">{member.name}</span>
                <span class="role-badge small {getRoleBadgeClass(member.role)}">{getRoleLabel(member.role)}</span>
              </div>
              <span class="roster-status-label">{getStatusLabel(member.status)}</span>
            </div>
          </div>
        {/each}
      </div>
    </div>

    <!-- My Stats -->
    <div class="section">
      <h2 class="section-title">YOUR COMPANY STATS</h2>
      <div class="driver-stats">
        <div class="stat-item">
          <span class="stat-value mono">{$playerData.totalLoadsCompleted}</span>
          <span class="stat-label">Deliveries</span>
        </div>
        <div class="stat-item">
          <span class="stat-value mono">${($playerData.totalEarnings || 0).toLocaleString()}</span>
          <span class="stat-label">Earnings</span>
        </div>
        <div class="stat-item">
          <span class="stat-value mono">{($playerData.totalDistanceDriven || 0).toLocaleString()} mi</span>
          <span class="stat-label">Distance</span>
        </div>
      </div>
    </div>

    <button class="btn-danger full-width" on:click={promptLeaveCompany}>
      Leave Company
    </button>
  {/if}
</div>

<ConfirmDialog
  visible={confirmVisible}
  title={confirmTitle}
  message={confirmMessage}
  {confirmStyle}
  on:confirm={handleConfirm}
  on:cancel={handleCancel}
/>

<style>
  .company-screen {
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
    margin-bottom: 20px;
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

  /* No Company State */
  .no-company {
    text-align: center;
    padding: 40px 24px;
    background: var(--navy-dark, #051229);
    border: 1px solid var(--border, #1E3A6E);
    border-radius: 8px;
  }

  .no-company-icon {
    margin-bottom: 16px;
  }

  .no-company-title {
    font-family: 'Barlow Condensed', sans-serif;
    font-weight: 700;
    font-size: 18px;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    color: var(--white, #FFFFFF);
    margin: 0 0 8px 0;
  }

  .no-company-desc {
    font-family: 'Inter', sans-serif;
    font-size: 14px;
    color: var(--muted, #A8B4C8);
    margin: 0 0 24px 0;
  }

  .create-company-form {
    display: flex;
    gap: 10px;
    justify-content: center;
    max-width: 400px;
    margin: 0 auto;
  }

  .input-field {
    flex: 1;
    font-family: 'Inter', sans-serif;
    font-size: 14px;
    background: var(--navy, #0B1F45);
    color: var(--white, #FFFFFF);
    border: 1px solid var(--border, #1E3A6E);
    border-radius: 4px;
    padding: 10px 14px;
    outline: none;
    transition: border-color 0.15s;
  }

  .input-field:focus {
    border-color: var(--orange, #C83803);
  }

  .input-field::placeholder {
    color: var(--disabled, #3A4A5C);
  }

  .btn-primary {
    font-family: 'Barlow Condensed', sans-serif;
    font-weight: 700;
    font-size: 14px;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    background: var(--orange, #C83803);
    color: var(--white, #FFFFFF);
    border: none;
    border-radius: 4px;
    padding: 10px 20px;
    cursor: pointer;
    transition: background 0.15s;
  }

  .btn-primary:hover:not(:disabled) {
    background: var(--orange-dim, #8A2702);
  }

  .btn-primary:disabled {
    background: var(--disabled, #3A4A5C);
    cursor: not-allowed;
  }

  .btn-primary.small, .btn-secondary.small {
    font-size: 12px;
    padding: 8px 14px;
  }

  .btn-secondary {
    font-family: 'Barlow Condensed', sans-serif;
    font-weight: 700;
    font-size: 14px;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    background: var(--navy-mid, #132E5C);
    color: var(--muted, #A8B4C8);
    border: 1px solid var(--border, #1E3A6E);
    border-radius: 4px;
    padding: 10px 20px;
    cursor: pointer;
    transition: background 0.15s;
  }

  .btn-secondary:hover {
    background: var(--border, #1E3A6E);
    color: var(--white, #FFFFFF);
  }

  /* Company Header */
  .company-header-card {
    background: var(--navy-dark, #051229);
    border: 1px solid var(--border, #1E3A6E);
    border-radius: 8px;
    padding: 16px 18px;
    margin-bottom: 16px;
  }

  .company-name-row {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 12px;
  }

  .company-name {
    font-family: 'Barlow Condensed', sans-serif;
    font-weight: 700;
    font-size: 20px;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    color: var(--white, #FFFFFF);
    margin: 0;
  }

  .member-count {
    font-family: 'Inter', sans-serif;
    font-size: 13px;
    color: var(--muted, #A8B4C8);
  }

  .company-actions {
    display: flex;
    gap: 8px;
    flex-wrap: wrap;
  }

  .btn-action {
    display: flex;
    align-items: center;
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
    padding: 8px 14px;
    cursor: pointer;
    transition: background 0.15s, color 0.15s;
  }

  .btn-action:hover {
    background: var(--border, #1E3A6E);
    color: var(--white, #FFFFFF);
  }

  .btn-action.dispatch {
    border-color: var(--orange, #C83803);
    color: var(--orange, #C83803);
  }

  .btn-action.dispatch:hover {
    background: rgba(200, 56, 3, 0.15);
  }

  /* Invite Input */
  .invite-input-row {
    display: flex;
    gap: 8px;
    margin-bottom: 16px;
    padding: 12px;
    background: var(--navy-dark, #051229);
    border: 1px solid var(--border, #1E3A6E);
    border-radius: 6px;
  }

  /* Role Badges */
  .role-badge {
    font-family: 'Barlow Condensed', sans-serif;
    font-weight: 700;
    font-size: 10px;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    padding: 3px 8px;
    border-radius: 3px;
  }

  .role-badge.small {
    font-size: 9px;
    padding: 2px 6px;
  }

  .role-owner {
    color: #FFD700;
    background: rgba(255, 215, 0, 0.12);
  }

  .role-dispatcher {
    color: var(--orange, #C83803);
    background: rgba(200, 56, 3, 0.12);
  }

  .role-driver {
    color: var(--muted, #A8B4C8);
    background: rgba(168, 180, 200, 0.1);
  }

  /* Roster */
  .roster-list {
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  .roster-row {
    display: flex;
    align-items: center;
    gap: 12px;
    background: var(--navy-dark, #051229);
    border: 1px solid var(--border, #1E3A6E);
    border-radius: 6px;
    padding: 10px 14px;
  }

  .roster-row.compact {
    padding: 8px 12px;
  }

  .roster-status-dot {
    width: 8px;
    height: 8px;
    border-radius: 50%;
    flex-shrink: 0;
  }

  .status-online {
    background: var(--success, #2D7A3E);
    box-shadow: 0 0 4px rgba(45, 122, 62, 0.5);
  }

  .status-delivery {
    background: var(--orange, #C83803);
    box-shadow: 0 0 4px rgba(200, 56, 3, 0.5);
    animation: pulse-status 2s ease-in-out infinite;
  }

  @keyframes pulse-status {
    0%, 100% { opacity: 1; }
    50% { opacity: 0.5; }
  }

  .status-offline {
    background: var(--disabled, #3A4A5C);
  }

  .roster-info {
    flex: 1;
    min-width: 0;
  }

  .roster-name-row {
    display: flex;
    align-items: center;
    gap: 8px;
    margin-bottom: 2px;
  }

  .roster-name {
    font-family: 'Inter', sans-serif;
    font-size: 14px;
    font-weight: 600;
    color: var(--white, #FFFFFF);
  }

  .roster-meta {
    display: flex;
    flex-direction: column;
    gap: 1px;
  }

  .roster-status-label {
    font-family: 'Inter', sans-serif;
    font-size: 11px;
    color: var(--muted, #A8B4C8);
  }

  .roster-load-info {
    font-family: 'Inter', sans-serif;
    font-size: 11px;
    color: var(--disabled, #3A4A5C);
  }

  .roster-eta {
    font-size: 10px;
    color: var(--warning, #C87B03);
    margin-left: 6px;
  }

  .roster-actions {
    display: flex;
    gap: 4px;
  }

  .btn-icon {
    background: var(--navy-mid, #132E5C);
    color: var(--muted, #A8B4C8);
    border: 1px solid var(--border, #1E3A6E);
    border-radius: 4px;
    width: 28px;
    height: 28px;
    display: flex;
    align-items: center;
    justify-content: center;
    cursor: pointer;
    transition: background 0.15s;
  }

  .btn-icon:hover {
    background: var(--border, #1E3A6E);
  }

  .btn-icon.danger {
    color: var(--orange, #C83803);
  }

  .btn-icon.danger:hover {
    background: rgba(200, 56, 3, 0.15);
  }

  /* Active Loads */
  .active-loads-list {
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  .load-row {
    display: flex;
    align-items: center;
    gap: 12px;
    background: var(--navy-dark, #051229);
    border: 1px solid var(--border, #1E3A6E);
    border-radius: 6px;
    padding: 10px 14px;
  }

  .load-driver {
    font-family: 'Inter', sans-serif;
    font-size: 13px;
    font-weight: 600;
    color: var(--white, #FFFFFF);
    min-width: 100px;
  }

  .load-details {
    flex: 1;
    display: flex;
    align-items: center;
    gap: 6px;
    font-family: 'Inter', sans-serif;
    font-size: 12px;
    color: var(--muted, #A8B4C8);
  }

  .load-cargo {
    color: var(--white, #FFFFFF);
  }

  .load-sep {
    color: var(--orange, #C83803);
  }

  .load-dest {
    color: var(--muted, #A8B4C8);
  }

  .load-status-badge {
    font-family: 'Barlow Condensed', sans-serif;
    font-weight: 700;
    font-size: 10px;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    color: var(--success, #2D7A3E);
    background: rgba(45, 122, 62, 0.12);
    padding: 3px 8px;
    border-radius: 3px;
  }

  /* Driver Stats */
  .driver-stats {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 10px;
  }

  .stat-item {
    background: var(--navy-dark, #051229);
    border: 1px solid var(--border, #1E3A6E);
    border-radius: 6px;
    padding: 14px 12px;
    text-align: center;
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  .stat-value {
    font-family: 'JetBrains Mono', monospace;
    font-size: 18px;
    font-weight: 700;
    color: var(--white, #FFFFFF);
  }

  .stat-label {
    font-family: 'Barlow Condensed', sans-serif;
    font-weight: 700;
    font-size: 10px;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    color: var(--muted, #A8B4C8);
  }

  /* Leave Button */
  .btn-danger {
    font-family: 'Barlow Condensed', sans-serif;
    font-weight: 700;
    font-size: 14px;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    background: transparent;
    color: var(--orange, #C83803);
    border: 1px solid var(--orange, #C83803);
    border-radius: 4px;
    padding: 12px 20px;
    cursor: pointer;
    transition: background 0.15s;
  }

  .btn-danger:hover {
    background: rgba(200, 56, 3, 0.1);
  }

  .full-width {
    width: 100%;
  }
</style>
