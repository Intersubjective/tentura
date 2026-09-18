---
status: draft
kind: implementation-plan
revision: 3
issue: https://github.com/Intersubjective/tentura/issues/130
---

# Issue #130 — Activation-aware first-run orientation in the Home shell

**Goal.** A brand-new account currently lands on `/#/home/work` and sees the
ordinary "No active work yet" empty state — a dead end that explains neither the
relay model nor where anything lives. Replace that specific state (and only that
state) with a compact **orientation panel**, keep it out of the way once the
account has real activity, and, when signup came from a request invitation, drop
the user straight into that request instead of the generic tab.

**Non-goal (explicit, from the issue).** *Do not add a new permanent Home page,*
no new route, no sixth tab, no full-screen takeover. The orientation is a body
state of the existing `MyWorkRoute` inside the existing `HomeScreen` shell.

**Scope.** `packages/client` only. No server change, no GraphQL change, no
migration, no `MIN_CLIENT_VERSION` bump.

**Revision 2 added:** the frozen copy deck (§6 — every user-visible string in
en and ru), the debug override that forces the panel on or off after it has been
retired (§7), and the browser integration test that proves shown-vs-hidden
across the whole matrix (§10.3).

**Revision 3** applies the adversarial review recorded in §14: account-safe
singleton binding and hydration, corrected snackbar ownership on the invite
handoff, per-projection activation latching, a de-double-counted activity sum,
an integration test that proves what it claims, and several corrected facts
about the repository (client version, lint baseline, the `!kIsWeb` guard,
per-file browser profiles).

---

## 1. Problem statement (from the reporter)

> "When the registration is finished … I'm placed at `…/#/home/work`. At the
> beginning I wouldn't have any work proposals anyway … I would like to see a
> brief summary about the concept, how to use this website and the whole idea.
> Maybe even put a trust legend. I don't think the starter page should be all
> the time … I had 3 small windows during the registration describing the idea,
> but they never showed me **how to navigate and where to start**."

Two distinct failures:

| # | Failure | Fix |
|---|---------|-----|
| F1 | The 3 onboarding pages (`packages/landing/onboarding.js` on web, `IntroScreen` on native) explain the *concept* but are gone by the time the app opens, and never mention navigation. | Orientation panel in the shell, with a literal nav map, shown while the account is unactivated. |
| F2 | An invite that pointed at a specific request drops the user on a generic tab; the request context is spent on a snackbar. | Navigate to the request itself after the handoff. |

The reporter's own "maybe for the first 5 requests" is a proxy for *"don't show
it forever"*. This plan uses a sharper rule — activity-based, with a one-way
latch — see §3.

---

## 2. Product decisions (frozen; an executor must not re-open these)

- **D1.** Orientation is a *state of the My Work body*, not a route. It renders
  instead of `MyWorkEmptyBody` when the filter is `active` and the account is
  unactivated. Every other filter (`drafts`, `archived`, …) keeps today's empty
  copy.
- **D2.** **Two states, not three.** Unactivated → orientation panel. Activated
  (or dismissed) → today's behavior, unchanged. A middle "slim persistent hint"
  tier was considered and rejected: once cards exist, the list is not empty, and
  a banner over real work is exactly the noise Tentura's anti-feed stance
  forbids. Continued access is via the permanent reopen entry (D6), not a strip.
- **D3.** Activation is a **one-way latch, per device**. The moment either
  projection individually shows activity the latch is written and the panel
  never returns on that device — not when the user archives everything, not when
  they close every request.
  **Honest limit:** the latch is local, and the projections behind it are
  *current-state* queries, not history — `my_work_fetch.graphql:5-25` excludes
  deleted requests (`status: {_neq: 2}`) and selects only active help offers. An
  account that created and then deleted its only request will see the panel
  again on a fresh device. Accepted: rare, harmless, one tap from dismissal, and
  the alternative is a server-side `has_ever_participated` field this issue does
  not justify.
- **D4.** The panel carries **at most one primary CTA plus one secondary text
  action**, chosen contextually (§5.4). Not a menu of six things.
- **D5.** **No trust/MeritRank legend on the panel.** The issue is explicit:
  teach trust indicators contextually. The panel says one sentence about
  vouching; the existing `ContactBadgeLegend` + trust sheet stay where the
  badges actually appear (§5.6).
- **D6.** "How Tentura works" is reopenable forever from **Profile** (all
  platforms) and from **Settings** next to the existing "Show Intro Again".
  Same content widget as the panel — one source of copy, two hosts.
- **D7.** Beacon-invite signup lands **on the request**, with the existing
  inviter snackbar preserved as arrival context. The Inbox tab is set as the
  underlying branch first, so Back is meaningful.
- **D8.** Copy is user-facing terminology: **Request**, **discussion**,
  **thread**, **My field**, **My people**. Never "beacon" / "room". Enforced by
  `scripts/check-user-facing-terminology.sh` and
  `test/l10n/request_terminology_contract_test.dart`.
- **D9.** A **debug override** (Settings → Debug) can force the panel to always
  show or always hide, independently of the latches — for QA, screenshots, and
  the integration test. Tri-state (`auto` / `show` / `hide`), persisted, device-
  wide, defaulting to `auto`. It never bypasses the `active`-filter condition
  (§7).

---

## 3. Activation contract (frozen)

```dart
// packages/client/lib/features/home/domain/entity/home_activation.dart  (NEW)

/// Shell-level snapshot of "has this account done anything real yet".
///
/// Pure value type: no I/O, no Flutter import. Fed by the reporters that
/// already sit in [HomeScreen]'s account scope.
class HomeActivationSignals {
  const HomeActivationSignals({
    this.myWorkCardCount = 0,
    this.draftCount = 0,
    this.archivedCountHint = 0,
    this.inboxItemCount = 0,
    this.myWorkLoaded = false,
    this.inboxLoaded = false,
    this.inboxFailed = false,
  });

  /// Non-archived cards: authored + help-offered. **Drafts already live inside
  /// this collection** — `MyWorkState.draftCount` is
  /// `countDraftMyWorkCards(nonArchivedCards)` (`my_work_state.dart:41`), so
  /// [draftCount] must never be added on top of it.
  final int myWorkCardCount;
  final int draftCount;         // reported for the debug readout only
  final int archivedCountHint;
  final int inboxItemCount;     // every inbox item, not just needs-me
  final bool myWorkLoaded;
  final bool inboxLoaded;

  /// The Inbox projection failed rather than resolved. Settles the decision
  /// (no infinite spinner) and forbids orientation (fail closed).
  final bool inboxFailed;

  int get myWorkActivityCount => myWorkCardCount + archivedCountHint;

  /// Disjoint by construction; drafts are deliberately absent.
  int get activityCount => myWorkActivityCount + inboxItemCount;

  bool get hasActivity => activityCount > 0;

  /// Enough is known to decide. A failed Inbox counts as settled.
  bool get isSettled => myWorkLoaded && (inboxLoaded || inboxFailed);

  /// Activity seen on a projection that *individually* succeeded — the trigger
  /// for the activation latch. Deliberately does not require both projections:
  /// a My Work card observed during an Inbox outage is still real activity.
  bool get hasProvenActivity =>
      (myWorkLoaded && myWorkActivityCount > 0) ||
      (inboxLoaded && inboxItemCount > 0);
}

/// Debug-only forcing of the orientation panel (§7). `auto` is production.
enum OrientationDebugOverride { auto, show, hide }
```

**Show rule** (the only place this is decided):

```dart
/// The empty branch needs three outcomes, not two: "orientation", "ordinary
/// empty body", and "we do not know yet — keep the spinner".
enum OrientationDecision { show, ordinaryEmpty, undecided }

OrientationDecision decideFor(MyWorkFilter filter) {
  if (filter != MyWorkFilter.active) return OrientationDecision.ordinaryEmpty;
  if (!hydrated) return OrientationDecision.undecided;   // latches still loading
  switch (debugOverride) {
    case OrientationDebugOverride.show: return OrientationDecision.show;
    case OrientationDebugOverride.hide: return OrientationDecision.ordinaryEmpty;
    case OrientationDebugOverride.auto:
      if (dismissedLatch || activatedLatch) {
        return OrientationDecision.ordinaryEmpty;
      }
      if (signals.inboxFailed) return OrientationDecision.ordinaryEmpty;
      if (!signals.isSettled) return OrientationDecision.undecided;
      return signals.hasActivity
          ? OrientationDecision.ordinaryEmpty
          : OrientationDecision.show;
  }
}
```

**Write rule:** whenever `signals.hasProvenActivity` and the activated latch is
unset → persist it once. Idempotent, fire-and-forget, one write per account.

Keyed on `hasProvenActivity`, **not** on `isSettled`: a My Work projection that
succeeds and shows a card while Inbox is failing is proof of activity, and
throwing that observation away because the *other* projection failed is exactly
how a long-standing user gets the first-run panel back. The debug override does
**not** suppress the write — forcing the panel visible must not corrupt real
activation state.

**Hydration.** `hydrated` stays false until `bindAccount` has finished reading
both per-user latches *and* the device-wide override. Until then the decision is
`undecided`, never `show`; otherwise a dismissed account flashes the panel, or a
persisted `hide` override is briefly ignored. Preference reads are tagged with
the account they were issued for and with a generation counter; a result whose
account no longer matches the bound one is discarded (§4 / UNIT 4).

Persisted keys in the existing Drift `settings` table, following the
`MyWorkDeskPreferencesRepository` key convention exactly:

| Key | Scope | Meaning |
|-----|-------|---------|
| `home:activated:<userId>` | per user | one-way latch, written on first observed activity |
| `home:orientationDismissed:<userId>` | per user | user tapped "Got it" |
| `home:orientationDebugOverride` | per device | `auto` \| `show` \| `hide` (§7) |

**Why the `undecided` outcome exists.** Both `MyWorkCubit` and `InboxCubit`
start loading with empty collections, so without a gate every returning user
sees the panel flash before their cards arrive.

The existing spinner does **not** already cover that window — revision 2 assumed
it did and was wrong. `_MyWorkListBody`'s loading branch checks only
`MyWorkState.isLoading` (`my_work_screen.dart:391`), so once My Work resolves
the body reaches `cards.isEmpty` (`:423`) while Inbox may still be in flight.
UNIT 7 therefore renders the spinner itself for `undecided`. It is bounded on
both sides: My Work is already resolved to have reached that branch at all, and
a failed Inbox sets `inboxFailed`, which settles the decision as
`ordinaryEmpty` instead of spinning forever.

**Known limitation.** `_MyWorkListBody`'s `onRefresh` calls `MyWorkCubit.fetch`
only (`my_work_screen.dart:432`), so pull-to-refresh does not retry a failed
Inbox projection; that account keeps the ordinary empty body until the Inbox tab
is visited. Accepted — the fallback is today's behavior, not a regression.

---

## 4. Where the code goes (layers)

Dependency direction stays inward (`AGENTS.md` invariant). `features/my_work`
already imports `features/home` cubits, so hosting shell-level activation in
`features/home` adds no new edge.

```
features/home/
  domain/entity/home_activation.dart                   (NEW, pure)
  domain/port/home_orientation_preferences_port.dart   (NEW)
  data/repository/home_orientation_preferences_repository.dart (NEW, Drift)
  ui/bloc/home_activation_cubit.dart                   (NEW, @singleton)
  ui/bloc/home_activation_state.dart                   (NEW, freezed)
  ui/widget/home_activation_reporter.dart              (NEW)
  ui/widget/how_tentura_works_content.dart             (NEW, shared body)
  ui/widget/home_orientation_panel.dart                (NEW, inline panel)
  ui/sheet/how_tentura_works_sheet.dart                (NEW, reopen host)
ui/widget/trust_info_sheet.dart                        (NEW, promoted from
                                                        profile_view_body.dart)
```

`HomeActivationCubit` is a **singleton fed by reporters**, mirroring
`InboxOperationalCubit`. It never reads another cubit directly (lint:
`no_cubit_to_data_service_import`, and the repo's existing reporter idiom). It
injects the preferences port only — one port, so no `*Case` is required
(`cubit_requires_use_case_for_multi_repos` not triggered).

---

## 5. UX specification

### 5.1 Placement and container

Rendered by `_MyWorkListBody` in place of `MyWorkEmptyBody`, inside the existing
`RefreshIndicator.adaptive` + `CustomScrollView`, wrapped by the existing
`TenturaContentColumn`.

> **Trap — must not be missed.** The current empty branch uses
> `SliverFillRemaining(hasScrollBody: false)`. The orientation panel is taller
> than a 375×667 viewport and will overflow there. The orientation branch must
> use `SliverToBoxAdapter` (keeping `AlwaysScrollableScrollPhysics` so
> pull-to-refresh still works). Do not "fix" the overflow by shrinking type —
> the design-system floors (body ≥ 15, metadata ≥ 13) are hard.

Width: reuse the shell's `TenturaContentColumn`; inside it constrain the panel
to `maxWidth` 400 (compact) / 560 (regular + expanded) so body copy stays inside
the 60–75 character measure. Horizontal insets come from `tt.screenHPadding`,
which `MyWorkScreen`'s `SafeArea(minimum:)` already applies.

### 5.2 Anatomy

```
┌─────────────────────────────────────────────────┐
│  ◇  Welcome to Tentura                          │  titleLarge
│     Someone you know vouched for you. Tentura    │  bodyMedium /
│     is where people get things done through      │  onSurfaceVariant
│     people they trust — ask for help when you    │
│     need it, or pass a request on to someone     │
│     who can give it.                             │
│                                                 │
│  How it works                                   │  titleSmall
│   1  Post a request — say what you need, in     │  bodyMedium
│      your own words. Nothing here is public.    │
│   2  Friends pass it on — anyone who sees it    │
│      can forward it to someone better placed    │
│      to help.                                    │
│   3  You sort it out together — every request   │
│      has its own discussion, where you agree    │
│      the details and close it when it's done.   │
│                                                 │
│  Where things are                               │  titleSmall
│   [work]    My Work    Requests you posted…   › │  tappable, ≥48dp
│   [inbox]   Inbox      Requests your friends… › │
│   [graph]   My field   The people and reque… › │
│   [people]  My people  Everyone you trust…    › │
│                                                 │
│   ▸ Create request                              │  primary CTA (contextual)
│   ▸ Find ways to help                           │  secondary text action
│   ▸ Got it                                      │  dismiss (text action)
└─────────────────────────────────────────────────┘
```

Container: `TenturaTechCard` (flat surface + hairline border, no elevation) —
already the app's record-surface idiom, so the panel reads as *content*, not as
a modal interrupting the tab. No custom shadows, no gradient, no illustration
beyond the existing brand glyph.

### 5.3 The nav map is interactive

Each "Where things are" row is a real tap target that switches the tab
(`AutoTabsRouter.of(context).setActiveIndex(HomeTabSpec.forTab(...).index)`).
This is the direct answer to *"they never showed me how to navigate"*: the row
both names the destination and takes you there, so the mapping icon→tab is
learned by doing rather than read.

Row requirements:
- `InkWell` inside the card (`TenturaTechCard` clips), min height `tt.buttonHeight`
  and never below 48dp — assert in the widget test.
- Leading icon = the **same glyph the nav bar uses** so the mapping is literal:
  `Icons.work_outline`, `Icons.inbox_outlined`, `TenturaIcons.graph`,
  `Icons.people_outline`. Use the bare `Icon`, **not** the `*NavbarItem`
  widgets — those carry attention dots and would render a meaningless marker
  here.
- Trailing `Icons.chevron_right` at `tt.iconSize`, `onSurfaceVariant`.
- `Semantics(button: true, label: l10n.orientationWhereSemantics(name, description))`.
- Profile/Me is deliberately **omitted**: five rows is a list, four is a map,
  and the profile tab is self-evident from the avatar.

### 5.4 Contextual next actions (priority ladder)

Exactly one primary + one secondary; the third line is always the dismiss.

| Precondition | Primary (filled) | Secondary (text) |
|---|---|---|
| `inboxNeedsMeCount > 0` | `View Inbox ({count})` → Inbox tab | `Create request` |
| otherwise | `Create request` → `ScreenCubit.showBeaconCreate()` | `Find ways to help` → Field tab |

This reuses the exact precedence and l10n keys `MyWorkEmptyBody` already
implements (`myWorkEmptyActiveInboxPrimaryCta` / `myWorkEmptyActiveCreateCta` /
`constellationFindWaysToHelp`), so a user who dismisses orientation and later
returns to the ordinary empty state sees the same two actions in the same order.
No new CTA vocabulary is introduced.

`inboxNeedsMeCount` comes from the already-mounted `InboxOperationalCubit` —
no new query.

### 5.5 Dismissal

- `Got it` (`TenturaTextAction`) writes `home:orientationDismissed:<userId>` and
  the body falls back to `MyWorkEmptyBody` in the same frame.
- Dismissal is **not** destructive and needs no confirm dialog; the content is
  one tap away forever via Profile → How Tentura works (D6).
- The transition is an `AnimatedSwitcher` crossfade, 200 ms, `Curves.easeOut`,
  skipped under `MediaQuery.disableAnimations` (reduced motion). One animated
  element only.

### 5.6 Trust / MeritRank — contextual, not front-loaded

The panel says exactly one trust sentence (the opening clause of
`orientationIntro`: *"Someone you know vouched for you."*) and shows **no
legend**.

The legend already exists and already lives where the badges do:
- `ContactBadgeLegend` — the mutual / eye-open / eye-closed rows.
- `_showTrustInfoSheet` in `profile_view_body.dart` — title + body + legend.
- The Field/graph legend panel (`graph_legend_panel.dart`).

Work here is small and additive: promote `_showTrustInfoSheet` to a shared
`showTrustInfoSheet(BuildContext)` in `lib/ui/widget/trust_info_sheet.dart`,
have `profile_view_body.dart` call it (no behavior change), and add one
`IconButton(Icons.info_outline, tooltip: l10n.trustInfoTitle)` to the **My
people** (Friends) app-bar actions — the first list where a new user meets trust
badges without any explanation. That is the whole contextual-teaching delta.

### 5.7 Accessibility & responsive checklist (blocking)

- Every tap target ≥ 48dp; row hit area extends full card width.
- `Semantics` labels on nav rows; `excludeSemantics` on the decorative icon
  inside a labeled row.
- Screen-reader order = visual order: heading → paragraph → steps → nav map →
  actions.
- Text scaling: verified at `textScaleFactor` 2.0 with no overflow — every step
  and nav-row text must `softWrap`, never `TextOverflow.ellipsis`.
- Light **and** dark verified independently; all color via `colorScheme` /
  `context.tt` tokens (lints `no_operational_raw_color`, `no_raw_edge_insets`,
  `no_raw_border_radius`, `no_inline_font_size` are hard gates).
- Compact (375 wide), regular (720), expanded (1280) all render without
  horizontal scroll; expanded uses the side rail, so the panel must not assume
  a bottom nav bar exists.
- Type roles only: `titleLarge` / `titleSmall` / `bodyMedium` / `labelLarge`.
  No literal sizes.

---

## 6. Copy deck (frozen)

Every user-visible string this feature introduces. **These are the final
values** — an executor copies them verbatim into `app_en.arb` / `app_ru.arb`,
adds the required `@key.description` metadata, and runs `flutter gen-l10n`.

Destination *names* in the nav map reuse existing keys (`myWork`, `inbox`,
`constellationNavLabel`, `network`) — do not duplicate them. CTA labels reuse
`myWorkEmptyActiveInboxPrimaryCta`, `myWorkEmptyActiveCreateCta`,
`constellationFindWaysToHelp`.

### 6.1 Panel and sheet

| Key | en | ru |
|---|---|---|
| `orientationTitle` | Welcome to Tentura | Добро пожаловать в Tentura |
| `orientationIntro` | Someone you know vouched for you. Tentura is where people get things done through people they trust — ask for help when you need it, or pass a request on to someone who can give it. | За вас поручился кто-то из знакомых. Tentura — это место, где дела делаются через людей, которым вы доверяете: просите о помощи, когда она нужна, и передавайте запрос тому, кто сможет помочь. |
| `orientationIntroReopen` | Tentura is where people get things done through people they trust — ask for help when you need it, or pass a request on to someone who can give it. | Tentura — это место, где дела делаются через людей, которым вы доверяете: просите о помощи, когда она нужна, и передавайте запрос тому, кто сможет помочь. |
| `orientationHowTitle` | How it works | Как это работает |
| `orientationHowStep1` | Post a request — say what you need, in your own words. Nothing here is public. | Опубликуйте запрос — своими словами опишите, что вам нужно. Здесь нет общей ленты. |
| `orientationHowStep2` | Friends pass it on — anyone who sees it can forward it to someone better placed to help. | Друзья передают его дальше — любой, кто увидит запрос, может переслать его тому, кто ближе к решению. |
| `orientationHowStep3` | You sort it out together — every request has its own discussion, where you agree the details and close it when it's done. | Вы обо всём договариваетесь на месте — у каждого запроса есть своё обсуждение: там вы уточняете детали и закрываете запрос, когда всё сделано. |
| `orientationWhereTitle` | Where things are | Что где находится |
| `orientationWhereWork` | Requests you posted, and the ones you've offered to help with. | Запросы, которые вы опубликовали, и те, где вы предложили помощь. |
| `orientationWhereInbox` | Requests your friends have forwarded to you. | Запросы, которые вам переслали друзья. |
| `orientationWhereField` | The people and requests around you — start here to find a way to help. | Люди и запросы вокруг вас — начните отсюда, если хотите помочь. |
| `orientationWhereNetwork` | Everyone you trust, and everyone who trusts you. | Все, кому доверяете вы, и все, кто доверяет вам. |
| `orientationWhereSemantics` | `{name}: {description}` | `{name}: {description}` |
| `orientationDismiss` | Got it | Понятно |
| `orientationReopen` | How Tentura works | Как устроена Tentura |

`orientationWhereSemantics` is a two-placeholder pattern (`name`, `description`,
both `String`). It exists so the screen-reader label is composed by the
localization, not by string concatenation in Dart.

### 6.2 Which title goes where

| Host | Title key | Intro key |
|---|---|---|
| Inline panel (My Work, first run) | `orientationTitle` | `orientationIntro` |
| Reopened sheet (Profile / Settings) | `orientationReopen` | `orientationIntroReopen` |

`HowTenturaWorksContent` therefore takes `title` and `intro` as parameters
rather than reading them itself — the same widget, two framings. The reopened
sheet drops the vouch sentence because by then it is stale news.

### 6.3 Debug section (§7)

| Key | en | ru |
|---|---|---|
| `settingsDebugOrientationSection` | First-run orientation | Панель первого запуска |
| `settingsDebugOrientationOverride` | Orientation panel | Показ панели |
| `settingsDebugOrientationAuto` | Automatic | Автоматически |
| `settingsDebugOrientationShow` | Always show | Всегда показывать |
| `settingsDebugOrientationHide` | Always hide | Всегда скрывать |
| `settingsDebugOrientationStatus` | Activated: {activated} · Dismissed: {dismissed} · Activity: {count} | Активирован: {activated} · Скрыт: {dismissed} · Активность: {count} |
| `settingsDebugOrientationReset` | Reset first-run state | Сбросить состояние первого запуска |
| `settingsDebugOrientationResetDone` | First-run state reset for this account | Состояние первого запуска сброшено |

`settingsDebugOrientationStatus` placeholders: `activated` and `dismissed` are
`String`, `count` is `int`. There are no `l10n.yes` / `l10n.no` keys in this
project (verified) — pass plain `"true"` / `"false"`. This is a debug screen;
do not invent localized yes/no keys for it.

`count` is `HomeActivationSignals.activityCount`, which by §3 excludes
`draftCount` (drafts are already inside `myWorkCardCount`). Revision 2's sum
double-counted them, which did not change visibility but made this readout
wrong — the one place the bug was actually observable.

### 6.4 Copy rules the executor must not break

- No occurrence of *beacon*, *room*, *node*, *edge*, *MeritRank*, or *score* in
  any of these values. `scripts/check-user-facing-terminology.sh` fails the
  build otherwise.
- "request" is lowercase in prose, capitalized only when naming the tab/CTA.
- Steps are one sentence each with an em-dash clause; do not split them into
  title+body pairs — the numbered row layout depends on a single string.
- Russian uses **запрос / запросы** for the request, **обсуждение** for the
  discussion, and never «просьба» here (that noun is reserved for coordination
  asks inside a thread).

---

## 7. Debug override (D9)

**Why.** Once the panel is retired it is retired for good, per D3 — which makes
it unreachable for QA, for screenshots, for design review, and for an
integration test that needs both branches inside one browser session. The
override is the escape hatch.

**Contract.**

- Persisted under `home:orientationDebugOverride` (device-wide, not per user) so
  it survives a web reload — the integration test depends on that.
- Absent or unparsable value → `OrientationDebugOverride.auto`. Never throw.
- `show` forces the panel wherever the panel *could* legally appear: the My Work
  body, `active` filter, empty card list. It does **not** show the panel over a
  populated list, and does **not** apply to `drafts`/`archived` filters — those
  are layout states, not policy, and forcing them would test nothing real.
- `hide` suppresses the panel for an account that would otherwise get it (used
  to check the ordinary empty state on a fresh account without dirtying the
  dismiss latch).
- The activation write rule (§3) still runs under both overrides. Forcing
  display must not falsify persisted state.

**Placement.** A new section in `DebugSettingsScreen`, above the existing FCM
block, matching that screen's idiom (`Text(titleMedium)` heading +
`TenturaCommandButton`s, `spacing: tt.rowGap`):

```
First-run orientation
  Activated: false · Dismissed: true · Activity: 0        ← status readout
  [ Automatic | Always show | Always hide ]                ← segmented control
  [ Reset first-run state ]                                ← command button
```

- The tri-state control is a `SegmentedButton<OrientationDebugOverride>`. This
  is the one place `SegmentedButton` is permitted — the design-system rule bans
  it on *beacon detail list surfaces*, not on the debug screen.
- `Reset first-run state` clears **both** per-user latches for the currently
  signed-in account and emits `settingsDebugOrientationResetDone` via the
  existing `UiEffectPort` snackbar path. It does not touch the override.
- The status readout is live (rebuilds from `HomeActivationCubit`), so a tester
  can watch the activity count change without leaving the screen.

**Exposure.** `DebugSettingsScreen` is already reachable from Settings in every
build with no environment gate, so this adds no new production surface. Do not
add an env gate now — that would be a separate, wider change to the whole debug
screen.

**Test ids** (`lib/ui/test_ids.dart`, needed by §10.3):

```dart
static const orientationPanel        = 'orientation.panel';
static const orientationDismiss      = 'orientation.dismiss';
static String orientationNavRow(String tab) => 'orientation.nav.$tab';
static const debugOrientationAuto    = 'debug.orientation.auto';
static const debugOrientationShow    = 'debug.orientation.show';
static const debugOrientationHide    = 'debug.orientation.hide';
static const debugOrientationReset   = 'debug.orientation.reset';
```

---

## 8. Invitation → request handoff (F2)

Today: `HomePostJoinListener` sets tab index 1 (Inbox) and emits
`BeaconInviteAcceptedMessage`. The request that motivated the whole signup is
never opened.

Change, inside `_handlePostJoin` only:

1. `widget.tabsRouter.setActiveIndex(HomeTabSpec.forTab(HomeTab.inbox).index)`
   (unchanged, so Back from the request lands on Inbox rather than an empty
   root).
2. `GetIt.I<ScreenCubit>().showBeacon(dest.beaconId!, entry: kBeaconEntryInvite)`
   — new const `kBeaconEntryInvite = 'invite'` in `consts.dart`, alongside the
   existing `kBeaconEntry*` family, so entry attribution stays truthful.
3. **Move snackbar ownership into the listener, and emit it *after* the push.**
   Revision 2's "keep both call sites as they are" was wrong. `AcceptInviteCubit`
   emits `BeaconInviteAcceptedMessage` *before* `NavigateReplace`
   (`accept_invite_cubit.dart:154-166`); the message is a
   `LocalizableActionMessage` (`accept_invite_messages.dart:81`), so the
   dispatcher defers it a frame (`ui_effect_dispatcher.dart:75-82`); and the app
   installs `ClearSnackBarsOnPushObserver` (`app.dart:129-132`), which clears
   snackbars in a microtask on `didPush` (`ui_utils.dart:66-75`).
   `BeaconViewRoute` is a **root** route (`root_router.dart:395-406`), so the new
   push lands on the observed navigator and destroys the very message that was
   supposed to preserve the invite context.

   Fix — exactly-once emission, correct ordering, both paths:
   - `AcceptInviteCubit`, beacon branch: set `showSnackbar: true` on the
     `PostJoinDestination` and **stop emitting `ShowMessage` itself** (navigate
     only). The listener becomes the single owner of that message.
   - `HomePostJoinListener`: `await` the `showBeacon` navigation, *then* emit
     `ShowMessage(BeaconInviteAcceptedMessage(...))` when `dest.showSnackbar`.
     Emitting after the push is what survives the observer.
   - The web `sessionStorage` handoff already carries `showSnackbar: true` and
     needs nothing beyond the new ordering.
4. **Fallback is mandatory.** If the request cannot be opened — deleted, or
   dropped by the Hasura `can_read_content` row permission — the user must not
   be stranded on an error screen as their first-ever view. Verify how
   `BeaconViewScreen` reports a missing/unreadable id; if it does not already
   degrade to a message + pop, the listener must not push blindly. Confirm this
   before implementing step 2 and record the finding in the journal.
5. Orientation and the handoff do not collide: the panel lives on the My Work
   branch and simply renders behind. When the user later returns to My Work with
   still-zero activity, they get the orientation — correct, since joining a
   request does not by itself create a card until the projection reports it.

`_handled` already guards against double-fire; do not add a second latch.

---

## 9. Implementation units

Execute in order. One unit → its checks → journal entry → focused local commit.
Do not push.

### UNIT 1 — l10n copy
Add every key from §6 to `packages/client/l10n/app_en.arb` and `app_ru.arb`
with `@key` descriptions; run `flutter gen-l10n`.

**Checks:** `bash scripts/check-user-facing-terminology.sh`;
`flutter test test/l10n/`.

### UNIT 2 — activation domain entity
Create `home_activation.dart` exactly as frozen in §3 (`HomeActivationSignals`,
`OrientationDebugOverride`, `OrientationDecision`). Pure Dart. No Flutter, no
data types.

**Test (new):** `test/features/home/home_activation_test.dart` — `isSettled`
false until My Work is loaded and Inbox is loaded-or-failed; `activityCount`
excludes `draftCount`; `hasActivity` false on an all-zero settled snapshot;
`hasProvenActivity` true for a loaded My Work with cards while Inbox is still
unloaded, and true for a loaded Inbox with items while My Work is unloaded.

### UNIT 3 — preferences port + Drift repository
`HomeOrientationPreferencesPort`:

```dart
Future<bool> isActivated({required String userId});
Future<void> setActivated({required String userId});
Future<bool> isOrientationDismissed({required String userId});
Future<void> setOrientationDismissed({required String userId});
Future<void> resetFirstRunState({required String userId});   // debug
Future<OrientationDebugOverride> getDebugOverride();          // device-wide
Future<void> setDebugOverride(OrientationDebugOverride value);
```

`HomeOrientationPreferencesRepository` registered
`@LazySingleton(as: …, env: [Environment.dev, Environment.prod])` — copy
`MyWorkDeskPreferencesRepository` verbatim in shape, including private key
builders. Unparsable override text → `auto`. Run
`dart run build_runner build -d`.

**Test (new):** in-memory Drift round-trip per user id; two user ids do not see
each other's latch; `resetFirstRunState` clears both and leaves the override;
a garbage override string reads back as `auto`.

### UNIT 4 — `HomeActivationCubit` + binder + reporter
- `HomeActivationState` (freezed): `signals`, `activatedLatch`,
  `dismissedLatch`, `debugOverride`, `boundAccountId`, `hydrated`, plus
  `OrientationDecision decideFor(MyWorkFilter filter)` implementing §3 verbatim.
- `@singleton HomeActivationCubit` injecting only the port:

  ```dart
  Future<void> bindAccount(String accountId);   // '' unbinds
  void reportMyWork({required String accountId, /* counts, loaded */});
  void reportInbox({required String accountId, /* count, loaded, failed */});
  Future<void> dismiss();
  Future<void> setDebugOverride(OrientationDebugOverride value);
  Future<void> resetFirstRunState();
  ```

- **Account safety — the part revision 2 left unspecified.** `bindAccount` sets
  `boundAccountId`, clears `signals`, sets `hydrated = false`, bumps an internal
  generation counter, then loads both latches + the override and applies the
  result only if the generation still matches. `''` unbinds: signals cleared,
  `hydrated = false`, decision `undecided`. Every `report*` call carries the
  account its projection belongs to and is **dropped** when that does not equal
  `boundAccountId`.

  Copy this discipline from `HomeAttentionCubit`, which already implements it
  (account-id rejection at `home_attention_cubit.dart:55,74`; generation reset at
  `:94-101`) — do not invent a variant.

  It matters because `_InboxScope` deliberately keeps the **last** account's
  `MyWorkCubit`/`InboxCubit` alive while `accountId` is transiently empty
  (`home_screen.dart:348-363`). Binding off `_lastAccountId` would keep the old
  account bound straight through sign-out; binding off
  `AuthCubit.currentAccountId` *without* the report filter would let the dying
  account's projections write into the newly bound one.

- **Who calls `bindAccount`:** a new `HomeActivationBinder` mounted inside the
  existing `BlocSelector<AuthCubit, AuthState, String>` in
  `HomeScreen.wrappedRoute` (`home_screen.dart:57-64`) — that selector already
  yields `currentAccountId` and already rebuilds on account change. It binds on
  first build and on every change, including to `''`. No other caller exists;
  revision 2 declared the method with none.

- **Provider placement — also unspecified in revision 2.** `@singleton`
  registers with GetIt; it does **not** put the cubit in the widget tree. Two
  hosts need it explicitly:
  - `HomeScreen.wrappedRoute`'s `MultiBlocProvider` gains
    `BlocProvider.value(value: GetIt.I<HomeActivationCubit>())` alongside the
    existing `ScreenCubit` / `HomeTabReselectCubit` / `HomeAttentionCubit` /
    `InboxOperationalCubit` entries (`home_screen.dart:46-52`). This is what
    `_MyWorkListBody`'s `BlocSelector` resolves against.
  - `DebugSettingsScreen` is a **root** route (`root_router.dart:206-215`),
    outside that subtree and outside the app-level providers
    (`app.dart:141-165`). It already implements `AutoRouteWrapper`; add the same
    `BlocProvider.value` there.

- `HomeActivationReporter`: two `BlocListener`s (`MyWorkCubit`, `InboxCubit`)
  calling the account-tagged report methods. Mount in `_InboxScope` wrapping
  `MyWorkAttentionReporter` — both cubits are provided there and the scope's own
  `id` is precisely the account those projections belong to, so it is the value
  to pass as `accountId`. Report `inboxFailed` from the Inbox error state
  (`inbox_cubit.dart:248-257`) as well as `inboxLoaded` from `projectionLoaded`
  (`:244`).

**Tests (new):** `test/features/home/home_activation_cubit_test.dart` —
`undecided` until hydrated; `undecided` while My Work is loaded and Inbox is
neither loaded nor failed; `ordinaryEmpty` when `inboxFailed`; `show` on a
settled-empty snapshot; latch written exactly once on `hasProvenActivity`,
**including the My-Work-only-during-an-Inbox-outage case**; `dismiss()`
suppresses without writing the activation latch; a report tagged with a
non-bound account is ignored; rebinding mid-flight discards the stale preference
read; unbinding to `''` returns `undecided`; `show` override wins over both
latches; `hide` override wins over an eligible account; **neither override
suppresses the activation write**; no override ever shows the panel for a
non-`active` filter.

### UNIT 5 — `HowTenturaWorksContent`
Shared body: title + intro (both injected per §6.2) + three numbered steps +
four nav rows. Callback-only (`onOpenTab(HomeTab)?`), zero navigation inside.
`null` callback → rows render but are non-interactive (the Settings host has no
`AutoTabsRouter` above it). Tokens only.

**Test (new):** `test/features/home/how_tentura_works_content_test.dart` —
renders four nav rows with the §6 descriptions; tapping a row invokes the
callback with the right `HomeTab`; every row's hit box ≥ 48dp; `null` callback
renders rows without an `InkWell` tap response; renders at `textScaleFactor` 2.0
in a 375×667 surface with no overflow.

### UNIT 6 — `HomeOrientationPanel`
`TenturaTechCard` + `HowTenturaWorksContent` + the contextual action ladder
(§5.4) + `Got it`. Callback-only; the parent owns navigation, matching
`MyWorkEmptyBody`'s existing contract. Root gets
`key: TestIds.key(TestIds.orientationPanel)`.

**Test (new):** `test/features/home/home_orientation_panel_test.dart` — CTA
ladder in both branches; `Got it` fires the dismiss callback; exactly one
`FilledButton` in the tree (one-primary-CTA rule); light and dark pump.

### UNIT 7 — My Work body integration
In `_MyWorkListBody.build`, in the `cards.isEmpty` branch
(`my_work_screen.dart:423`): select on `HomeActivationCubit` alongside the
existing `InboxOperationalCubit` selector and switch on
`decideFor(state.filter)`:

| Decision | Body |
|---|---|
| `show` | `SliverToBoxAdapter(child: HomeOrientationPanel(...))` |
| `ordinaryEmpty` | today's `SliverFillRemaining` + `MyWorkEmptyBody`, untouched |
| `undecided` | `SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator.adaptive()))` |

The `undecided` arm is **not optional**. The screen's own loading branch
(`my_work_screen.dart:391`) checks only `MyWorkState.isLoading`, so a resolved My
Work with an in-flight Inbox reaches this branch; without the arm the ordinary
empty body renders and then swaps to the panel — the exact flash the gate
exists to prevent. Keep all three arms inside the existing `RefreshIndicator` +
`CustomScrollView` so pull-to-refresh survives. Crossfade per §5.5.

Wire the panel's callbacks to the handlers `MyWorkEmptyBody` already uses
(`showBeaconCreate`, `setActiveIndex`), plus `onOpenTab` → `setActiveIndex` and
`onDismiss` → `HomeActivationCubit.dismiss()`.

**Test (new):** `test/features/my_work/my_work_orientation_state_test.dart` —
one case per decision: unactivated + settled-empty + `active` → panel; `drafts`
filter → old empty body; activated → old empty body; unhydrated → spinner; My
Work loaded while Inbox is in flight → spinner; `inboxFailed` → old empty body,
never the panel.
**Regression:** `my_work_empty_body_test.dart` must pass unchanged.

### UNIT 8 — reopen entry points (D6)
- `how_tentura_works_sheet.dart`: `showHowTenturaWorksSheet(context)` using
  `showTenturaAdaptiveSheet` with `isScrollControlled: true`,
  `showDragHandle: true`, `useSafeArea: true` — same construction as
  `_showTrustInfoSheet`. Uses the reopen title/intro per §6.2. Nav-row taps
  close the sheet first, then switch the tab; hosts without an
  `AutoTabsRouter` pass `onOpenTab: null`.
- `profile_body.dart`: `OutlinedButton.icon(Icons.help_outline,
  l10n.orientationReopen)` in the existing button stack, above Settings.
- `settings_screen.dart`: same action beside "Show Intro Again" — but placed
  **outside** its `if (!kIsWeb)` guard (`settings_screen.dart:155-160`). D6
  promises the reopen entry unqualified, and web is the platform this issue was
  filed against; inside the guard it would vanish exactly where it is needed.

**Test (new):** sheet opens from Profile; nav rows visible-but-inert when
`onOpenTab` is null.

### UNIT 9 — contextual trust affordance (§5.6)
Move `_showTrustInfoSheet` into `lib/ui/widget/trust_info_sheet.dart` as
`showTrustInfoSheet`; update `profile_view_body.dart`; add the info `IconButton`
to `friends_app_bar_actions.dart`.

**Test:** existing profile_view tests still pass; new test asserts the Friends
app bar exposes a button tooltipped `l10n.trustInfoTitle`.

### UNIT 10 — debug override UI (§7)
Add the `First-run orientation` section to `DebugSettingsScreen`: live status
readout, `SegmentedButton<OrientationDebugOverride>`, and the reset command
button, all with the §7 test ids. Wire to `HomeActivationCubit`.

**Test (new):** `test/features/settings/debug_orientation_section_test.dart` —
selecting each segment calls `setDebugOverride` with the matching value; reset
calls `resetFirstRunState`; the status readout reflects cubit state.

### UNIT 11 — invite → request navigation (§8)
First **verify** §8 step 4 (unreadable-request behavior) and journal the finding.
Then add `kBeaconEntryInvite` and change
`HomePostJoinListener._handlePostJoin`.

**Test:** extend `test/features/home/home_post_join_listener_test.dart` — a
destination with a beacon id sets the Inbox index **and** requests the beacon
route with `entry=invite`; a destination without a beacon id does neither.

### UNIT 12 — browser integration test
Per §10.3. New helpers in `integration_test/support/e2e_test_helpers.dart`, new
`integration_test/first_run_orientation_test.dart`, and a row in the test table
in `docs/local-integration-tests.md`.

### UNIT 13 — version + verification
- Bump `packages/client/pubspec.yaml` `version:` — **`7.2.2` → `7.3.0`**.
  (`7.2.2` is the value at plan writing; re-read the file rather than trusting
  this number, and bump the minor from whatever is actually there. Revision 2
  said `7.2.1`, which no longer matches — a literal find-replace would have
  silently matched nothing.)
- Run the app once so `hook/build.dart` rewrites
  `packages/client/web/index.html`'s `flutter_bootstrap.js?v=` cache-buster,
  then confirm the diff is staged. A missed cache-buster has previously made a
  landed fix look broken (`AGENTS.md`).
- Do **not** raise `kDefaultMinClientVersion` — client-only change.

---

## 10. Test plan

### 10.1 Unit / pure
`home_activation_test.dart` — the value type and the show rule's inputs.

### 10.2 Widget
`how_tentura_works_content_test.dart`, `home_orientation_panel_test.dart`,
`my_work_orientation_state_test.dart`, `debug_orientation_section_test.dart`,
plus the extended `home_post_join_listener_test.dart`.

These own the cases an e2e cannot reach reliably: the unresolved-projection
window, `textScaleFactor` 2.0 overflow, dark mode, and hit-box geometry.

### 10.3 Browser integration test (new)

`packages/client/integration_test/first_run_orientation_test.dart`, run by
`./scripts/run_client_integration_web_local.sh` like every other file there.
It drives the **real** app against the local stack, so it proves the wiring the
widget tests stub out: Drift persistence, account scoping, tab switching, and
the debug override surviving navigation.

**Fixture.** `bootstrapFixture` creates author + helper + a mutual friendship
and **no requests** — exactly the unactivated shape this feature targets. That
is what makes the shown-case reachable without a new QA endpoint.

**New helpers** (`support/e2e_test_helpers.dart`):

```dart
Future<void> expectOrientationPanel(WidgetTester tester, {required bool visible});
Future<void> openDebugSettings(WidgetTester tester);      // goToPath(kPathDebugSettings)
Future<void> setOrientationOverride(WidgetTester tester, OrientationDebugOverride mode);
Future<void> resetFirstRunOrientation(WidgetTester tester);
Future<void> awaitActivationSettled(WidgetTester tester, String accountId);
```

`expectOrientationPanel` asserts on `TestIds.orientationPanel` **and** the
complementary state: when hidden it must also find `l10n.myWorkEmptyActiveTitle`
or a non-empty card list, so a spinner or a silently blank body cannot pass as
"hidden". `awaitActivationSettled` pumps until `HomeActivationCubit`'s state is
`hydrated`, bound to `accountId`, and `isSettled` — **every** visibility
assertion below must be preceded by it, or the test races the `undecided` arm.

**Reading persisted state directly.** Several assertions read the port rather
than the UI:

```dart
final prefs = GetIt.I<HomeOrientationPreferencesPort>();
expect(await prefs.isOrientationDismissed(userId: authorId), isTrue);
```

That is deliberate. A Flutter integration test cannot restart the browser
mid-test, so "survives a reload" is not directly observable here — but the write
reaching Drift is, and the read path back out is covered by UNIT 3's repository
test. Revision 2 claimed step 5's navigation proved persistence; it does not.
`goToPath` is `router.navigatePath` (`e2e_test_helpers.dart:206-226`) and
reloads nothing.

**Sequence** (one `testWidgets`, one browser session):

| # | Step | Assertion |
|---|---|---|
| 1 | `launchApp`, `bootstrapFixture`, `logout`, `loginAs(authorEmail)`, `showMyWorkList`, `awaitActivationSettled(authorId)` | panel **visible** — fresh account, zero activity |
| 2 | tap the Inbox nav row | `currentAppUrl()` contains `/home/inbox` |
| 3 | back to the Work tab | panel **visible** again (no state lost) |
| 4 | tap `Got it` | panel **hidden**, ordinary empty state visible |
| 5 | read the port | `isOrientationDismissed(authorId) == true` **and** `isActivated(authorId) == false` — the dismiss write reached Drift and did not falsify activation |
| 6 | `goToPath(kPathSettings)`, back to `/home/work` | panel **hidden** — survives navigation and a rebuilt `_MyWorkListBody` |
| 7 | `openDebugSettings`, `setOrientationOverride(show)`, back to `/home/work` | panel **visible** — override beats the dismiss latch |
| 8 | `setOrientationOverride(hide)`, back | panel **hidden** |
| 9 | `setOrientationOverride(auto)`, `resetFirstRunOrientation`, back | panel **visible** — reset cleared the dismiss latch |
| 10 | `createAndForwardRequest(...)` as the author, return to `/home/work` | `isActivated(authorId) == true` — latched from the live projection (the list is now non-empty, so the panel itself proves nothing here) |
| 11 | `resetFirstRunOrientation`, back to `/home/work`, settle | `isActivated(authorId) == true` again — re-derived from the non-empty projection, proving D3 on this device |
| 12 | `logout`, `loginAs(helperEmail)`, `showMyWorkList`, `awaitActivationSettled(helperId)` | panel **hidden** with an **empty** My Work list |
| 13 | read the port | `isOrientationDismissed(helperId) == false` **and** `isActivated(helperId) == true` — hidden *because activated*, not because the author's latch leaked; proves the keys are per-user |
| 14 | teardown | `setOrientationOverride(auto)` |

Step 12 is the load-bearing one, and revision 2 did not have it. Steps 10–11 sit
behind a non-empty card list, where `cards.isEmpty` (`my_work_screen.dart:423`)
hides the panel regardless of any latch — so they can only be asserted at the
port, which is what they now do. The helper is the one account in the fixture
with activity (a received forward, delivered and verified inside
`createAndForwardRequest`, `e2e_test_helpers.dart:565`) **and** an empty active
My Work list: exactly the shape that separates "hidden because activated" from
"hidden because the list is full".

Step 14 is hygiene, not leak prevention. The runner launches a separate
`flutter drive` per target (`run_client_integration_web_local.sh:152-177`), each
with its own scoped Chrome profile, so IndexedDB — and therefore every latch —
starts empty per file and cannot leak across files. That same fact is what makes
step 1's "fresh account" assertion reliable in the first place. (Revision 2
asserted a shared browser profile; that was wrong.)

**Not covered here (and why):** the unhydrated window (step 1 races it; the
widget test owns it deterministically), a real browser reload, text scaling, and
dark mode.

### 10.4 Manual pass
Local stack, both themes:

1. QA-signup a fresh account → orientation, not "No active work yet".
2. Each nav row → correct tab; Back returns.
3. `Got it` → ordinary empty state; reload → still ordinary.
4. Profile → How Tentura works → sheet with the reopen title/intro.
5. Create one request → reload → orientation never returns, even after
   archiving it.
6. Accept a request invite as a brand-new account → lands on that request with
   the inviter snackbar.
7. 375 px at `textScaleFactor` 2.0 → no overflow, no horizontal scroll.
8. Reduced motion → no crossfade.
9. Debug screen: each segment behaves per §7; status readout tracks the live
   activity count.

---

## 11. Verification gate

Run every line from the **repository root**. Package commands are subshells so
the root-relative scripts still resolve — revision 2's block `cd`-ed into
`packages/client` on line 1 and then invoked `./scripts/...`, which fails.

```bash
(cd packages/client && flutter gen-l10n && dart run build_runner build -d)
./scripts/check-custom-lints.sh packages/client   # baseline: packages/client 32
./scripts/check-custom-lints.sh packages/server   # baseline: packages/server 0
bash scripts/check-user-facing-terminology.sh
(cd packages/client && flutter test)
./scripts/run_client_integration_web_local.sh \
  integration_test/first_run_orientation_test.dart
```

Baselines live in `scripts/custom-lint-baseline.txt` and may only go **down**.
Do not resolve a mismatch by raising them.

---

## 12. Risks

| Risk | Mitigation |
|---|---|
| Orientation flashes for returning users on a cold cache | The `undecided` decision plus UNIT 7's explicit spinner arm; the screen's own loading branch does **not** cover it (§3). |
| Latches load asynchronously and the panel decides before they arrive | `hydrated` gate; generation-tagged reads discarded on rebind (§3, UNIT 4). |
| A dying account's projections write into the freshly bound one | Account-tagged `report*` calls dropped when they do not match `boundAccountId` (UNIT 4). |
| Inbox never resolves → the body spins forever | `inboxFailed` settles the decision as `ordinaryEmpty` — fail closed (§3). |
| Activity observed during an Inbox outage is never latched | Write rule keys on `hasProvenActivity` (per-projection), not `isSettled` (§3). |
| The inviter snackbar is cleared by the new request push | Ownership moved into the listener and emitted after the push completes (§8 step 3). |
| `SliverFillRemaining` overflow on small phones | UNIT 7 switches to `SliverToBoxAdapter`; 375×667 + 2.0 scale test. |
| Debug override leaks into other integration tests or a real session | Device-wide key defaults to `auto`; step 12 teardown resets it; `resetFirstRunState` deliberately does not touch it, so the two knobs stay independent. |
| Forcing the panel visible falsifies activation state | §3 write rule runs under every override; asserted in the cubit test. |
| Panel pushes a new user into request creation before they know anyone | CTA ladder puts Inbox first when anything is waiting; "Find ways to help" is always the secondary. |
| Invite handoff pushes an unreadable request as the very first screen | UNIT 11 verifies degradation before wiring the push. |
| Copy drifts from the landing/native onboarding | The panel *complements* rather than repeats: landing explains the concept, the panel explains navigation. §6 is the single source; do not re-word in code. |
| Local-only latch resets on a new device | Usually harmless — the first projection is non-empty, so the latch re-derives immediately. The exception (an account that deleted all its activity) is documented in D3 and accepted; the projections are current-state, not history. |

---

## 13. Out of scope

- Any new route, tab, or permanent home page.
- Server-side activation/onboarding state.
- Changing `IntroScreen` or `packages/landing/onboarding.js`.
- A full trust/MeritRank legend anywhere new (D5).
- Env-gating the debug settings screen (pre-existing, wider question).
- Progress checklists, streaks, or completion meters — feed-shaped mechanics
  Tentura's product stance rejects.

---

## 14. Review trace (adversarial review, round 1)

Protocol: Adversarial Review (Qiu & Gill 2026, arXiv:2608.18167) — one round.

| Role | Model | Mode |
|---|---|---|
| M (owner/editor) | Claude Opus 5 | this session |
| R (reviewer) | codex — `gpt-6-astra` (Astra GPT-6), `model_reasoning_effort=high` | `-s read-only`, rooted at the repo |
| C (critic) | cursor-agent — `kimi-k3-max` (Kimi K3) | `--mode plan` (read-only) |

**Verdicts.** R: `NEEDS_CHANGES` (8 flags). C: **`AGREE`** — every flag verified
against the code, plus 4 bugs R missed. No `DISAGREE_*` round was needed, so the
inner loop terminated after one exchange and M applied the surviving flags.

### R's flags → resolution

| # | Sev | Flag | Resolution in rev 3 |
|---|---|---|---|
| 1 | P1 | `bindAccount` had no caller; `@singleton` ≠ provided to `BlocSelector`; `_InboxScope` retains `_lastAccountId` through sign-out | UNIT 4 rewritten: `HomeActivationBinder` under the existing `AuthCubit` selector, account-tagged reports with generation-guarded reads, explicit `BlocProvider.value` in both `HomeScreen.wrappedRoute` and `DebugSettingsScreen.wrappedRoute` |
| 2 | P1 | The inviter snackbar is destroyed by `ClearSnackBarsOnPushObserver` when the new request push lands | §8 step 3 rewritten: emission moved into the listener, after the awaited push; `AcceptInviteCubit` stops emitting and sets `showSnackbar: true` |
| 3 | P2 | Projection readiness ≠ preference readiness; latches load async | `hydrated` added to the state and to the show rule; generation-tagged reads (§3, UNIT 4) |
| 4 | P2 | The existing spinner only checks `MyWorkState.isLoading`, so an unresolved Inbox falls through to the empty branch | `OrientationDecision.undecided` + UNIT 7's explicit spinner arm; `inboxFailed` prevents an infinite spinner |
| 5 | P2 | The one-way latch over-promised: both-projection write rule loses a My-Work-only observation, and current-state projections cannot prove history | Write rule keyed on `hasProvenActivity`; D3 now states the fresh-device limit honestly |
| 6 | P2 | `activityCount` double-counted drafts (`draftCount` counts inside `nonArchivedCards`) | Disjoint `activityCount`; `draftCount` kept for the debug readout only (§3, §6.3) |
| 7 | P2 | The integration sequence proved neither persistence nor activation; steps sat behind a non-empty list | §10.3 rewritten: port-level assertions, the helper-account step (empty active list + activated), per-user key isolation |
| 8 | P3 | The verification block breaks on `cd` when run literally | §11 uses subshells |

### C's missed bugs → resolution

| # | Bug | Resolution |
|---|---|---|
| 9 | Plan said bump from `7.2.1`; `pubspec.yaml:5` is `7.2.2` — a literal find-replace matches nothing | UNIT 13 corrected, with an instruction to re-read rather than trust the number |
| 10 | Plan said lint baseline "client 115"; `scripts/custom-lint-baseline.txt:19` says `packages/client 32` | §11 corrected; server baseline added |
| 11 | "Show Intro Again" is behind `if (!kIsWeb)`, so a literal executor would hide the Settings reopen entry on web — the platform this issue targets | UNIT 8 now requires placement **outside** the guard |
| 12 | §10.3 claimed the runner reuses one browser profile; it runs a separate `flutter drive` per target with its own scoped Chrome profile | Step 14 rationale corrected; the fresh-profile fact now backs step 1 instead |

### Not adopted

Nothing. Every flag was either evidence-backed by both models or independently
re-verified by M against the repository before editing.
