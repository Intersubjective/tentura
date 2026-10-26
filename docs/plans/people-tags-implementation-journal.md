# People tags — implementation journal

## R1 — Phase 1 release

G1 (server Field snapshot at 400): deferred to the end of the queue by owner decision 2026-10-24 — not a release blocker; tracked by manual bead tentura-x56h.11.

G2 is also deferred to the end of the queue (manual bead tentura-x56h.50).
If performance is bad, the Field cap will be lowered. No performance measurements
are claimed by this entry.

Client 7.54.0 enables private people tags and Field membership V2, superseding
D9's Request-holder pruning. The server peer cap is 400; the client render cap
remains 120 until semantic zoom ships. The web cache-buster matches the version.
