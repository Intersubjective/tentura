---
name: material-3-flutter
description: >
  Build and review Tentura's Flutter client UI as a Material Design 3 +
  design-system specialist. Activate for ANY work touching widgets, layout,
  theming, colors, typography, spacing, or shared components under
  packages/client (features/**/ui, ui/**, design_system/**). Route all styling
  through the existing design system — never invent raw visual constants in
  feature UI.
---

# Material 3 + Tentura design system (Flutter client)

Tentura already ships a Material 3 theme and a design system. Your job is to
**use it**, not to redesign it. The app theme (`TenturaTheme.light/dark` in
`packages/client/lib/design_system/tentura_theme.dart`) is built with
`useMaterial3: true` from `ColorScheme.fromSeed`, plus a `TenturaTokens`
`ThemeExtension` for operational density.

Read `docs/tentura-design-system.md` before non-trivial UI changes. For
typography work also read `docs/typography-overhaul-journal.md`.

## Core tools (import the barrel)

```dart
import 'package:tentura/design_system/tentura_design_system.dart';
```

- **Colors** → semantic `ColorScheme` roles (`Theme.of(context).colorScheme.*`:
  `primary`/`onPrimary`, `surface`, `onSurfaceVariant`, `outline`, `error`, …)
  and the `context.tt` tokens (`tt.info/good/warn/danger`, `tt.border`,
  `tt.textMuted`, …). Pair `onX` foreground with its `X` background.
- **Typography** → `TenturaText.*` (e.g. `TenturaText.title`, `bodySmall`,
  `status`, `typeLabel`) or `Theme.of(context).textTheme.*`. Never a bare
  `fontSize:`.
- **Spacing / sizes** → `context.tt` density tokens: `cardPadding`, `cardGap`,
  `rowGap`, `sectionGap`, `iconTextGap`, `avatarTextGap`, `tightGap`,
  `screenHPadding`, `iconSize`, `avatarSize`, `buttonHeight`. These scale by
  `WindowClass` (compact / regular / expanded) — text sizes do not.
- **Radius** → `tt.cardRadius`, `tt.buttonRadius`, or `TenturaRadii.*`.
- **Components** → prefer the existing `Tentura*` widgets in
  `design_system/components/`: `TenturaAvatar`, `TenturaCommandButton`,
  `TenturaCountBadge`, `TenturaHairlineDivider`, `TenturaStatusText`,
  `TenturaMetaText`, `TenturaTypeLabel`, `TenturaTextAction`, `TenturaTechCard`,
  `TenturaUnderlineTabs`.

## When creating UI

1. Reach for a `Tentura*` component first; then a themed Material 3 component
   (`FilledButton`, `OutlinedButton`, `NavigationBar`, `Card`, `ListTile`,
   `Chip`, `Badge`) — they are already styled by `TenturaTheme`. Do **not**
   hand-roll a `Container` with manual decoration when a themed widget exists.
2. Source every color from a `ColorScheme` role or `context.tt`; every gap /
   padding / radius from a token; every text style from `TenturaText.*` /
   `textTheme`.
3. Keep tap targets ≥ 48dp, honor text scaling (never set
   `TextScaler.noScaling` app-wide), and keep contrast ≥ 4.5:1.
4. Use `const` constructors and decompose large `build` methods into small
   private widgets.

## When reviewing UI

- Color pairing correct (`onX` on `X`); no arbitrary colors.
- Type uses the right scale role; no inline `fontSize`.
- Spacing / radius come from tokens, not magic numbers.
- Material 3 component used instead of a bespoke equivalent.
- Tap targets, semantics labels, and text-scale behavior are intact.
- Beacon detail surfaces: no `Chip` / `SegmentedButton` / pill-style status —
  use `TenturaStatusText` / `TenturaUnderlineTabs`.

## When refactoring UI

- Replace literals with the nearest existing token. Minor visual deltas are
  acceptable if they don't change layout and move toward the MD3 / token scale.
- **If no token fits, add it to the design system first** (`tentura_spacing.dart`
  + `tentura_tokens.dart`, or `tentura_radii.dart`), then use it. Never inline a
  raw constant to "get it done".
- Migrate stray Material 2 patterns only when trivially safe; otherwise leave
  them and note it.

## Forbidden patterns (enforced by `tentura_lints` via `dart analyze`)

| Pattern | Lint | Scope |
|---|---|---|
| `Color(0x…)`, `Colors.*` (except `Colors.transparent`) | `no_operational_raw_color` | beacon_view / my_work / inbox |
| `TextStyle(…)` literal | `no_operational_raw_text_style` | beacon_view / my_work / inbox |
| inline `fontSize:` | `no_inline_font_size` | features/** , ui/** |
| `EdgeInsets.*(<number>)` | `no_raw_edge_insets` | features/** , ui/** |
| `BorderRadius`/`Radius.*(<number>)` | `no_raw_border_radius` | features/** , ui/** |
| `Chip`/`SegmentedButton`/pill status on beacon detail | `no_operational_pill_widgets_in_beacon_view` | beacon_view |

Design-system files and the package's own `test/` tree are exempt.

## Required checks before final answer

1. `cd packages/client && flutter analyze --no-fatal-warnings --no-fatal-infos`
   — no new violations in files you touched.
2. `cd packages/client && flutter test` — green.
3. For a new/changed **reusable** component, add or update a golden/widget test
   (pattern: `test/features/inbox/inbox_item_tile_golden_test.dart`). Regenerate
   intentionally with `flutter test --update-goldens <path>` and eyeball the PNG.
4. If you added a token or lint, run `cd packages/tentura_lints && dart test`.
