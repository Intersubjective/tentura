# Known issues

Tracked product and test gaps that are understood but not yet fixed.

Last updated: 2026-08-16 (integration suite after `8bd40b51e`).

---

## Web integration tests (`packages/client/integration_test`)

Run: `./scripts/run_client_integration_web_local.sh`

**Status: 7/10 passing.**

| Test | Status |
|------|--------|
| `request_lifecycle_create_forward_inbox_test.dart` | pass |
| `request_lifecycle_close_review_test.dart` | pass |
| `request_lifecycle_review_trust_control_test.dart` | pass |
| `tab_attention_forced_background_test.dart` | pass |
| `request_lifecycle_beacon_cover_test.dart` | pass |
| `request_lifecycle_closed_to_archive_test.dart` | pass |
| `witness_admission_forward_band_test.dart` | pass |
| `request_lifecycle_offer_admit_chat_test.dart` | **fail** |
| `request_threads_navigation_test.dart` | **fail** |
| `graph_navigation_hops_test.dart` | **fail** |

### `request_lifecycle_offer_admit_chat_test.dart`

**Symptom:** `TimeoutException` in `enterThreadsIfNeeded()` (`support/e2e_test_helpers.dart`).

**What happens:** The helper creates the first coordination item (“Need answer”) successfully, then the UI stays in **General thread chat** (room message input visible). The harness cannot return to the **threads list** where Ask / Commitment launcher buttons live, so the second `createCoordinationItem` (Commitment / Blocker) never runs.

**Likely cause:** After item creation the app opens or keeps a thread detail / General chat view. Existing helpers (`popToThreadsListIfNeeded`, “Back to Threads”, Details→Threads tab switching, scroll) do not reliably collapse that view in the My Work embedded layout on web.

**Workarounds tried (partial):** Reordered test to create coordination items before sending a room message; added back-navigation and scroll helpers — first item still strands the harness before subsequent items.

---

### `request_threads_navigation_test.dart`

**Symptom:** `Multiple exceptions (4600+)` during the test run.

**What happens:** The test exercises thread deep links, browser `history.back()` / `forward()`, and viewport resize (390×844 → 1280×900). Flutter’s test framework aborts once render exceptions accumulate; the log does not surface a single root exception.

**Likely cause:** Layout or navigation instability when switching compact ↔ expanded layouts, thread routing, or browser history — possibly a product bug, not only a harness gap.

**Note:** Failure mode is distinct from simple `pumpUntil` timeouts; needs first-exception capture or a headed repro to isolate.

---

### `graph_navigation_hops_test.dart`

**Symptom:** `TimeoutException` in `pumpUntil()` on `/home/profile/graph/...`. Screen dump shows “Trust graph” with ego (ME) and subscribed helper (IH) visible.

**What happens:** After `openConnectionsGraph` and `expandEgoNeighbourhood`, the test focuses the helper and waits for the **Expand** control (`TestIds.graphExpand` via `expandFocusedGraphNode()`). That wait times out.

**Likely cause:** Either `selectGraphNeighbor()` taps helper **label text** without setting `GraphCubit` focus on web (Expand is focus-gated), or MeritRank / `userSubscribe` did not produce an expandable neighbourhood so Expand never appears.

**Note:** Graph shell loads (reset control and nodes visible); hop/expand step does not complete.

---

## Recently fixed integration failures (for context)

These failed before harness + beacon-create fixes in `8bd40b51e` and now pass:

| Area | Cause | Fix |
|------|--------|-----|
| Create / forward flows | Web `enterText` did not sync `BeaconCreateCubit`; forward publish stayed disabled | `Form.save()`, `onSaved`, `syncBeaconCreateDraftFields`, wait for enabled forward submit |
| Uncovered forward note | “Send without a shared note” sheet blocked send | `confirmUncoveredForwardNoteIfPresent()` |
| Close-after-review | HUD shows “Close now” vs My Work “Close request”; Archive CTA on list only | `triggerCloseNow()`, `showMyWorkList()` |
