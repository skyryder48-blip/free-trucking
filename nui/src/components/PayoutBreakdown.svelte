<script>
  /**
   * PayoutBreakdown — Collapsible payout breakdown display.
   * Shows each payout component line-by-line with a total.
   * @prop {object} breakdown - Payout breakdown data
   * @prop {boolean} [startExpanded=false] - Start expanded
   */
  export let breakdown = {};
  export let startExpanded = false;

  let expanded = startExpanded;

  function toggle() {
    expanded = !expanded;
  }

  /**
   * Expected breakdown shape:
   * {
   *   baseRate: number,
   *   distance: number,
   *   basePayout: number,
   *   weightMultiplier: number,
   *   ownerOpBonus: number | null,
   *   timePerformance: number,
   *   complianceBonus: number,
   *   nightHaulPremium: number | null,
   *   surgeBonus: number | null,
   *   surgePercentage: number | null,
   *   totalEstimated: number,
   * }
   */

  $: lines = buildLines(breakdown);

  function buildLines(b) {
    if (!b) return [];
    const result = [];

    if (b.baseRate && b.distance) {
      result.push({
        label: `Base rate ($${formatNum(b.baseRate)}/mi x ${formatNum(b.distance)} mi)`,
        value: b.basePayout || b.baseRate * b.distance,
        type: 'base',
      });
    } else if (b.basePayout) {
      result.push({ label: 'Base payout', value: b.basePayout, type: 'base' });
    }

    if (b.weightMultiplier && b.weightMultiplier !== 1) {
      result.push({
        label: `Weight multiplier (x${formatNum(b.weightMultiplier)})`,
        value: null,
        type: 'modifier',
      });
    }

    if (b.ownerOpBonus) {
      result.push({ label: 'Owner-op bonus', value: b.ownerOpBonus, type: 'bonus' });
    }

    if (b.timePerformance) {
      result.push({ label: 'Est. time performance', value: b.timePerformance, type: 'bonus' });
    }

    if (b.complianceBonus) {
      result.push({ label: 'Compliance potential', value: b.complianceBonus, type: 'bonus' });
    }

    if (b.nightHaulPremium) {
      result.push({ label: 'Night haul premium', value: b.nightHaulPremium, type: 'bonus' });
    }

    if (b.surgeBonus) {
      const surgeLabel = b.surgePercentage
        ? `Surge bonus (+${b.surgePercentage}%)`
        : 'Surge bonus';
      result.push({ label: surgeLabel, value: b.surgeBonus, type: 'surge' });
    }

    return result;
  }

  function formatNum(n) {
    if (n == null) return '—';
    return Number(n).toLocaleString('en-US', {
      minimumFractionDigits: 0,
      maximumFractionDigits: 2,
    });
  }

  function formatDollar(n) {
    if (n == null) return '—';
    return '$' + Number(n).toLocaleString('en-US');
  }
</script>

<div class="payout-breakdown" class:expanded>
  <button class="payout-header" on:click={toggle}>
    <span class="payout-title">Payout Breakdown</span>
    <div class="payout-header-right">
      <span class="payout-total mono">{formatDollar(breakdown?.totalEstimated)}</span>
      <span class="payout-chevron">{expanded ? '\u25B2' : '\u25BC'}</span>
    </div>
  </button>

  {#if expanded}
    <div class="payout-body fade-in">
      {#each lines as line}
        <div class="payout-line" class:surge-line={line.type === 'surge'}>
          <span class="payout-line-label">{line.label}</span>
          {#if line.value != null}
            <span class="payout-line-value mono">{formatDollar(line.value)}</span>
          {/if}
        </div>
      {/each}
      <div class="payout-divider"></div>
      <div class="payout-line payout-total-line">
        <span class="payout-line-label">Total Estimated</span>
        <span class="payout-line-value payout-figure mono">{formatDollar(breakdown?.totalEstimated)}</span>
      </div>
    </div>
  {/if}
</div>

<style>
  .payout-breakdown {
    background: var(--navy-dark);
    border: 1px solid var(--border);
    border-radius: var(--radius-md);
    overflow: hidden;
  }

  .payout-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    width: 100%;
    padding: var(--spacing-sm) var(--spacing-md);
    background: none;
    border: none;
    color: var(--white);
    cursor: pointer;
    transition: background 0.15s ease;
  }

  .payout-header:hover {
    background: rgba(30, 58, 110, 0.2);
  }

  .payout-title {
    font-family: var(--font-heading);
    font-weight: 700;
    font-size: 12px;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    color: var(--muted);
  }

  .payout-header-right {
    display: flex;
    align-items: center;
    gap: var(--spacing-sm);
  }

  .payout-total {
    font-size: 14px;
    color: var(--success);
  }

  .payout-chevron {
    font-size: 10px;
    color: var(--muted);
  }

  .payout-body {
    padding: var(--spacing-sm) var(--spacing-md) var(--spacing-md);
    display: flex;
    flex-direction: column;
    gap: var(--spacing-xs);
  }

  .payout-line {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 2px 0;
  }

  .payout-line-label {
    font-size: 13px;
    color: var(--muted);
  }

  .payout-line-value {
    font-size: 13px;
    color: var(--white);
  }

  .surge-line .payout-line-label,
  .surge-line .payout-line-value {
    color: var(--orange);
  }

  .payout-divider {
    width: 100%;
    height: 1px;
    background: var(--border);
    margin: var(--spacing-xs) 0;
  }

  .payout-total-line .payout-line-label {
    color: var(--white);
    font-family: var(--font-heading);
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    font-size: 12px;
  }

  .payout-figure {
    font-size: 16px;
    color: var(--success);
    font-weight: 500;
  }
</style>
