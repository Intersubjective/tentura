/**
 * Invite landing shared-request card helpers.
 * Collapsed body uses the server `snippet` (≤140 chars); expand needs full
 * `description` from the same preview JSON.
 */

/**
 * Whether the beacon card should show a Show more / Show less control.
 * @param {string|null|undefined} snippet
 * @param {string|null|undefined} description
 */
export function needsExpand(snippet, description) {
  const full = String(description ?? '').trim();
  const short = String(snippet ?? '').trim();
  if (!full || !short) return false;
  return full.length > short.length || full !== short;
}

/**
 * Body text for the collapsed vs expanded card state.
 * @param {{ snippet?: string|null, description?: string|null }} beacon
 * @param {boolean} expanded
 */
export function beaconBodyText(beacon, expanded) {
  const snippet = String(beacon?.snippet ?? '').trim();
  const description = String(beacon?.description ?? '').trim();
  if (expanded && description) return description;
  if (snippet) return snippet;
  return description;
}
