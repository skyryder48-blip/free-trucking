<script>
  /**
   * StatusBadge — Reusable status indicator badge.
   * @prop {string} status - Status key (sealed, broken, active, expired, not_applied, warning, critical, inactive)
   * @prop {string} [label] - Optional override label text
   */
  export let status = 'inactive';
  export let label = '';

  const statusConfig = {
    sealed:       { text: 'Sealed',      cssClass: 'status-sealed' },
    broken:       { text: 'Broken',      cssClass: 'status-broken' },
    active:       { text: 'Active',      cssClass: 'status-active' },
    expired:      { text: 'Expired',     cssClass: 'status-expired' },
    not_applied:  { text: 'Not Applied', cssClass: 'status-not-applied' },
    warning:      { text: 'Warning',     cssClass: 'status-warning' },
    critical:     { text: 'Critical',    cssClass: 'status-critical' },
    inactive:     { text: 'Inactive',    cssClass: 'status-inactive' },
    rejected:     { text: 'Rejected',    cssClass: 'status-rejected' },
    suspended:    { text: 'Suspended',   cssClass: 'status-suspended' },
    in_transit:   { text: 'In Transit',  cssClass: 'status-active' },
    at_origin:    { text: 'At Origin',   cssClass: 'status-active' },
    at_destination: { text: 'At Dest',   cssClass: 'status-active' },
    completed:    { text: 'Completed',   cssClass: 'status-sealed' },
    distress_active: { text: 'Distress', cssClass: 'status-critical' },
  };

  $: config = statusConfig[status] || statusConfig.inactive;
  $: displayText = label || config.text;
</script>

<span class="status-badge {config.cssClass}">
  {displayText}
</span>

<style>
  .status-badge {
    display: inline-flex;
    align-items: center;
    padding: 2px 8px;
    border-radius: var(--radius-sm);
    font-family: var(--font-heading);
    font-weight: 700;
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }

  .status-sealed,
  .status-active {
    background: rgba(45, 122, 62, 0.2);
    color: var(--success);
    border: 1px solid var(--success);
  }

  .status-broken,
  .status-warning {
    background: rgba(200, 123, 3, 0.2);
    color: var(--warning);
    border: 1px solid var(--warning);
  }

  .status-expired,
  .status-rejected,
  .status-critical,
  .status-suspended {
    background: rgba(200, 56, 3, 0.2);
    color: var(--orange);
    border: 1px solid var(--orange);
  }

  .status-not-applied,
  .status-inactive {
    background: rgba(58, 74, 92, 0.3);
    color: var(--muted);
    border: 1px solid var(--disabled);
  }
</style>
