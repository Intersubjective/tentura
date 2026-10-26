# People tags — implementation journal

## R1 — Phase 1 release

G1 (server Field snapshot at 400): deferred to the end of the queue by owner decision 2026-10-24 — not a release blocker; tracked by manual bead tentura-x56h.11.

G2 is also deferred to the end of the queue (manual bead tentura-x56h.50).
If performance is bad, the Field cap will be lowered. No performance measurements
are claimed by this entry.

Client 7.54.0 enables private people tags and Field membership V2, superseding
D9's Request-holder pruning. The server peer cap is 400; the client render cap
remains 120 until semantic zoom ships. The web cache-buster matches the version.

## R3 — Phase 3 release

Client 7.56.0 enables `kFieldSemanticZoomEnabled` and the 400-person render
budget. Close / district / overview share one zoom-level controller, replacing
the legacy bare cutoff. This activates phase-3 community placement, minimap,
cluster actions and tag magnets. The tracked web cache-buster is 7.56.0.

The client-only release preserves server compatibility and does not require a
minimum-client-version increase. G2 remains deferred by the owner decision
above; no wasm performance result is claimed here.

Release verification covers the zoom defaults and presentation wiring, the
wrapped client suite, analyzer baseline and custom lints. Verification results
are recorded by the task runner. The release commit body must include
`Closes #595` and `Closes #640` (git is owned by Alloy).
