# CURSOR_REPORT — Issue #248

## Commits

| Unit | Commit | Message |
|------|--------|---------|
| 1 | `8dbfd0669` | Post room card + Replies + scroll collapse |
| 2 | `431f9e279` | Composer card preview + recipients header |
| 3 | `c79140288` | Lifetime on Posts list + Field (+ inbox widget test) |

## Coverage map

### Unit 1 — Post room card

| Acceptance item | Status | Evidence |
|-----------------|--------|----------|
| Expanded card: avatar, name, time, lifetime | done | `PostRootPinCard` + `postLifetimeLineForDeadline`; test hourglass in `issue_248_post_room_card_test.dart` |
| Full root text + attachments + #667 lines | done | Reuses `RoomMessageTextBody`, attachment widgets |
| Meta line people · replies · share/invite-only | done | `postCardMetaCanShare` / `postCardMetaInviteOnly` l10n |
| Collapse on scroll; tap strip expands + scroll top | done | `beacon_room_body.dart` + `post_view_screen_test.dart` pinned root strip |
| No duplicate root bubble | done | Root filtered from list; tests assert ListView has no root |
| «Replies» divider + «Reply…» composer | done | `issue_248_post_room_card_test.dart` 375×667 RU |
| Archived marker + read-only replies | done | Existing archived/read-only paths unchanged; card uses archived marker |
| Request rooms unchanged | done | Gated on `RoomCapabilities.post()` |
| EN + RU | done | `app_en.arb` / `app_ru.arb` |
| Reduced motion | done | `MediaQuery.disableAnimations` respected in collapse animation |

### Unit 2 — Composer preview

| Acceptance item | Status | Evidence |
|-----------------|--------|----------|
| Step 1 card-styled field (same widget tokens) | done | `PostRootPinCard.editorShell` in `post_create_screen.dart` |
| Helper «Everyone… lives up to {lifetime}» | done | `postCreateReplyLifetimeHint` EN/RU |
| Step 2 `ForwardRecipientPicker.header` collapsed draft | done | `PostRootDraftPreviewCard`; tap returns to step 1 |
| Other picker callers unaffected | done | Optional `header` parameter |
| Step order / lifetime / forwarding unchanged | done | `post_create_screen_test.dart` (36 tests pass) |

### Unit 3 — Lifetime everywhere

| Acceptance item | Status | Evidence |
|-----------------|--------|----------|
| Posts list row visible ⏳ lifetime | done | `PostLifetimeTicker` on `post_conversation_row.dart`; `issue_248_post_row_lifetime_test.dart` 375×667 RU |
| Field preview sheet under excerpt | done | `constellation_post_preview_sheet.dart` |
| Map node second muted line | done | `constellation_viewport_overlay.dart` |
| Field list view after excerpt | done | `constellation_text_view.dart` |
| Tick ≥1 min via shared clock | done | `PostLifetimeTicker` → `RelativeTimestampTicker`; map overlay listens to `RelativeTimeClock` |
| No new formatting helper | done | `postRemainingVisibleLabel` / `postLifetimeLineForDeadline` only |

## Sibling matrix

| Row | Unit 1 | Unit 2 | Unit 3 |
|-----|--------|--------|--------|
| **input** | Open Post room (wire harness / screen test) | Draft text + lifetime segment | `PostSummary.expiresAt` / beacon expires |
| **surface** | Post room | Post create steps 1–2 | Inbox row, Field sheet/map/list |
| **role** | Participant | Author | Viewer |
| **state** | Open + archived | Draft | Live + archived marker |
| **freshness** | `postNow` injected in harness | Lifetime segment label | Ticker minute refresh |
| **width** | 375×667 RU room test | n/a: existing create tests (desktop scope) | 375×667 RU row test |
| **locale** | RU room + EN strip tests in `post_view_screen_test.dart` | EN/RU ARB | RU row test |

**Real-path:** `post_view_screen_test.dart` exercises Post view → room body with repository-backed `_pumpPost` graph (participants, messages, forward edges). Domain wire coverage remains in `post_lifecycle_repository_test.dart` (`withRemoteWire`).

## Tests run (exact commands)

```bash
bash scripts/check-analyze-baseline.sh packages/client
# → 1963 issues (≤ baseline 1964), OK

scripts/run_tests.sh client-gates
# → exit 0 (~1 min)

cd packages/client && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- \
  flutter test test/features/beacon_threads/issue_248_post_room_card_test.dart \
  test/features/post_view/post_view_screen_test.dart --name 'pinned root'
# → 11 passed

cd packages/client && ../../scripts/run_with_test_cleanup.sh --timeout 25m -- \
  flutter test test/features/beacon_create/post_create_screen_test.dart \
  test/features/inbox/issue_248_post_row_lifetime_test.dart \
  test/features/post_view/post_remaining_label_test.dart
# → all passed

scripts/run_tests.sh client-affected
# → started job 1103-132551-88761 (see wait output when complete)
```

## Reuse contract

Single evolved widget: `post_root_pin_card.dart` (`PostRootPinCard`, `PostRootDraftPreviewCard`). No parallel post card, chat body, or picker. `_PinnedPostRootRow` removed.

## Left

None — all three units landed.
