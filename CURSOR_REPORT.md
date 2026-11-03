# CURSOR_REPORT — #545 loading pattern rollout

## Coverage map

| Unit | Item | Status | Commit / evidence |
|------|------|--------|-------------------|
| 1 | `TenturaFirstLoadGate` + 150ms / 2.5s / error / latch contract | done | `TenturaCircularProgress`, gate docs, `test/ui/widget/first_load_gate_test.dart` |
| 2 | Request view gate (beacon + status + offers) + loading shell (no title/linear bar during gate) | done | `beacon_view_screen.dart`, `request_declined_forwards_first_load_test.dart` |
| 3 | Activity list page 1 gate | n/a | Already on `main` (`tentura-mezc.25`); unit 3 commit touches Activity load-more progress only |
| 4 | My Work cards gate | n/a | Already on `main` (`tentura-mezc.26`); unit 4 commit migrates inline progress widget |
| 5 | People list gate | n/a | Already on `main` (`tentura-mezc.27`); empty unit commit documents verification |
| 6 | Remove replaced per-screen spinners (rolled-out surfaces) | done | Child-requests reserve slot, room/my_work/activity use `TenturaCircularProgress` |
| 7 | `no_raw_circular_progress_in_features` lint + baseline | done | `packages/tentura_lints`, `scripts/check-custom-lints.sh`, baseline 73 |

QA r10 desktop **split-layout jump before reveal** remains **Part of #545** (needs deferred split layout / room-ready gate beyond this PR’s minimal header shell).

## Sibling matrix

| Row | Coverage |
|-----|----------|
| input | Gate tests use delayed repos / harness (`request_declined_forwards_first_load_test.dart`, existing Activity/My Work/People gate tests on main) |
| surface | Phone 375×667 RU in declined-forwards phone test; desktop 1365 in declined-forwards matrix |
| role | Author/helper variants in declined-forwards suite |
| state | Cold load, timeout, refresh paths in existing gate tests (main) |
| freshness | Real-path declined-forwards wire test (existing) |
| width | Phone + desktop/tablet in declined-forwards parametrized tests |
| locale | RU phone case in declined-forwards; EN desktop |

## Tests run

```text
scripts/run_tests.sh client-gates                          → OK
flutter test test/ui/widget/first_load_gate_test.dart      → OK (via client-gates / local)
flutter test test/features/beacon_view/request_declined_forwards_first_load_test.dart → OK
packages/tentura_lints: dart test                           → OK
scripts/check-custom-lints.sh packages/client                → OK (73/73)
bash scripts/check-analyze-baseline.sh packages/client     → OK (1964)
```
