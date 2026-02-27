<script>
  import { currentScreen, activeLoad } from '../lib/stores.js';

  export let phoneMode = false;

  const navItems = [
    { id: 'home', label: 'Home', icon: 'home' },
    { id: 'board', label: 'Board', icon: 'board' },
    { id: 'activeload', label: 'Load', icon: 'load', requiresLoad: true },
    { id: 'profile', label: 'Profile', icon: 'profile' },
    { id: 'insurance', label: 'Insurance', icon: 'insurance' },
    { id: 'company', label: 'Company', icon: 'company' },
  ];

  function navigate(screenId) {
    currentScreen.set(screenId);
  }

  $: hasActiveLoad = $activeLoad !== null;
  $: visibleItems = navItems.filter(item => !item.requiresLoad || hasActiveLoad);
</script>

<nav class="navigation-bar" class:phone-mode={phoneMode}>
  {#each visibleItems as item}
    <button
      class="nav-item"
      class:active={$currentScreen === item.id}
      on:click={() => navigate(item.id)}
    >
      <span class="nav-icon">
        {#if item.icon === 'home'}
          <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor">
            <path d="M10 20v-6h4v6h5v-8h3L12 3 2 12h3v8z"/>
          </svg>
        {:else if item.icon === 'board'}
          <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor">
            <path d="M19 3H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2zm0 16H5V5h14v14zM7 7h10v2H7zm0 4h10v2H7zm0 4h7v2H7z"/>
          </svg>
        {:else if item.icon === 'load'}
          <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor">
            <path d="M20 8h-3V4H3c-1.1 0-2 .9-2 2v11h2c0 1.66 1.34 3 3 3s3-1.34 3-3h6c0 1.66 1.34 3 3 3s3-1.34 3-3h2v-5l-3-4zM6 18.5c-.83 0-1.5-.67-1.5-1.5s.67-1.5 1.5-1.5 1.5.67 1.5 1.5-.67 1.5-1.5 1.5zm13.5-9l1.96 2.5H17V9.5h2.5zm-1.5 9c-.83 0-1.5-.67-1.5-1.5s.67-1.5 1.5-1.5 1.5.67 1.5 1.5-.67 1.5-1.5 1.5z"/>
          </svg>
        {:else if item.icon === 'profile'}
          <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor">
            <path d="M12 12c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm0 2c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z"/>
          </svg>
        {:else if item.icon === 'insurance'}
          <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor">
            <path d="M12 1L3 5v6c0 5.55 3.84 10.74 9 12 5.16-1.26 9-6.45 9-12V5l-9-4zm-2 16l-4-4 1.41-1.41L10 14.17l6.59-6.59L18 9l-8 8z"/>
          </svg>
        {:else if item.icon === 'company'}
          <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor">
            <path d="M16 11c1.66 0 2.99-1.34 2.99-3S17.66 5 16 5c-1.66 0-3 1.34-3 3s1.34 3 3 3zm-8 0c1.66 0 2.99-1.34 2.99-3S9.66 5 8 5C6.34 5 5 6.34 5 8s1.34 3 3 3zm0 2c-2.33 0-7 1.17-7 3.5V19h14v-2.5c0-2.33-4.67-3.5-7-3.5zm8 0c-.29 0-.62.02-.97.05 1.16.84 1.97 1.97 1.97 3.45V19h6v-2.5c0-2.33-4.67-3.5-7-3.5z"/>
          </svg>
        {/if}
      </span>
      <span class="nav-label">{item.label}</span>
      {#if item.requiresLoad && hasActiveLoad}
        <span class="active-indicator"></span>
      {/if}
    </button>
  {/each}
</nav>

<style>
  .navigation-bar {
    display: flex;
    align-items: stretch;
    background: var(--navy-dark, #051229);
    border-top: 1px solid var(--border, #1E3A6E);
    padding: 4px 8px;
    gap: 2px;
  }

  .navigation-bar.phone-mode {
    padding: 2px 4px;
  }

  .nav-item {
    flex: 1;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 3px;
    padding: 8px 4px 6px;
    background: transparent;
    border: none;
    border-radius: 6px;
    cursor: pointer;
    position: relative;
    transition: background 0.15s, color 0.15s;
    color: var(--muted, #A8B4C8);
  }

  .phone-mode .nav-item {
    padding: 6px 2px 4px;
  }

  .nav-item:hover {
    background: rgba(30, 58, 110, 0.4);
    color: var(--white, #FFFFFF);
  }

  .nav-item.active {
    color: var(--orange, #C83803);
    background: rgba(200, 56, 3, 0.08);
  }

  .nav-item.active::after {
    content: '';
    position: absolute;
    top: 0;
    left: 20%;
    right: 20%;
    height: 2px;
    background: var(--orange, #C83803);
    border-radius: 0 0 2px 2px;
  }

  .nav-icon {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 24px;
    height: 24px;
  }

  .phone-mode .nav-icon {
    width: 20px;
    height: 20px;
  }

  .nav-icon svg {
    transition: transform 0.15s;
  }

  .nav-item.active .nav-icon svg {
    transform: scale(1.1);
  }

  .nav-label {
    font-family: 'Barlow Condensed', sans-serif;
    font-weight: 700;
    font-size: 10px;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    line-height: 1;
  }

  .phone-mode .nav-label {
    font-size: 9px;
  }

  .active-indicator {
    position: absolute;
    top: 6px;
    right: 12px;
    width: 6px;
    height: 6px;
    border-radius: 50%;
    background: var(--success, #2D7A3E);
    animation: pulse-dot 2s ease-in-out infinite;
  }

  @keyframes pulse-dot {
    0%, 100% { opacity: 1; }
    50% { opacity: 0.4; }
  }
</style>
