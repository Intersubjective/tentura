# V1 contradictions — resolution plan (overview)

Reference: **no** public feed, **no** likes/dislikes/**poll voting** as core beacon engagement, **no** normal comments; forwarding-first. **Canonical amendments:** [`product-decisions.md`](./product-decisions.md) (**chat kept**, **report kept**, **personal beacon list kept**, **AppBar chrome**, **beacon state enum**).

This document lists **code that still conflicts** with those goals. Items **withdrawn** as contradictions are listed at the end for traceability.

---

## 1. Likes, dislikes, and favorites on beacon tiles

**Conflict:** V1 omits likes/dislikes as social engagement on beacons.

**Current behavior**

- `beacon_tile_control.dart` — **`LikeControl`**, **`BeaconPinIconButton`**, **`RatingIndicator`**, **`PollButton`**, graph, share.
- `beacon_tile.dart` → **`My Work`** (`my_work_screen.dart`).

**Resolution**

- Remove or feature-flag **LikeControl** / **BeaconPinIconButton** (and **`LikeCubit`** / **`FavoritesCubit`** on `home_screen.dart` if unused elsewhere).
- **MR display** (`RatingIndicator` / scores) may stay as **read-only trust signal** — not “voting”; align naming with MeritRank.

**Open**

- Whether MR indicator appears on every tile or only detail/forward screens.

---

## 2. Graph access gated on voting (`myVote`)

**Conflict:** Graph is chain/reachability inspection; must not require thumbs up/down.

**Current behavior**

- `beacon_tile_control.dart` — graph disabled when `beacon.myVote < 0`.

**Resolution**

- Remove vote gate; use **visibility / can-view** from server or “user can open beacon” only.

---

## 3. Polls (beacon create + tile)

**Conflict:** Poll **voting** omitted for V1 beacon product.

**Current behavior**

- `beacon_create_screen.dart` — Poll tab; `beacon_tile_control.dart` — **`PollButton`**; `beacon.dart` — **`Polling?`**.

**Resolution**

- Remove Poll tab and tile surfacing; optional API rejection of new polls.

---

## 4. Boolean `enabled` vs lifecycle enum

**Conflict:** Code assumes **`enabled`**; product now requires **enum** (`OPEN`, `CLOSED`, `DRAFT`, `PENDING_REVIEW`, …).

**Current behavior**

- `my_work_fetch.graphql`, `BeaconViewCubit.toggleEnabled`, `Beacon.isEnabled`, repositories.

**Resolution**

- Full migration per `product-decisions.md` and **§4** of `missing-features-plan.md`.

---

## 5. Forward route as fullscreen dialog

**Conflict:** Forward should feel like a normal full-screen **step** in the flow; `fullscreenDialog: true` is modal.

**Current behavior**

- `root_router.dart` — **`ForwardBeaconRoute`**: `fullscreenDialog: true`.

**Resolution**

- Prefer standard push + **AppBar** consistent with §7 shell refactor.

---

## 6. Comments vs timeline-only beacon

**Conflict:** No normal comment threads on beacons in V1.

**Current behavior**

- `features/comment/`; `beacon_view_cubit.dart` (e.g. focused comment paths).

**Resolution**

- Remove or hide comment UI on beacon; keep forward notes + author updates + commitments only.

---

## 7. Profile copy: “Community feedback” vs trust framing

**Soft conflict:** MR is wanted; copy must not read as generic social engagement.

**Current behavior**

- `profile_screen.dart` — **OpinionList**; `profile_app_bar.dart` — **Rating** route.

**Resolution**

- Rename strings to **trust / MeritRank** framing where appropriate.

---

## 8. Home shell listeners (engagement only)

**Current behavior**

- `home_screen.dart` — **`LikeCubit`**, **`FavoritesCubit`**, **`ChatNewsCubit`**.

**Resolution**

- After removing likes/favorites UI, **drop** those listeners if nothing consumes them.
- **Keep** **`ChatNewsCubit`** (and related) — **chat stays** per `product-decisions.md`.

---

## Withdrawn / not contradictions (per product decisions)

| Topic | Note |
|-------|------|
| **1-to-1 chat** | **In scope.** Do not remove `ChatRoute` / peer tiles as a feature; IA may add forwarding-first layout but chat remains. |
| **Personal “Show Beacons”** | **In scope** on own profile; not treated as global discovery feed. |
| **Report / complaint** | **Required** — legal/moderation; **keep** `showComplaint` / `ComplaintRoute`. |
| **Infinite scroll on personal beacon list** | Acceptable for now on **personal** list; still avoid cross-user “all visible beacons” discovery surfaces elsewhere. |

---

## Summary table (active contradictions)

| # | Topic | Primary files |
|---|--------|----------------|
| 1 | Likes / favorites / polls on tiles | `beacon_tile_control.dart`, `beacon_tile.dart`, `home_screen.dart` |
| 2 | Graph requires vote | `beacon_tile_control.dart` |
| 3 | Poll create + tile | `beacon_create_screen.dart`, `beacon_tile_control.dart`, `beacon.dart` |
| 4 | `enabled` vs enum | GraphQL, `beacon.dart`, `beacon_view_cubit.dart`, `my_work_fetch.graphql` |
| 5 | Forward modal | `root_router.dart` |
| 6 | Comments | `features/comment/`, `beacon_view_cubit.dart` |
| 7 | Copy / MR framing | `profile_screen.dart`, `profile_app_bar.dart` |
| 8 | Dead engagement listeners | `home_screen.dart` (after §1) |

---

## Suggested sequencing

1. **Beacon lifecycle enum** migration (unblocks badges, My Work, inbox).
2. **Strip** likes/favorites/polls (§1–§3, §8).
3. **Decouple** graph from `myVote` (§2).
4. **AppBar shell** + **forward route** push (link to `missing-features-plan.md` §7, §3).
5. **Comment** audit (§6); **copy** pass (§7).
