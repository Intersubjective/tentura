# Tentura design system (Flutter client)

Operational, minimal, record-list UI for `packages/client`. Not a social feed, marketplace, or default Material “chunky” chrome.

## Source of truth in code

| Area | Location |
|------|----------|
| Theme + `ThemeExtension` | [`packages/client/lib/design_system/tentura_theme.dart`](../packages/client/lib/design_system/tentura_theme.dart), [`tentura_tokens.dart`](../packages/client/lib/design_system/tentura_tokens.dart) |
| Text styles | [`tentura_text.dart`](../packages/client/lib/design_system/tentura_text.dart) |
| Window breakpoints | [`tentura_window_class.dart`](../packages/client/lib/design_system/tentura_window_class.dart), [`tentura_responsive_scope.dart`](../packages/client/lib/design_system/tentura_responsive_scope.dart) |
| Components | [`packages/client/lib/design_system/components/`](../packages/client/lib/design_system/components/) |
| Barrel export | [`tentura_design_system.dart`](../packages/client/lib/design_system/tentura_design_system.dart) |
| App wiring | [`packages/client/lib/app/app.dart`](../packages/client/lib/app/app.dart) uses `TenturaTheme.light()` / `dark()` + `TenturaResponsiveScope` |
| Theme compatibility | [`packages/client/lib/ui/theme.dart`](../packages/client/lib/ui/theme.dart) — `createAppTheme` for tests/previews |

Access tokens: `import 'package:tentura/design_system/tentura_design_system.dart';` then `context.tt` ([`TenturaThemeX`](../packages/client/lib/design_system/tentura_tokens.dart)).

## Type scale (semantic)

Primary font: **Inter** (bundled assets). Use `TenturaText.*` helpers and `ThemeData.textTheme` roles — **never** inline `fontSize:` in `features/**` or `ui/**` (enforced by `no_inline_font_size` where enabled).

| Role | TenturaText / TextTheme | Size | Weight | Line height |
|------|-------------------------|------|--------|-------------|
| Card / beacon title | `titleMedium` | 18 | 700 | 1.22 |
| Large title | `titleLarge` | 20 | 700 | 1.22 |
| Section / small title | `titleSmall` | 15 | 600 | 1.25 |
| Body | `bodyMedium` | 15 | 400 | 1.40 |
| Body large | `bodyLarge` | 16 | 400 | 1.40 |
| Metadata / status / secondary | `bodySmall` | 13 | 500 | 1.35 |
| Primary actions / buttons | `labelLarge` | 15 | 700 | 1.20 |
| Chips / secondary labels | `labelMedium` | 13 | 600 | 1.20 |
| Bottom nav labels | `navLabel` (via `TenturaText.navLabel` or `labelMedium` tuned for nav) | 12.5 | 600 | 1.20 |
| Type / mono-like labels | `typeLabel` | 13 | 700 | — (letterSpacing 0.3) |
| Tab labels | `tabLabel` | 13 | 600 | 1.20 |
| Command emphasis | `command` | 15 | 700 | 1.20 |

For **tabular numerals** (timers, counts): `TenturaText.withTabular(style)`.

## Breakpoints & WindowClass

Width drives layout density, **not** font size:

| WindowClass | Width (logical px) | Behavior |
|-------------|-------------------|----------|
| `compact` | &lt; 600 | Phone; smallest density tokens |
| `regular` | 600–839 | Tablet / narrow desktop; medium tokens |
| `expanded` | ≥ 840 | Wide desktop; largest density tokens, `contentMaxWidth` cap |

`TenturaResponsiveScope` selects `TenturaTokens` preset per class. **TextTheme sizes stay identical** across classes; only padding, gaps, icon sizes, avatar sizes, button heights, app bar / bottom nav heights, and max content width change.

## Hard floors

- **Metadata / secondary readable text:** minimum **13** logical px (`bodySmall`).
- **Body:** minimum **15** (`bodyMedium` / `body`).
- **Action labels:** minimum **15** (`labelLarge`).
- **Bottom nav labels:** **12.5** is the **only** allowed exception below 13.
- **Banned** in `packages/client/lib/features/**` and `packages/client/lib/ui/**`: literal font sizes **8, 10, 11, 12** (use semantic roles instead).

Do **not** scale the whole UI proportionally from screen width (no `fontSize: 14 * (width / 390)`).

## No global text scaler override

Do **not** wrap the app in `MediaQuery.copyWith(textScaler: TextScaler.noScaling)`. Let Flutter apply system / accessibility text scaling. Design dense cards so they remain usable at **text scale ~1.3** (wrap rows, allow soft wrap, reduce padding via tokens if needed — never shrink semantic type below floors).

## Principles

1. **Information first** — quiet surfaces; no ornamental gradients, heavy shadows, or badge clouds.
2. **Statuses = plain colored text** — semantic color on **`bodySmall`**-scale type (see [`TenturaText.status`](../packages/client/lib/design_system/tentura_text.dart)); no `Chip` / pill backgrounds for state on operational surfaces.
3. **Flat record cards** — white surface, 1px border, radius from tokens, padding/gap from `context.tt`, shadow minimal or off.
4. **Hairlines** — use [`TenturaHairlineDivider`](../packages/client/lib/design_system/components/tentura_hairline_divider.dart), not nested cards.
5. **Tabs** — underline row with 2px active indicator ([`TenturaUnderlineTabs`](../packages/client/lib/design_system/components/tentura_underline_tabs.dart)), not `SegmentedButton` on beacon detail.
6. **Actions** — [`TenturaTextAction`](../packages/client/lib/design_system/components/tentura_text_action.dart) / [`TenturaCommandButton`](../packages/client/lib/design_system/components/tentura_command_button.dart); avoid filled buttons inside dense cards unless truly primary.
7. **Avatars** — size from `context.tt` (`avatarSize`, `metadataAvatarSize`, `cardAvatarSize`), circle + thin border ([`TenturaAvatar`](../packages/client/lib/design_system/components/tentura_avatar.dart)).
8. **A11y** — min tap targets (e.g. button height from tokens); respect system text scaling.

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
| `context.tt` + `TenturaText` / `theme.textTheme` | `Color(0x…)`, `Colors.*` (except e.g. `Colors.transparent` where needed) in `beacon_view`, `my_work`, `inbox` feature code |
| `TenturaTechCard` for record rows | Ad-hoc `TextStyle(fontSize: …)` in those folders |
| Plain text status | `Chip` / `SegmentedButton` in `beacon_view` `widget/` + `screen/` |

Custom lint: `no_operational_raw_color`, `no_operational_raw_text_style`, `no_operational_pill_widgets_in_beacon_view` in [`packages/tentura_lints`](../packages/tentura_lints); plus `no_inline_font_size` for `features/**` and `ui/**` (allow-listed paths in rule).

## Web viewport

`packages/client/web/index.html` must use `width=device-width, initial-scale=1.0`, `viewport-fit=cover`. Do **not** set `maximum-scale=1` or `user-scalable=no` (hurts accessibility and zoom).

If the design doc and code disagree, update the doc after confirming product intent.
