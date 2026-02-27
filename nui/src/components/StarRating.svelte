<script>
  /** Rating value from 1-5 */
  export let rating = 0;
  /** Size of each star in pixels */
  export let size = 20;
  /** Whether to show the numeric label */
  export let showLabel = true;

  $: stars = Array.from({ length: 5 }, (_, i) => {
    const starValue = i + 1;
    if (rating >= starValue) return 'full';
    if (rating >= starValue - 0.5) return 'half';
    return 'empty';
  });

  $: qualityLabel = getQualityLabel(rating);

  function getQualityLabel(r) {
    if (r >= 4.5) return 'Excellent';
    if (r >= 3.5) return 'Good';
    if (r >= 2.5) return 'Fair';
    if (r >= 1.5) return 'Poor';
    if (r >= 0.5) return 'Critical';
    return 'N/A';
  }

  $: qualityClass = getQualityClass(rating);

  function getQualityClass(r) {
    if (r >= 4.5) return 'excellent';
    if (r >= 3.5) return 'good';
    if (r >= 2.5) return 'fair';
    if (r >= 1.5) return 'poor';
    return 'critical';
  }
</script>

<div class="star-rating" class:compact={!showLabel}>
  <div class="stars" style="--star-size: {size}px">
    {#each stars as state}
      <span class="star" class:full={state === 'full'} class:half={state === 'half'} class:empty={state === 'empty'}>
        {#if state === 'full'}
          <svg width={size} height={size} viewBox="0 0 24 24" fill="currentColor">
            <path d="M12 2l3.09 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77l-6.18 3.25L7 14.14 2 9.27l6.91-1.01L12 2z"/>
          </svg>
        {:else if state === 'half'}
          <svg width={size} height={size} viewBox="0 0 24 24">
            <defs>
              <linearGradient id="halfGrad">
                <stop offset="50%" stop-color="currentColor"/>
                <stop offset="50%" stop-color="var(--disabled, #3A4A5C)"/>
              </linearGradient>
            </defs>
            <path d="M12 2l3.09 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77l-6.18 3.25L7 14.14 2 9.27l6.91-1.01L12 2z" fill="url(#halfGrad)"/>
          </svg>
        {:else}
          <svg width={size} height={size} viewBox="0 0 24 24" fill="var(--disabled, #3A4A5C)">
            <path d="M12 2l3.09 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77l-6.18 3.25L7 14.14 2 9.27l6.91-1.01L12 2z"/>
          </svg>
        {/if}
      </span>
    {/each}
  </div>
  {#if showLabel}
    <span class="rating-label {qualityClass}">
      {rating > 0 ? rating.toFixed(1) : '--'} / 5.0
      <span class="quality-text">{qualityLabel}</span>
    </span>
  {/if}
</div>

<style>
  .star-rating {
    display: flex;
    align-items: center;
    gap: 10px;
  }

  .star-rating.compact {
    gap: 4px;
  }

  .stars {
    display: flex;
    gap: 2px;
    align-items: center;
  }

  .star {
    display: flex;
    align-items: center;
    line-height: 1;
  }

  .star.full {
    color: var(--warning, #C87B03);
  }

  .star.half {
    color: var(--warning, #C87B03);
  }

  .rating-label {
    font-family: 'JetBrains Mono', monospace;
    font-size: 13px;
    color: var(--muted, #A8B4C8);
    display: flex;
    align-items: center;
    gap: 8px;
  }

  .quality-text {
    font-family: 'Barlow Condensed', sans-serif;
    font-weight: 700;
    font-size: 12px;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    padding: 2px 8px;
    border-radius: 3px;
  }

  .excellent .quality-text {
    color: var(--success, #2D7A3E);
    background: rgba(45, 122, 62, 0.15);
  }

  .good .quality-text {
    color: #4CAF50;
    background: rgba(76, 175, 80, 0.15);
  }

  .fair .quality-text {
    color: var(--warning, #C87B03);
    background: rgba(200, 123, 3, 0.15);
  }

  .poor .quality-text {
    color: var(--orange, #C83803);
    background: rgba(200, 56, 3, 0.15);
  }

  .critical .quality-text {
    color: #D32F2F;
    background: rgba(211, 47, 47, 0.15);
  }
</style>
