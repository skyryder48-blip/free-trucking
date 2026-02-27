<script>
  import { createEventDispatcher } from 'svelte';

  /**
   * TabBar — Reusable horizontal tab navigation.
   * @prop {Array<{id: string, label: string}>} tabs - Tab definitions
   * @prop {string} activeTab - Currently active tab id
   */
  export let tabs = [];
  export let activeTab = '';

  const dispatch = createEventDispatcher();

  function selectTab(tabId) {
    dispatch('tabChange', { tab: tabId });
  }
</script>

<div class="tab-bar">
  {#each tabs as tab (tab.id)}
    <button
      class="tab-item"
      class:tab-active={activeTab === tab.id}
      on:click={() => selectTab(tab.id)}
    >
      {tab.label}
      {#if tab.count !== undefined}
        <span class="tab-count mono">{tab.count}</span>
      {/if}
    </button>
  {/each}
</div>

<style>
  .tab-bar {
    display: flex;
    gap: 2px;
    background: var(--navy-dark);
    border-radius: var(--radius-md);
    padding: 2px;
    margin-bottom: var(--spacing-lg);
  }

  .tab-item {
    flex: 1;
    display: flex;
    align-items: center;
    justify-content: center;
    gap: var(--spacing-xs);
    padding: var(--spacing-sm) var(--spacing-md);
    background: none;
    border: none;
    border-radius: var(--radius-sm);
    color: var(--muted);
    font-family: var(--font-heading);
    font-weight: 700;
    font-size: 12px;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    cursor: pointer;
    transition: color 0.15s ease, background 0.15s ease;
  }

  .tab-item:hover {
    color: var(--white);
    background: rgba(30, 58, 110, 0.3);
  }

  .tab-active {
    color: var(--white);
    background: var(--navy-mid);
  }

  .tab-count {
    font-size: 10px;
    padding: 1px 5px;
    border-radius: 8px;
    background: rgba(30, 58, 110, 0.5);
    color: var(--muted);
    line-height: 1.3;
  }

  .tab-active .tab-count {
    background: var(--orange);
    color: var(--white);
  }
</style>
