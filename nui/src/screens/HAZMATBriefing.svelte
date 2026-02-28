<script>
  import { fetchNUI } from '../lib/nui.js';
  import { hazmatBriefingData } from '../lib/stores.js';

  let currentTopic = 0;
  let completing = false;

  $: topics = $hazmatBriefingData?.topics || [];
  $: totalTopics = topics.length;
  $: allRead = currentTopic >= totalTopics - 1;

  function nextTopic() {
    if (currentTopic < totalTopics - 1) {
      currentTopic++;
    }
  }

  function prevTopic() {
    if (currentTopic > 0) {
      currentTopic--;
    }
  }

  async function completeBriefing() {
    if (completing) return;
    completing = true;
    await fetchNUI('trucking:completeHAZMATBriefing');
  }

  function closeBriefing() {
    fetchNUI('trucking:closeCDLTest');
  }
</script>

<div class="hazmat-briefing">
  <div class="briefing-header">
    <h2>HAZMAT Safety Briefing</h2>
    <span class="hazmat-badge">ENDORSEMENT</span>
    <button class="close-btn" on:click={closeBriefing} aria-label="Close">
      <svg width="14" height="14" viewBox="0 0 16 16" fill="none">
        <path d="M12 4L4 12M4 4L12 12" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>
      </svg>
    </button>
  </div>

  <!-- Topic progress -->
  <div class="topic-progress">
    {#each topics as topic, i}
      <button
        class="topic-pip"
        class:read={i <= currentTopic}
        class:current={i === currentTopic}
        on:click={() => { if (i <= currentTopic) currentTopic = i; }}
        aria-label="Topic {i + 1}"
      >{i + 1}</button>
    {/each}
  </div>

  <div class="progress-label">
    Topic {currentTopic + 1} of {totalTopics}
  </div>

  <!-- Current topic -->
  {#if topics[currentTopic]}
    {@const topic = topics[currentTopic]}
    <div class="topic-card">
      <div class="topic-id">Topic {topic.id || currentTopic + 1}</div>
      <h3 class="topic-title">{topic.title}</h3>
      <p class="topic-description">{topic.description}</p>
    </div>
  {/if}

  <!-- Navigation -->
  <div class="nav-buttons">
    <button
      class="nav-btn"
      disabled={currentTopic === 0}
      on:click={prevTopic}
    >Previous</button>

    {#if currentTopic < totalTopics - 1}
      <button
        class="nav-btn nav-next"
        on:click={nextTopic}
      >Next Topic</button>
    {:else}
      <button
        class="nav-btn nav-complete"
        disabled={completing}
        on:click={completeBriefing}
      >{completing ? 'Processing...' : 'Complete Briefing'}</button>
    {/if}
  </div>
</div>

<style>
  .hazmat-briefing {
    padding: var(--spacing-md, 12px);
  }

  .briefing-header {
    display: flex;
    align-items: center;
    gap: var(--spacing-sm, 8px);
    margin-bottom: var(--spacing-md, 12px);
  }

  .briefing-header h2 {
    margin: 0;
    font-size: 18px;
    color: var(--white, #fff);
  }

  .hazmat-badge {
    font-size: 10px;
    color: #e6a817;
    background: rgba(230, 168, 23, 0.15);
    padding: 2px 8px;
    border-radius: var(--radius-sm, 4px);
    font-weight: 700;
    letter-spacing: 0.08em;
  }

  .briefing-header .close-btn {
    margin-left: auto;
    background: none;
    border: none;
    color: var(--muted, #A8B4C8);
    cursor: pointer;
    padding: 4px;
  }

  .briefing-header .close-btn:hover {
    color: var(--white, #fff);
  }

  .topic-progress {
    display: flex;
    gap: 6px;
    margin-bottom: 4px;
  }

  .topic-pip {
    width: 36px;
    height: 36px;
    border-radius: var(--radius-sm, 4px);
    border: 1px solid var(--border, #1E3A6E);
    background: var(--navy-dark, #051229);
    color: var(--muted, #A8B4C8);
    font-size: 13px;
    font-weight: 700;
    cursor: pointer;
    display: flex;
    align-items: center;
    justify-content: center;
    transition: all 0.15s ease;
  }

  .topic-pip.read {
    background: rgba(230, 168, 23, 0.15);
    border-color: #e6a817;
    color: #e6a817;
    cursor: pointer;
  }

  .topic-pip.current {
    border-color: var(--white, #fff);
    color: var(--white, #fff);
    background: rgba(230, 168, 23, 0.25);
  }

  .progress-label {
    font-size: 12px;
    color: var(--muted, #A8B4C8);
    margin-bottom: var(--spacing-md, 12px);
  }

  .topic-card {
    background: var(--navy-dark, #051229);
    border: 1px solid var(--border, #1E3A6E);
    border-radius: var(--radius-md, 8px);
    padding: var(--spacing-lg, 16px);
    margin-bottom: var(--spacing-md, 12px);
    min-height: 180px;
  }

  .topic-id {
    font-size: 11px;
    color: #e6a817;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    font-weight: 700;
    margin-bottom: 8px;
  }

  .topic-title {
    color: var(--white, #fff);
    font-size: 16px;
    margin: 0 0 12px 0;
  }

  .topic-description {
    color: var(--muted, #A8B4C8);
    font-size: 13px;
    line-height: 1.6;
    margin: 0;
    white-space: pre-line;
  }

  .nav-buttons {
    display: flex;
    justify-content: space-between;
    gap: var(--spacing-sm, 8px);
  }

  .nav-btn {
    padding: 8px 20px;
    border: 1px solid var(--border, #1E3A6E);
    border-radius: var(--radius-sm, 4px);
    background: var(--navy-dark, #051229);
    color: var(--muted, #A8B4C8);
    font-weight: 600;
    font-size: 13px;
    cursor: pointer;
    transition: color 0.15s, border-color 0.15s;
  }

  .nav-btn:hover:not(:disabled) {
    color: var(--white, #fff);
    border-color: var(--white, #fff);
  }

  .nav-btn:disabled {
    opacity: 0.4;
    cursor: not-allowed;
  }

  .nav-next {
    margin-left: auto;
  }

  .nav-complete {
    margin-left: auto;
    background: #e6a817;
    border-color: #e6a817;
    color: #1a1a1a;
    font-weight: 700;
  }

  .nav-complete:hover:not(:disabled) {
    background: #f0b81e;
    border-color: #f0b81e;
  }
</style>
