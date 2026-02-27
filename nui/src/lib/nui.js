/**
 * NUI Communication Utilities
 * Handles messaging between Svelte UI and FiveM client script.
 */

/**
 * Check if running in a regular browser (dev mode) vs FiveM CEF.
 * @returns {boolean}
 */
export function isEnvBrowser() {
  return !(window.invokeNative);
}

/**
 * POST data to the FiveM NUI callback handler.
 * @param {string} eventName - The NUI callback event name
 * @param {object} [data={}] - Payload to send
 * @returns {Promise<any>} Response from the client script
 */
export async function fetchNUI(eventName, data = {}) {
  if (isEnvBrowser()) {
    // In browser dev mode, mock the response
    return {};
  }

  const url = `https://trucking/${eventName}`;
  const resp = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(data),
  });

  return await resp.json();
}

/**
 * Listen for NUI messages sent from the FiveM client via SendNUIMessage.
 * @param {function} callback - Called with (action, data) for each message
 * @returns {function} Cleanup function to remove the listener
 */
export function onNUIMessage(callback) {
  function handler(event) {
    const { action, ...data } = event.data;
    if (action) {
      callback(action, data);
    }
  }

  window.addEventListener('message', handler);

  return () => {
    window.removeEventListener('message', handler);
  };
}

/**
 * Send a close event back to the FiveM client to hide the NUI.
 */
export function closeNUI() {
  fetchNUI('close');
}
