# Fact history pin event evidence

Evidence for `tentura-s689`. The deployed client requested `BeaconFactCardRevisions` from `/api/v2/graphql` for fact `F58ee87ae051e` on Request `Beec80fe70075` as the QA account. The Playwright captures at 1280×800 and 375×667 yielded the same response and both matched the fixture byte for byte after replacing only the actor ID and name. The capture used read-only requests. [Captured response](../../packages/client/test/features/beacon_threads/fixtures/created_fact_with_pin_event.json)

| Entry key | Entry | Kind | Seq | Body | Null fields |
| --- | --- | --- | --- | --- | --- |
| `r0000000001` | Revision | 0, created | 1 | `A 1293 F-mixQ`, 13 characters, neither empty nor whitespace-only | `restoredFromSeq`, `visibilityFrom`, `visibilityTo` |
| `e1794814699343511` | Event | 2, pinned | `null` | `null`, no body length or empty or whitespace-only string | `seq`, `factText`, `restoredFromSeq`, `visibilityFrom`, `visibilityTo` |

Both rows have `createdAt` equal to `2026-11-16T07:38:19.343511Z`. The page has a null `nextCursor`, and the fact list reports a null `originBeaconKind`.

The Playwright console recorded no messages while the history was open at either size. Both runs showed the revision body followed by the pin actor alone. The repository and cubit delivered both rows in order and the widget tests found no build or layout exception. A pin event has no revision body. The renderer's fallback displayed only the actor name for kind 2, leaving out the event label. The fix uses the existing localized “Fact pinned” label beneath the actor and keeps the bounded shrink-wrapped layout from `gmlw`. [History renderer](../../packages/client/lib/features/beacon_threads/ui/widget/fact_history_sheet.dart)

With the sheet file from `b9873b862`, the fixture-driven command exited 1 with all three cases failing at `expect(visibleBelowActor(), isTrue, ...)`. The assertion reported the following. [Regression test](../../packages/client/test/features/beacon_threads/fact_history_pin_event_test.dart#L223)

- The second row ends at its actor line. Content below that line must be fully visible after mouse wheel.
- The second row ends at its actor line. Content below that line must be fully visible after mouse drag.
- The second row ends at its actor line. Content below that line must be fully visible after touch drag.

After restoring the fixed sheet, all 52 tests passed across `fact_history_pin_event_test.dart`, `fact_history_sheet_layout_test.dart`, `fact_history_sheet_test.dart`, `fact_history_cubit_test.dart`, and `fact_history_highlight_test.dart`.
