# Tentura design system (Flutter client)

Operational, minimal, record-list UI for `packages/client`. Not a social feed, marketplace, or default Material “chunky” chrome.

## Source of truth in code

| Area | Location |
|------|----------|
| Theme + `ThemeExtension` | [`packages/client/lib/design_system/tentura_theme.dart`](../packages/client/lib/design_system/tentura_theme.dart), [`tentura_tokens.dart`](../packages/client/lib/design_system/tentura_tokens.dart) |
| Text styles | [`tentura_text.dart`](../packages/client/lib/design_system/tentura_text.dart) |
| Components | [`packages/client/lib/design_system/components/`](../packages/client/lib/design_system/components/) |
| Barrel export | [`tentura_design_system.dart`](../packages/client/lib/design_system/tentura_design_system.dart) |
| App wiring | [`packages/client/lib/app/app.dart`](../packages/client/lib/app/app.dart) uses `TenturaTheme.light()` / `dark()` |
| Theme compatibility | [`packages/client/lib/ui/theme.dart`](../packages/client/lib/ui/theme.dart) — `createAppTheme` for tests/previews |

Access tokens: `import 'package:tentura/design_system/tentura_design_system.dart';` then `context.tt` ([`TenturaThemeX`](../packages/client/lib/design_system/tentura_tokens.dart)).

## Principles

1. **Information first** — quiet surfaces; no ornamental gradients, heavy shadows, or badge clouds.
2. **Statuses = plain colored text** — 10pt semibold Roboto, semantic color (see [`TenturaText.status`](../packages/client/lib/design_system/tentura_text.dart)); no `Chip` / pill backgrounds for state on operational surfaces.
3. **Flat record cards** — white surface, 1px border, radius 8–10, padding 12, gap 10–12, shadow minimal or off.
4. **Hairlines** — use [`TenturaHairlineDivider`](../packages/client/lib/design_system/components/tentura_hairline_divider.dart), not nested cards.
5. **Tabs** — underline row with 2px active indicator ([`TenturaUnderlineTabs`](../packages/client/lib/design_system/components/tentura_underline_tabs.dart)), not `SegmentedButton` on beacon detail.
6. **Actions** — [`TenturaTextAction`](../packages/client/lib/design_system/components/tentura_text_action.dart) / [`TenturaCommandButton`](../packages/client/lib/design_system/components/tentura_command_button.dart); avoid filled buttons inside dense cards unless truly primary.
7. **Avatars** — 32px circle + thin border ([`TenturaAvatar`](../packages/client/lib/design_system/components/tentura_avatar.dart)).
8. **A11y** — keep min tap targets; `TextScaler.noScaling` in app is a known tradeoff to revisit for scaling.

## Token summary (light)

| Token | Role |
|-------|------|
| `bg` | `#F8FAFC` scaffold |
| `surface` | `#FFFFFF` cards |
| `border` / `borderSubtle` | hairlines |
| `text` / `textMuted` / `textFaint` | hierarchy |
| `info` (sky) / `good` (emerald) / `warn` (amber) / `danger` (rose) | semantics |

## Components (use these)

- `TenturaTechCard` / `TenturaTechCardStatic`
- `TenturaStatusText`, `TenturaMetaText`, `TenturaTypeLabel`
- `TenturaTextAction`, `TenturaCommandButton`
- `TenturaUnderlineTabs`, `TenturaAvatar`, `TenturaHairlineDivider`

## Do / don’t (operational areas)

| Do | Don’t |
|----|--------|
| `context.tt` + `TenturaText` | `Color(0x…)`, `Colors.*` (except e.g. `Colors.transparent` where needed) in `beacon_view`, `my_work`, `inbox` feature code |
| `TenturaTechCard` for record rows | Ad-hoc `TextStyle(` in those folders |
| Plain text status | `Chip` / `SegmentedButton` in `beacon_view` `widget/` + `screen/` |

Custom lint: `no_operational_raw_color`, `no_operational_raw_text_style`, `no_operational_pill_widgets_in_beacon_view` in [`packages/tentura_lints`](../packages/tentura_lints).
