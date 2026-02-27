<script>
  /**
   * ProgressRing — Circular progress indicator for integrity, temperature, etc.
   * @prop {number} value - Current value (0-100)
   * @prop {number} [max=100] - Maximum value
   * @prop {number} [size=64] - Ring diameter in pixels
   * @prop {number} [strokeWidth=5] - Ring stroke width
   * @prop {string} [label=''] - Center label text
   * @prop {'default' | 'integrity' | 'temperature'} [variant='default'] - Color behavior
   * @prop {number} [warningThreshold=60] - Below this = warning color
   * @prop {number} [criticalThreshold=40] - Below this = critical color
   */
  export let value = 100;
  export let max = 100;
  export let size = 64;
  export let strokeWidth = 5;
  export let label = '';
  export let variant = 'default';
  export let warningThreshold = 60;
  export let criticalThreshold = 40;

  $: percentage = Math.max(0, Math.min(100, (value / max) * 100));
  $: radius = (size - strokeWidth) / 2;
  $: circumference = 2 * Math.PI * radius;
  $: dashOffset = circumference - (percentage / 100) * circumference;

  $: strokeColor = getStrokeColor(percentage, variant);

  function getStrokeColor(pct, v) {
    if (v === 'integrity' || v === 'default') {
      if (pct <= criticalThreshold) return 'var(--orange)';
      if (pct <= warningThreshold) return 'var(--warning)';
      return 'var(--success)';
    }
    if (v === 'temperature') {
      // For temperature: green = in range, else warning/critical
      if (pct <= criticalThreshold) return 'var(--orange)';
      if (pct <= warningThreshold) return 'var(--warning)';
      return 'var(--success)';
    }
    return 'var(--orange)';
  }
</script>

<div class="progress-ring" style="width: {size}px; height: {size}px;">
  <svg width={size} height={size} viewBox="0 0 {size} {size}">
    <!-- Background ring -->
    <circle
      cx={size / 2}
      cy={size / 2}
      r={radius}
      fill="none"
      stroke="var(--navy-dark)"
      stroke-width={strokeWidth}
    />
    <!-- Progress arc -->
    <circle
      cx={size / 2}
      cy={size / 2}
      r={radius}
      fill="none"
      stroke={strokeColor}
      stroke-width={strokeWidth}
      stroke-linecap="round"
      stroke-dasharray={circumference}
      stroke-dashoffset={dashOffset}
      transform="rotate(-90 {size / 2} {size / 2})"
      class="progress-arc"
    />
  </svg>
  <div class="ring-content">
    <span class="ring-value mono" style="color: {strokeColor};">
      {Math.round(value)}
    </span>
    {#if label}
      <span class="ring-label">{label}</span>
    {/if}
  </div>
</div>

<style>
  .progress-ring {
    position: relative;
    display: inline-flex;
    align-items: center;
    justify-content: center;
  }

  .progress-ring svg {
    position: absolute;
    top: 0;
    left: 0;
  }

  .progress-arc {
    transition: stroke-dashoffset 0.4s ease, stroke 0.3s ease;
  }

  .ring-content {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    z-index: 1;
  }

  .ring-value {
    font-size: 16px;
    font-weight: 500;
    line-height: 1;
  }

  .ring-label {
    font-size: 9px;
    color: var(--muted);
    text-transform: uppercase;
    letter-spacing: 0.04em;
    margin-top: 2px;
  }
</style>
