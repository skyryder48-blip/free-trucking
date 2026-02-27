<script>
  /** Current temperature in Fahrenheit */
  export let currentTemp = null;
  /** Minimum acceptable temperature */
  export let minTemp = null;
  /** Maximum acceptable temperature */
  export let maxTemp = null;
  /** Whether the reefer unit is operational */
  export let reeferOperational = true;
  /** Whether there is an active excursion */
  export let excursionActive = false;
  /** Total excursion minutes accumulated */
  export let excursionMinutes = 0;

  $: inRange = currentTemp !== null && minTemp !== null && maxTemp !== null
    ? (currentTemp >= minTemp && currentTemp <= maxTemp)
    : true;

  $: rangeCenter = (minTemp !== null && maxTemp !== null)
    ? (minTemp + maxTemp) / 2
    : 0;

  $: rangeSpan = (minTemp !== null && maxTemp !== null)
    ? maxTemp - minTemp
    : 0;

  $: displayLow = minTemp !== null ? minTemp - rangeSpan : 0;
  $: displayHigh = maxTemp !== null ? maxTemp + rangeSpan : 100;
  $: displaySpan = displayHigh - displayLow;

  $: needlePosition = currentTemp !== null && displaySpan > 0
    ? Math.max(0, Math.min(100, ((currentTemp - displayLow) / displaySpan) * 100))
    : 50;

  $: rangeStart = displaySpan > 0
    ? ((minTemp - displayLow) / displaySpan) * 100
    : 25;

  $: rangeEnd = displaySpan > 0
    ? ((maxTemp - displayLow) / displaySpan) * 100
    : 75;

  $: statusText = getStatusText(currentTemp, inRange, reeferOperational, excursionActive);

  function getStatusText(temp, ok, reefer, excursion) {
    if (!reefer) return 'REEFER FAILURE';
    if (excursion) return 'EXCURSION';
    if (temp === null) return 'NO DATA';
    if (ok) return 'IN RANGE';
    return 'OUT OF RANGE';
  }

  $: statusClass = getStatusClass(inRange, reeferOperational, excursionActive);

  function getStatusClass(ok, reefer, excursion) {
    if (!reefer) return 'critical';
    if (excursion) return 'warning';
    if (ok) return 'normal';
    return 'warning';
  }
</script>

<div class="temp-gauge" class:warning={statusClass === 'warning'} class:critical={statusClass === 'critical'}>
  <div class="gauge-header">
    <span class="gauge-icon">
      <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor">
        <path d="M15 13V5c0-1.66-1.34-3-3-3S9 3.34 9 5v8c-1.21.91-2 2.37-2 4 0 2.76 2.24 5 5 5s5-2.24 5-5c0-1.63-.79-3.09-2-4zm-4-8c0-.55.45-1 1-1s1 .45 1 1v3h-2V5z"/>
      </svg>
    </span>
    <span class="gauge-label">TEMPERATURE</span>
    <span class="status-badge {statusClass}">{statusText}</span>
  </div>

  <div class="gauge-body">
    <div class="temp-display">
      <span class="temp-value" class:out={!inRange}>
        {currentTemp !== null ? currentTemp.toFixed(1) : '--'}
      </span>
      <span class="temp-unit">°F</span>
    </div>

    <div class="gauge-bar-container">
      <div class="gauge-bar">
        <div
          class="range-zone"
          style="left: {rangeStart}%; width: {rangeEnd - rangeStart}%"
        ></div>
        <div
          class="needle"
          class:out={!inRange}
          style="left: {needlePosition}%"
        >
          <div class="needle-line"></div>
          <div class="needle-dot"></div>
        </div>
      </div>
      <div class="range-labels">
        <span class="range-min mono">{minTemp !== null ? minTemp + '°F' : '--'}</span>
        <span class="range-max mono">{maxTemp !== null ? maxTemp + '°F' : '--'}</span>
      </div>
    </div>

    {#if excursionMinutes > 0}
      <div class="excursion-info">
        <span class="excursion-label">Excursion Time:</span>
        <span class="excursion-value mono">{excursionMinutes} min</span>
      </div>
    {/if}

    {#if !reeferOperational}
      <div class="reefer-warning">
        REEFER UNIT NOT OPERATIONAL — TEMPERATURE UNCONTROLLED
      </div>
    {/if}
  </div>
</div>

<style>
  .temp-gauge {
    background: var(--navy-dark, #051229);
    border: 1px solid var(--border, #1E3A6E);
    border-radius: 6px;
    padding: 14px 16px;
  }

  .temp-gauge.warning {
    border-color: var(--warning, #C87B03);
  }

  .temp-gauge.critical {
    border-color: var(--orange, #C83803);
    animation: pulse-border 1.5s ease-in-out infinite;
  }

  @keyframes pulse-border {
    0%, 100% { border-color: var(--orange, #C83803); }
    50% { border-color: rgba(200, 56, 3, 0.4); }
  }

  .gauge-header {
    display: flex;
    align-items: center;
    gap: 8px;
    margin-bottom: 12px;
  }

  .gauge-icon {
    color: var(--muted, #A8B4C8);
    display: flex;
    align-items: center;
  }

  .gauge-label {
    font-family: 'Barlow Condensed', sans-serif;
    font-weight: 700;
    font-size: 12px;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    color: var(--muted, #A8B4C8);
    flex: 1;
  }

  .status-badge {
    font-family: 'Barlow Condensed', sans-serif;
    font-weight: 700;
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    padding: 3px 8px;
    border-radius: 3px;
  }

  .status-badge.normal {
    color: var(--success, #2D7A3E);
    background: rgba(45, 122, 62, 0.15);
  }

  .status-badge.warning {
    color: var(--warning, #C87B03);
    background: rgba(200, 123, 3, 0.15);
  }

  .status-badge.critical {
    color: var(--orange, #C83803);
    background: rgba(200, 56, 3, 0.15);
  }

  .gauge-body {
    display: flex;
    flex-direction: column;
    gap: 10px;
  }

  .temp-display {
    display: flex;
    align-items: baseline;
    gap: 4px;
  }

  .temp-value {
    font-family: 'JetBrains Mono', monospace;
    font-size: 28px;
    font-weight: 700;
    color: var(--success, #2D7A3E);
    line-height: 1;
  }

  .temp-value.out {
    color: var(--orange, #C83803);
  }

  .temp-unit {
    font-family: 'JetBrains Mono', monospace;
    font-size: 14px;
    color: var(--muted, #A8B4C8);
  }

  .gauge-bar-container {
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  .gauge-bar {
    position: relative;
    height: 8px;
    background: rgba(30, 58, 110, 0.5);
    border-radius: 4px;
    overflow: visible;
  }

  .range-zone {
    position: absolute;
    top: 0;
    height: 100%;
    background: rgba(45, 122, 62, 0.35);
    border-radius: 4px;
  }

  .needle {
    position: absolute;
    top: 50%;
    transform: translateX(-50%);
    z-index: 2;
    transition: left 0.5s ease;
  }

  .needle-line {
    width: 2px;
    height: 16px;
    background: var(--success, #2D7A3E);
    margin: 0 auto;
    transform: translateY(-50%);
  }

  .needle.out .needle-line {
    background: var(--orange, #C83803);
  }

  .needle-dot {
    width: 8px;
    height: 8px;
    border-radius: 50%;
    background: var(--success, #2D7A3E);
    position: absolute;
    top: 50%;
    left: 50%;
    transform: translate(-50%, -50%);
  }

  .needle.out .needle-dot {
    background: var(--orange, #C83803);
  }

  .range-labels {
    display: flex;
    justify-content: space-between;
    padding: 0 2px;
  }

  .range-min, .range-max {
    font-size: 11px;
    color: var(--muted, #A8B4C8);
  }

  .mono {
    font-family: 'JetBrains Mono', monospace;
  }

  .excursion-info {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 6px 10px;
    background: rgba(200, 123, 3, 0.1);
    border-radius: 4px;
  }

  .excursion-label {
    font-family: 'Inter', sans-serif;
    font-size: 12px;
    color: var(--warning, #C87B03);
  }

  .excursion-value {
    font-size: 13px;
    color: var(--warning, #C87B03);
    font-weight: 600;
  }

  .reefer-warning {
    font-family: 'Barlow Condensed', sans-serif;
    font-weight: 700;
    font-size: 12px;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    color: var(--orange, #C83803);
    text-align: center;
    padding: 8px;
    background: rgba(200, 56, 3, 0.1);
    border: 1px solid rgba(200, 56, 3, 0.3);
    border-radius: 4px;
  }
</style>
