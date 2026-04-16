# New Stuff Indicators (Inbox & My Work)

Client-only “since last visit” cues for the **Inbox** and **My Work** home tabs: bottom-nav dots and per-row/per-card markers, driven by local Drift cursors and max activity timestamps from successful fetches.

## What it does

- **Bottom navigation** — A small dot on the Inbox or My Work destination when there is activity **newer** than the stored last-seen cursor **and** the user is **not** currently on that tab.
- **Inbox rows** — Pills distinguish **New** (forward / inbox activity after last visit) vs **Updated** (beacon content changed after last visit without newer forward activity than the cursor). The tab dot’s max-activity snapshot uses `max(latest_forward_at, beacon.updated_at)` per row so beacon-only edits still count.
- **My Work cards** — Pills distinguish **New** (beacon `created_at` after last visit) vs **Updated** (edited after last visit but created on or before it). The nav dot still uses the max of `beacon.updated_at` across cards.

There is **no** server API dedicated to this feature: cursors are **per account**, stored in `Settings` as epoch milliseconds (`valueInt`).

## Architecture

```
[HomeScreen]
  ├─ HomeBottomNavListener → NewStuffCubit.setActiveHomeTabIndex (sync with TabsRouter)
  └─ onDestinationSelected → NewStuffCubit.markInboxTabSeen / markMyWorkTabSeen

[NewStuffCubit] (@singleton)
  ├─ Hydrates last-seen from SettingsRepository on auth / account change
  ├─ In-memory max activity: maxInboxActivityMs / maxMyWorkActivityMs (from cubits)
  └─ Persists last-seen only when the user marks the tab seen (or pending-after-first-fetch path)

[InboxCubit] ──reportInboxActivity(max latestForwardAt)──▶ NewStuffCubit
[MyWorkCubit] ──reportMyWorkActivity(max beacon.updatedAt)──▶ NewStuffCubit
```

### Key files

| Layer | File |
|---|---|
| State & cubit | `packages/client/lib/features/home/ui/bloc/new_stuff_cubit.dart`, `new_stuff_state.dart` |
| Settings keys | `packages/client/lib/features/settings/data/repository/settings_repository.dart` (`newStuff:inbox:<accountId>`, `newStuff:myWork:<accountId>`) |
| Tab sync | `packages/client/lib/features/home/ui/widget/home_bottom_nav_listener.dart` |
| Mark on tab entry | `packages/client/lib/features/home/ui/screen/home_screen.dart` |
| Nav dots | `packages/client/lib/features/home/ui/widget/inbox_navbar_item.dart`, `my_work_navbar_item.dart` |
| Activity reporting | `packages/client/lib/features/inbox/ui/bloc/inbox_cubit.dart`, `packages/client/lib/features/my_work/ui/bloc/my_work_cubit.dart` |
| Row/card UI | `packages/client/lib/features/inbox/ui/widget/inbox_item_tile.dart`, `packages/client/lib/features/my_work/ui/widget/my_work_cards.dart` |

## Design notes

- **Null last-seen** — No dot and no row/card “new” baseline until the user has a persisted last-seen for that tab (hydrated from Drift or written after the first successful mark path).
- **Drift writes** — Advancing last-seen is **not** tied to every background refetch; repeated `report*Activity` updates in-memory max only. Persistence happens when the user **enters** the tab (`mark*TabSeen`) or the **pending-after-fetch** path runs on first visit when max was unknown at tap time.
- **Default Inbox tab** — `markInboxTabSeen` runs from bottom-nav **selection changes**. If the user stays on Inbox for the whole session and never switches tabs, Inbox last-seen may not advance for that session; switching away and back to Inbox updates it. My Work is usually entered by tapping tab 1, which triggers the mark path.
