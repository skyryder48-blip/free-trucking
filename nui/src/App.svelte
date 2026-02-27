<script>
  import { onMount, onDestroy } from 'svelte';
  import { onNUIMessage, closeNUI, isEnvBrowser } from './lib/nui.js';
  import {
    currentScreen,
    playerData,
    activeLoad,
    boardData,
    insuranceData,
    companyData,
    hudData,
    convoyData,
    visibility,
  } from './lib/stores.js';

  import Home from './screens/Home.svelte';
  import Board from './screens/Board.svelte';
  import LoadDetail from './screens/LoadDetail.svelte';
  import ActiveLoad from './screens/ActiveLoad.svelte';

  /** @type {'standalone' | 'phone'} */
  let mode = 'standalone';

  /** Data passed to LoadDetail screen */
  let selectedLoad = null;

  let removeListener;

  function handleKeyDown(e) {
    if (e.key === 'Escape') {
      e.preventDefault();
      handleClose();
    }
  }

  function handleClose() {
    visibility.set(false);
    closeNUI();
  }

  function navigateTo(screen, data = null) {
    if (screen === 'loadDetail' && data) {
      selectedLoad = data;
    }
    currentScreen.set(screen);
  }

  onMount(() => {
    // In browser dev mode, show the UI immediately for development
    if (isEnvBrowser()) {
      visibility.set(true);
      playerData.set({
        citizenid: 'DEV123',
        name: 'Dev Driver',
        reputationScore: 650,
        reputationTier: 'established',
        suspendedUntil: null,
        totalLoadsCompleted: 42,
        totalLoadsFailed: 2,
        totalLoadsStolen: 0,
        totalDistanceDriven: 1280,
        totalEarnings: 87500,
        licenses: [
          { type: 'class_b', status: 'active' },
          { type: 'class_a', status: 'active' },
        ],
        certifications: [
          { type: 'bilkington_carrier', status: 'active' },
        ],
        leonAccess: false,
      });
    }

    removeListener = onNUIMessage((action, data) => {
      switch (action) {
        case 'show':
          visibility.set(true);
          mode = data.mode || 'standalone';
          if (data.screen) {
            currentScreen.set(data.screen);
          }
          break;

        case 'hide':
          visibility.set(false);
          break;

        case 'setScreen':
          currentScreen.set(data.screen);
          if (data.screen === 'loadDetail' && data.load) {
            selectedLoad = data.load;
          }
          break;

        case 'updatePlayer':
          playerData.set(data.player);
          break;

        case 'updateActiveLoad':
          activeLoad.set(data.load);
          break;

        case 'updateBoard':
          boardData.set(data.board);
          break;

        case 'updateInsurance':
          insuranceData.set(data.insurance);
          break;

        case 'updateCompany':
          companyData.set(data.company);
          break;

        case 'updateHud':
          hudData.set(data.hud);
          break;

        case 'updateConvoy':
          convoyData.set(data.convoy);
          break;
      }
    });

    window.addEventListener('keydown', handleKeyDown);
  });

  onDestroy(() => {
    if (removeListener) removeListener();
    window.removeEventListener('keydown', handleKeyDown);
  });

  $: isVisible = $visibility;
  $: screen = $currentScreen;
</script>

{#if isVisible}
  <div class="nui-wrapper" class:phone-mode={mode === 'phone'} class:standalone-mode={mode === 'standalone'}>
    <div class="nui-container fade-in">
      <!-- Navigation header -->
      <header class="nui-header">
        <div class="header-left">
          <h1 class="header-title">Trucking</h1>
        </div>
        <nav class="header-nav">
          <button
            class="nav-btn"
            class:nav-active={screen === 'home'}
            on:click={() => navigateTo('home')}
          >Home</button>
          <button
            class="nav-btn"
            class:nav-active={screen === 'board' || screen === 'loadDetail'}
            on:click={() => navigateTo('board')}
          >Board</button>
          {#if $activeLoad}
            <button
              class="nav-btn"
              class:nav-active={screen === 'activeLoad'}
              on:click={() => navigateTo('activeLoad')}
            >Active Load</button>
          {/if}
        </nav>
        <button class="close-btn" on:click={handleClose} aria-label="Close">
          <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
            <path d="M12 4L4 12M4 4L12 12" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>
          </svg>
        </button>
      </header>

      <!-- Screen router -->
      <main class="nui-content">
        {#if screen === 'home'}
          <Home on:navigate={(e) => navigateTo(e.detail.screen, e.detail.data)} />
        {:else if screen === 'board'}
          <Board on:navigate={(e) => navigateTo(e.detail.screen, e.detail.data)} />
        {:else if screen === 'loadDetail'}
          <LoadDetail
            load={selectedLoad}
            on:navigate={(e) => navigateTo(e.detail.screen, e.detail.data)}
            on:back={() => navigateTo('board')}
          />
        {:else if screen === 'activeLoad'}
          <ActiveLoad on:navigate={(e) => navigateTo(e.detail.screen, e.detail.data)} />
        {/if}
      </main>
    </div>
  </div>
{/if}

<style>
  .nui-wrapper {
    position: fixed;
    top: 0;
    left: 0;
    width: 100vw;
    height: 100vh;
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 999;
  }

  .standalone-mode {
    background: rgba(5, 18, 41, 0.85);
  }

  .phone-mode .nui-container {
    width: 100%;
    height: 100%;
    max-width: none;
    max-height: none;
    border-radius: 0;
    border: none;
  }

  .nui-container {
    width: 680px;
    max-height: 85vh;
    background: var(--navy);
    border: 1px solid var(--border);
    border-radius: var(--radius-lg);
    display: flex;
    flex-direction: column;
    overflow: hidden;
  }

  .nui-header {
    display: flex;
    align-items: center;
    padding: var(--spacing-md) var(--spacing-lg);
    border-bottom: 1px solid var(--border);
    background: var(--navy-dark);
    flex-shrink: 0;
  }

  .header-left {
    display: flex;
    align-items: center;
    gap: var(--spacing-sm);
  }

  .header-title {
    font-size: 18px;
    color: var(--orange);
    margin: 0;
  }

  .header-nav {
    display: flex;
    gap: var(--spacing-xs);
    margin-left: var(--spacing-xl);
    flex: 1;
  }

  .nav-btn {
    background: none;
    border: none;
    color: var(--muted);
    font-family: var(--font-heading);
    font-weight: 700;
    font-size: 13px;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    padding: var(--spacing-xs) var(--spacing-sm);
    border-radius: var(--radius-sm);
    cursor: pointer;
    transition: color 0.15s ease, background 0.15s ease;
  }

  .nav-btn:hover {
    color: var(--white);
    background: rgba(30, 58, 110, 0.3);
  }

  .nav-active {
    color: var(--orange);
    background: rgba(200, 56, 3, 0.1);
  }

  .close-btn {
    background: none;
    border: none;
    color: var(--muted);
    cursor: pointer;
    padding: var(--spacing-xs);
    border-radius: var(--radius-sm);
    display: flex;
    align-items: center;
    justify-content: center;
    transition: color 0.15s ease;
  }

  .close-btn:hover {
    color: var(--white);
  }

  .nui-content {
    flex: 1;
    overflow-y: auto;
    padding: var(--spacing-lg);
  }
</style>
