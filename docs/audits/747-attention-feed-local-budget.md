# #747 local AttentionFeed investigation — 2026-11-02

Conclusion: no slow branch reproduced locally. Ship the regression guard, with no speculative SQL/index change. This does not establish why the single dev cancellation occurred; concurrent load on the two-vCPU host remains a hypothesis. No dev-host benchmark was run. No MeritRank code or shipped migration changed.

## Measurement

`attention_feed_statement_budget_pg_test.dart` passed all six tests through the real HTTP GraphQL resolver and PostgreSQL repository. Each cell below has 20 SQL samples, with nearest-rank p95 (sample 19). EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) runs the captured resolver statement with its original arguments. Measurements use disposable local clones, migrated to head; source databases remain untouched. Typical means median receipt-count account, except the explicitly seeded scale viewer. The scale fixture adds 128 Requests with 128 receipts each and a separate 32-receipt viewer.

Configured statement timeout: 30,000 ms. Effective fresh request deadline: 4,999 ms (5-second GraphQL request budget). Guard requires p95 < 2,499.5 ms. Worst measured p95: 169.717 ms, about 3.4% of the effective deadline. These are local serial measurements, not proof of dev performance under contention.

| Dataset | Population receipts | Viewer | Viewer receipts | Surface | p95 ms | EXPLAIN execution ms |
|---|---:|---|---:|---|---:|---:|
| tentura_devcopy | 735 | heavy: U6fca01549512 | 54 | activity | 26.132 | 19.268 |
| tentura_devcopy | 735 | heavy: U6fca01549512 | 54 | history | 16.034 | 5.946 |
| tentura_devcopy | 735 | typical: U02fbd7c8df4c | 2 | activity | 8.923 | 2.062 |
| tentura_devcopy | 735 | typical: U02fbd7c8df4c | 2 | history | 12.770 | 1.748 |
| tentura_perfsynth | 764 | heavy: U6fca01549512 | 54 | activity | 26.786 | 12.605 |
| tentura_perfsynth | 764 | heavy: U6fca01549512 | 54 | history | 10.937 | 5.816 |
| tentura_perfsynth with large receipt history | 17180 | heavy: Ufeedscaleheavy | 16384 | activity | 169.717 | 151.705 |
| tentura_perfsynth with large receipt history | 17180 | heavy: Ufeedscaleheavy | 16384 | history | 151.548 | 136.215 |
| tentura_perfsynth with large receipt history | 17180 | typical: Ufeedscaletypical | 32 | activity | 8.966 | 2.528 |
| tentura_perfsynth with large receipt history | 17180 | typical: Ufeedscaletypical | 32 | history | 6.559 | 1.802 |
| tentura_perfsynth | 764 | typical: U26aca0e369c7 | 2 | activity | 8.569 | 2.261 |
| tentura_perfsynth | 764 | typical: U26aca0e369c7 | 2 | history | 5.694 | 7.626 |

Full plans, buffers and individual samples are emitted under `packages/server/build/perf/attention_feed/*.json` on each run; this table preserves the verified run's numbers in tracked documentation.

## History review

Reviewed `git log` for attention_repository.dart and migrations since 2026-10-30, and the relevant repository diffs. nb7d.1 (216e94f77, October 28) changed request cancellation/telemetry. 23qd.1 (cace12048, October 30) changed the query and installed m0277. Subsequent #736 changes are relevant: 67ee4588e shares the post-lifecycle unread predicate between summary and unread page; 24d066a24 centralizes historyAttention and adds account-wide history summary to the separate surface summary query. Therefore “no relevant changes since nb7d.1” is not a factual conclusion. Current history and activity resolver SQL is measured here and comfortably within budget; no before/after performance regression is claimed or disproved for every historical revision. Later migration history includes chat/read-receipt/forwarding changes; no migration is proposed by this investigation.

## Coverage map and sibling matrix

| Issue item | Evidence / disposition |
|---|---|
| Reopened dev 57014 | Local real resolver measurements above; cause of the historical dev event remains unproven |
| Heavy and typical devcopy viewers | 735-receipt clone, both surfaces, 20 samples per viewer/surface |
| Scale dataset | 764-receipt perfsynth plus 17,180-receipt expanded clone, including 16,384-receipt viewer |
| EXPLAIN ANALYZE BUFFERS and timeout | Captured SQL plans and samples; table and budget above |
| Query changes since previous fix | History review above; relevant changes explicitly acknowledged |
| Regression guard | Real HTTP/resolver/PG test asserts p95 below half effective deadline; history IDs and pagination checked |
| Migration / before-after fix evidence | n/a: no measured slow branch, no production fix |
| MeritRank restriction | No MeritRank code changed; suite lock only prevents concurrent shared-service test interference |
| #747 communication / bead notes | This report supplies the conclusion and measurements for Alloy to attach; no external comment claimed posted |

Sibling decisions: surfaces = history and activity; roles = highest-receipt and median/seeded typical accounts; state = existing source data plus synthetic history, not exhaustive lifecycle-state coverage; network = local serial SQL, contention not reproduced. Mouse/touch/keyboard, phone width, EN/RU and browser freshness are n/a because no UI behaviour changes. The guard uses a fresh request for every sample.

## Verification

Alloy ran the targeted command after the final Dart edit: six tests passed (exit 0). `scripts/run_tests.sh server-gates` also passed (exit 0), without baseline changes. This is an investigation/guard addition, not a claimed behaviour fix; no fabricated red/green production change is needed.
