<script>
  /**
   * TierBadge — Displays a cargo tier label (T0-T3) with color coding.
   * @prop {number} tier - Tier number (0-3)
   * @prop {string} [size='default'] - 'small' or 'default'
   */
  export let tier = 0;
  export let size = 'default';

  const tierLabels = {
    0: 'T0',
    1: 'T1',
    2: 'T2',
    3: 'T3',
  };

  const tierNames = {
    0: 'Entry',
    1: 'Standard',
    2: 'Specialized',
    3: 'Premium',
  };

  $: label = tierLabels[tier] || 'T0';
  $: name = tierNames[tier] || 'Entry';
  $: badgeClass = `badge badge-t${tier}`;
</script>

<span class={badgeClass} class:badge-small={size === 'small'} title={name}>
  {label}
</span>

<style>
  .badge {
    display: inline-flex;
    align-items: center;
    padding: 2px 8px;
    border-radius: var(--radius-sm);
    font-family: var(--font-heading);
    font-weight: 700;
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    line-height: 1.4;
  }

  .badge-small {
    padding: 1px 6px;
    font-size: 10px;
  }

  .badge-t0 {
    background: var(--disabled);
    color: var(--muted);
  }

  .badge-t1 {
    background: var(--border);
    color: var(--white);
  }

  .badge-t2 {
    background: var(--orange-dim);
    color: var(--white);
  }

  .badge-t3 {
    background: var(--orange);
    color: var(--white);
  }
</style>
