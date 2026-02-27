<script>
  import { hudData, convoyData } from '../lib/stores.js';

  $: visible = $hudData.visible;
  $: borderState = $hudData.borderState;

  $: formattedDistance = $hudData.distanceRemaining.toFixed(1);

  $: formattedTime = formatTime($hudData.timeRemaining);

  function formatTime(seconds) {
    if (seconds <= 0) return '0:00:00';
    const h = Math.floor(seconds / 3600);
    const m = Math.floor((seconds % 3600) / 60);
    const s = seconds % 60;
    return `${h}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
  }

  $: hasTemp = $hudData.temperature !== null;
  $: tempDisplay = hasTemp ? `${$hudData.temperature}°F` : null;
  $: tempOk = $hudData.tempInRange;

  $: integrityPct = $hudData.integrity;

  $: showConvoy = $convoyData.active && $convoyData.members.length > 0;
</script>

{#if visible}
  <div
    class="hud-overlay"
    class:border-normal={borderState === 'normal'}
    class:border-warning={borderState === 'warning'}
    class:border-critical={borderState === 'critical'}
  >
    <div class="hud-line line-1">
      <span class="bol-number">BOL #{$hudData.bolNumber}</span>
      <span class="separator">&middot;</span>
      <span class="cargo-type">{$hudData.cargoType}</span>
    </div>

    <div class="hud-line line-2">
      <span class="destination-arrow">&rarr;</span>
      <span class="destination">{$hudData.destination}</span>
      <span class="separator">&middot;</span>
      <span class="distance mono">{formattedDistance} mi</span>
    </div>

    <div class="hud-line line-3">
      <span class="time mono">{formattedTime}</span>
      {#if hasTemp}
        <span class="separator">&middot;</span>
        <span class="temp" class:temp-ok={tempOk} class:temp-bad={!tempOk}>
          {tempDisplay} {tempOk ? '\u2713' : '\u2717'}
        </span>
      {/if}
      <span class="separator">&middot;</span>
      <span
        class="integrity mono"
        class:integrity-low={integrityPct < 50}
        class:integrity-ok={integrityPct >= 50}
      >{integrityPct}%</span>
    </div>
  </div>

  {#if showConvoy}
    <div class="convoy-overlay">
      {#each $convoyData.members as member}
        <div class="convoy-member">
          <span class="convoy-name">{member.name}</span>
          <span class="convoy-distance mono">{member.distance ? member.distance.toFixed(1) + ' mi' : '---'}</span>
        </div>
      {/each}
    </div>
  {/if}
{/if}

<style>
  .hud-overlay {
    position: fixed;
    top: 16px;
    right: 16px;
    z-index: 8000;
    background: rgba(5, 18, 41, 0.82);
    backdrop-filter: blur(4px);
    border-radius: 6px;
    padding: 10px 16px;
    min-width: 280px;
    border: 2px solid var(--border, #1E3A6E);
    pointer-events: none;
    user-select: none;
  }

  .hud-overlay.border-normal {
    border-color: var(--border, #1E3A6E);
  }

  .hud-overlay.border-warning {
    border-color: var(--warning, #C87B03);
  }

  .hud-overlay.border-critical {
    border-color: var(--orange, #C83803);
    animation: hud-pulse 1.5s ease-in-out infinite;
  }

  @keyframes hud-pulse {
    0%, 100% { border-color: var(--orange, #C83803); }
    50% { border-color: rgba(200, 56, 3, 0.4); }
  }

  .hud-line {
    display: flex;
    align-items: center;
    gap: 6px;
    line-height: 1.6;
    white-space: nowrap;
  }

  .separator {
    color: var(--disabled, #3A4A5C);
    font-size: 12px;
  }

  .bol-number {
    font-family: 'JetBrains Mono', monospace;
    font-size: 13px;
    font-weight: 600;
    color: var(--white, #FFFFFF);
  }

  .cargo-type {
    font-family: 'Inter', sans-serif;
    font-size: 13px;
    color: var(--muted, #A8B4C8);
  }

  .destination-arrow {
    color: var(--orange, #C83803);
    font-size: 14px;
    font-weight: 700;
  }

  .destination {
    font-family: 'Inter', sans-serif;
    font-size: 13px;
    color: var(--white, #FFFFFF);
  }

  .distance {
    font-size: 13px;
    color: var(--muted, #A8B4C8);
  }

  .mono {
    font-family: 'JetBrains Mono', monospace;
  }

  .time {
    font-size: 13px;
    color: var(--white, #FFFFFF);
  }

  .temp {
    font-family: 'JetBrains Mono', monospace;
    font-size: 12px;
  }

  .temp-ok {
    color: var(--success, #2D7A3E);
  }

  .temp-bad {
    color: var(--orange, #C83803);
  }

  .integrity {
    font-size: 12px;
  }

  .integrity-ok {
    color: var(--success, #2D7A3E);
  }

  .integrity-low {
    color: var(--orange, #C83803);
  }

  /* Convoy sub-overlay */
  .convoy-overlay {
    position: fixed;
    top: 96px;
    right: 16px;
    z-index: 7999;
    background: rgba(5, 18, 41, 0.72);
    backdrop-filter: blur(4px);
    border: 1px solid var(--border, #1E3A6E);
    border-radius: 4px;
    padding: 6px 12px;
    min-width: 180px;
    pointer-events: none;
    user-select: none;
  }

  .convoy-member {
    display: flex;
    justify-content: space-between;
    align-items: center;
    gap: 12px;
    padding: 2px 0;
  }

  .convoy-name {
    font-family: 'Inter', sans-serif;
    font-size: 11px;
    color: var(--muted, #A8B4C8);
    overflow: hidden;
    text-overflow: ellipsis;
    max-width: 100px;
  }

  .convoy-distance {
    font-size: 11px;
    color: var(--white, #FFFFFF);
  }
</style>
