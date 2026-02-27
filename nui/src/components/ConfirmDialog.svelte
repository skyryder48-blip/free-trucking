<script>
  import { createEventDispatcher } from 'svelte';

  export let visible = false;
  export let title = 'Confirm';
  export let message = 'Are you sure?';
  export let confirmText = 'Confirm';
  export let cancelText = 'Cancel';
  export let confirmStyle = 'primary'; // 'primary' | 'danger'

  const dispatch = createEventDispatcher();

  function handleConfirm() {
    dispatch('confirm');
  }

  function handleCancel() {
    dispatch('cancel');
  }

  function handleOverlayClick(e) {
    if (e.target === e.currentTarget) {
      handleCancel();
    }
  }
</script>

{#if visible}
  <div class="dialog-overlay" on:click={handleOverlayClick}>
    <div class="dialog-box">
      <h2 class="dialog-title">{title}</h2>
      <p class="dialog-message">{message}</p>
      <div class="dialog-actions">
        <button class="btn-cancel" on:click={handleCancel}>
          {cancelText}
        </button>
        <button
          class="btn-confirm"
          class:danger={confirmStyle === 'danger'}
          on:click={handleConfirm}
        >
          {confirmText}
        </button>
      </div>
    </div>
  </div>
{/if}

<style>
  .dialog-overlay {
    position: fixed;
    top: 0;
    left: 0;
    width: 100%;
    height: 100%;
    background: rgba(5, 18, 41, 0.85);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 9999;
  }

  .dialog-box {
    background: var(--navy, #0B1F45);
    border: 2px solid var(--border, #1E3A6E);
    border-radius: 6px;
    padding: 28px 32px 24px;
    min-width: 340px;
    max-width: 440px;
    box-shadow: 0 12px 40px rgba(0, 0, 0, 0.6);
  }

  .dialog-title {
    font-family: 'Barlow Condensed', sans-serif;
    font-weight: 700;
    font-size: 20px;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    color: var(--white, #FFFFFF);
    margin: 0 0 12px 0;
  }

  .dialog-message {
    font-family: 'Inter', sans-serif;
    font-size: 15px;
    color: var(--muted, #A8B4C8);
    line-height: 1.5;
    margin: 0 0 24px 0;
  }

  .dialog-actions {
    display: flex;
    gap: 12px;
    justify-content: flex-end;
  }

  .btn-cancel {
    font-family: 'Barlow Condensed', sans-serif;
    font-weight: 700;
    font-size: 14px;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    background: var(--navy-mid, #132E5C);
    color: var(--muted, #A8B4C8);
    border: 1px solid var(--border, #1E3A6E);
    border-radius: 4px;
    padding: 10px 22px;
    cursor: pointer;
    transition: background 0.15s, color 0.15s;
  }

  .btn-cancel:hover {
    background: var(--border, #1E3A6E);
    color: var(--white, #FFFFFF);
  }

  .btn-confirm {
    font-family: 'Barlow Condensed', sans-serif;
    font-weight: 700;
    font-size: 14px;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    background: var(--orange, #C83803);
    color: var(--white, #FFFFFF);
    border: 1px solid transparent;
    border-radius: 4px;
    padding: 10px 22px;
    cursor: pointer;
    transition: background 0.15s;
  }

  .btn-confirm:hover {
    background: var(--orange-dim, #8A2702);
  }

  .btn-confirm.danger {
    background: #8B0000;
  }

  .btn-confirm.danger:hover {
    background: #6B0000;
  }
</style>
