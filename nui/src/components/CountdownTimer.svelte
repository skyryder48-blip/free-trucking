<script>
  import { onMount, onDestroy } from 'svelte';

  /**
   * CountdownTimer — Displays a countdown with warning/critical color states.
   * @prop {number} targetTime - Unix timestamp (seconds) when the timer expires
   * @prop {number} [warningMinutes=15] - Minutes remaining to trigger warning state
   * @prop {number} [criticalMinutes=5] - Minutes remaining to trigger critical state
   * @prop {boolean} [large=false] - Large display variant
   * @prop {boolean} [showLabel=true] - Show "Time Remaining" label
   */
  export let targetTime = 0;
  export let warningMinutes = 15;
  export let criticalMinutes = 5;
  export let large = false;
  export let showLabel = true;

  let remaining = 0;
  let interval;

  $: hours = Math.floor(remaining / 3600);
  $: minutes = Math.floor((remaining % 3600) / 60);
  $: seconds = remaining % 60;

  $: display = formatTime(hours, minutes, seconds);
  $: state = getState(remaining);

  function formatTime(h, m, s) {
    const pad = (n) => String(n).padStart(2, '0');
    if (h > 0) {
      return `${h}:${pad(m)}:${pad(s)}`;
    }
    return `${pad(m)}:${pad(s)}`;
  }

  function getState(rem) {
    if (rem <= 0) return 'expired';
    if (rem <= criticalMinutes * 60) return 'critical';
    if (rem <= warningMinutes * 60) return 'warning';
    return 'normal';
  }

  function tick() {
    const now = Math.floor(Date.now() / 1000);
    remaining = Math.max(0, targetTime - now);
  }

  onMount(() => {
    tick();
    interval = setInterval(tick, 1000);
  });

  onDestroy(() => {
    if (interval) clearInterval(interval);
  });
</script>

<div class="countdown" class:countdown-large={large} class:state-warning={state === 'warning'} class:state-critical={state === 'critical'} class:state-expired={state === 'expired'}>
  {#if showLabel}
    <span class="countdown-label">Time Remaining</span>
  {/if}
  <span class="countdown-value mono">
    {display}
  </span>
  {#if state === 'expired'}
    <span class="countdown-expired-label">Expired</span>
  {/if}
</div>

<style>
  .countdown {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 2px;
  }

  .countdown-label {
    font-size: 10px;
    color: var(--muted);
    text-transform: uppercase;
    letter-spacing: 0.04em;
    font-family: var(--font-heading);
    font-weight: 700;
  }

  .countdown-value {
    font-size: 18px;
    font-weight: 500;
    color: var(--white);
    transition: color 0.3s ease;
  }

  .countdown-large .countdown-value {
    font-size: 28px;
  }

  .state-warning .countdown-value {
    color: var(--warning);
  }

  .state-critical .countdown-value {
    color: var(--orange);
    animation: criticalPulse 1s ease-in-out infinite;
  }

  .state-expired .countdown-value {
    color: var(--orange);
    opacity: 0.7;
  }

  .countdown-expired-label {
    font-size: 10px;
    color: var(--orange);
    font-family: var(--font-heading);
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }

  @keyframes criticalPulse {
    0%, 100% { opacity: 1; }
    50% { opacity: 0.6; }
  }
</style>
