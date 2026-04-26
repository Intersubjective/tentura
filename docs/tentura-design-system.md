# Tentura design system (Flutter client)

Operational, minimal, record-list UI for `packages/client`. Not a social feed, marketplace, or default Material “chunky” chrome.

## Source of truth in code

| Area | Location |
|------|----------|
| Theme + `ThemeExtension` | [`tentura_theme.dart`](../packages/client/lib/design_system/tentura_theme.dart), [`tentura_tokens.dart`](../packages/client/lib/design_system/tentura_tokens.dart) |
| Text styles | [`tentura_text.dart`](../packages/client/lib/design_system/tentura_text.dart) |
| Window breakpoints | [`tentura_window_class.dart`](../packages/client/lib/design_system/tentura_window_class.dart), [`tentura_responsive_scope.dart`](../packages/client/lib/design_system/tentura_responsive_scope.dart) |
| Components | [`packages/client/lib/design_system/components/`](../packages/client/lib/design_system/components/) |
| Barrel export | [`tentura_design_system.dart`](../packages/client/lib/design_system/tentura_design_system.dart) |
| App wiring | [`packages/client/lib/app/app.dart`](../packages/client/lib/app/app.dart) uses `TenturaTheme.light()` / `dark()` + `TenturaResponsiveScope` |
| Theme compatibility | [`packages/client/lib/ui/theme.dart`](../packages/client/lib/ui/theme.dart) — `createAppTheme` for tests/previews |

Access tokens: `import 'package:tentura/design_system/tentura_design_system.dart';` then `context.tt` ([`TenturaThemeX`](../packages/client/lib/design_system/tentura_tokens.dart)).

## Type scale (semantic)

Primary font: **Inter** (bundled assets). Use `TenturaText.*` helpers and `ThemeData.textTheme` roles — **never** inline `fontSize:` in `features/**` or `ui/**` (enforced by `no_inline_font_size` where enabled).

| Role                          | TenturaText / TextTheme                                                | Size | Weight | Line height           |
| ----------------------------- | ---------------------------------------------------------------------- | ---- | ------ | --------------------- |
| Card / beacon title           | `titleMedium`                                                          | 18   | 700    | 1.22                  |
| Large title                   | `titleLarge`                                                           | 20   | 700    | 1.22                  |
| Section / small title         | `titleSmall`                                                           | 15   | 600    | 1.25                  |
| Body                          | `bodyMedium`                                                           | 15   | 400    | 1.40                  |
| Body large                    | `bodyLarge`                                                            | 16   | 400    | 1.40                  |
| Metadata / status / secondary | `bodySmall`                                                            | 13   | 500    | 1.35                  |
| Primary actions / buttons     | `labelLarge`                                                           | 15   | 700    | 1.20                  |
| Chips / secondary labels      | `labelMedium`                                                          | 13   | 600    | 1.20                  |
| Bottom nav labels             | `TenturaText.navLabel` (`NavigationBarTheme` in app theme)             | 12.5 | 600    | 1.20                  |
| Type / offer labels           | `TenturaText.typeLabel` (Inter; letter-spaced, not a second font)         | 13   | 700    | 1.35 (letterSpacing 0.3) |
| Tab labels                    | `TenturaText.tabLabel` (`TenturaUnderlineTabs`)                        | 13   | 600    | 1.20                  |
| Command emphasis              | `TenturaText.command`                                                  | 15   | 700    | 1.20                  |

`command`, `typeLabel`, `tabLabel`, and `navLabel` are **TenturaText** helpers only (not separate `TextTheme` slots). All other rows map to both `TenturaText.*` and `ThemeData.textTheme` via `TenturaTheme.baseTextTheme` in `tentura_theme.dart`.

For **tabular numerals** (timers, counts): `TenturaText.withTabular(style)`.

## Breakpoints & WindowClass

Width drives layout density, **not** font size:


| WindowClass | Width (logical px) | Behavior |
|-------------|-------------------|----------|
| `compact` | &lt; 600 | Phone; smallest density tokens |
| `regular` | 600 ≤ *w* &lt; 840 | Tablet / narrow desktop; medium tokens (same class at width 839.5, etc.) |
| `expanded` | ≥ 840 | Wide desktop; largest density tokens, `contentMaxWidth` cap |


`TenturaResponsiveScope` selects `TenturaTokens` preset per class. **TextTheme sizes stay identical** across classes; only padding, gaps, icon sizes, avatar sizes, button heights, app bar / bottom nav heights, and max content width change.

## Hard floors

- **Metadata / secondary readable text:** minimum **13** logical px (`bodySmall`).
- **Body:** minimum **15** (`bodyMedium` / `body`).
- **Action labels:** minimum **15** (`labelLarge`).
- **Bottom nav labels:** **12.5** is the **only** allowed exception below 13.
- **Banned** in `packages/client/lib/features/**` and `packages/client/lib/ui/**`: literal font sizes **8, 10, 11, 12** (use semantic roles instead).

Do **not** scale the whole UI proportionally from screen width (no `fontSize: 14 * (width / 390)`).

**Compact width:** reflow actions (e.g. second row for tertiary) and use ellipsis on tabs — do **not** visually shrink tab or action text with `FittedBox` / proportional font hacks.

## Beacon detail — type hierarchy

On **Beacon view** (`features/beacon_view`), keep a clear ladder:

| Element | Role |
|--------|------|
| App bar title ([`BeaconViewScreen`](../packages/client/lib/features/beacon_view/ui/screen/beacon_view_screen.dart)) | `titleLarge` (20 / 700) |
| Beacon title (header) | `titleMedium` (18 / 700) — pass `titleStyle` into [`BeaconCardHeaderRow`](../packages/client/lib/ui/widget/beacon_card_primitives.dart) from the detail screen only; **list cards** keep default `titleSmall`. |
| Overview foldable section titles | `titleSmall` (15 / 600) |
| Overview coordination **collapsed** summary (accent line under section title) | `TenturaText.status` (13 / 500) — same scale as status strip; other foldable section summaries (need / description preview) stay `TenturaText.body` (15) muted |
| Overview coordination **expanded** diagnosis title (e.g. need-different-skill label) | `TenturaText.typeLabel` (13 / 700) — aligns with commitment coordination labels |
| Overview / Coordination prose (diagnosis body, author update text, need excerpt) | `bodyMedium` (15 / 400) |
| Metadata (counts under headers, timestamps, status strip) | `bodySmall` / `TenturaText.status` (13) |
| Commitment tile display name | `titleSmall` — below the beacon title, above body message |
| Commitments summary heading | `titleSmall` — matches overview sections |
| Commitments tab summary subline (useful / need coordination counts) | `bodySmall` (13) with semantic colors — matches overview “useful · coordination” meta |
| Activity tab section headers | `titleSmall` — same weight as other section titles (no extra bold bump) |
| Primary / secondary Material buttons (incl. [`CardTriageActionRow`](../packages/client/lib/ui/widget/card_triage_action_row.dart), owner CTAs in [`BeaconPrimaryCtaBar`](../packages/client/lib/features/beacon_view/ui/widget/beacon_primary_cta_bar.dart)) | `labelLarge` (15 / 700) via `theme.textTheme.labelLarge` |

## Forward Beacon picker — type hierarchy

On **Forward Beacon** (`features/forward` — `ForwardBeaconPage`, `ForwardRecipientRow`, `ForwardScopeLinks`, `ForwardBottomComposer`), keep a compact list hierarchy; do not compete with `titleMedium` on every row.

| Element | Role |
|--------|------|
| Screen title (top bar) | `TenturaText.title` / `titleMedium` (18 / 700) — same as other modal-style titles |
| Subtitle (beacon title · lifecycle) | `bodySmall` muted |
| Context strip (author · context · dates) | `bodySmall` + `metadataAvatarSize` / token gaps from `context.tt` |
| Scope tabs (best / unseen / involved) | `TenturaText.tabLabel` (13) for label; `bodySmall` or tabular `bodySmall` for `/count`; **ellipsis** when tight — **no `FittedBox` scale-down** |
| Recipient display name | `titleSmall` (15 / 600), not `title` — use `SelfUserHighlight.nameStyle` with `TenturaText.titleSmall` as base |
| Presence + involvement line | `bodySmall` for presence; `TenturaStatusText` + `TenturaTone` for forward-path status (plain text, not chips) |
| Personalized note action (add/hide) | **Icon only** (`add_comment_outlined` / `expand_less`), **immediately left of** the row checkbox, with the same strings as **tooltip** when the row is selected |
| Per-recipient + shared note fields | Same tokenized `InputDecoration` (surface, border, `TenturaRadii.cardDense`, `TenturaText.body` for input) |
| Primary Forward CTA | `TenturaText.command` / `OutlinedButton` with height ≥ `context.tt.buttonHeight` |
| List row avatars + checkbox hit targets | Avatar size from `context.tt` (`cardAvatarSize` or `avatarSize`); checkbox visual stays small but wrap in at least **44×44** logical px tap target |

## No global text scaler override

Do **not** wrap the app in `MediaQuery.copyWith(textScaler: TextScaler.noScaling)`. Let Flutter apply system / accessibility text scaling. Design dense cards so they remain usable at **text scale ~1.3** (wrap rows, allow soft wrap, reduce padding via tokens if needed — never shrink semantic type below floors).

## Principles

1. **Information first** — quiet surfaces; no ornamental gradients, heavy shadows, or badge clouds.
2. **Statuses = plain colored text** — semantic color on **`bodySmall`**-scale type (see [`TenturaText.status`](../packages/client/lib/design_system/tentura_text.dart)); no `Chip` / pill backgrounds for state on operational surfaces.
3. **Flat record cards** — white surface, 1px border, radius from tokens, padding/gap from `context.tt`, shadow minimal or off.
4. **Hairlines** — use [`TenturaHairlineDivider`](../packages/client/lib/design_system/components/tentura_hairline_divider.dart), not nested cards.
5. **Tabs** — underline row with 2px active indicator ([`TenturaUnderlineTabs`](../packages/client/lib/design_system/components/tentura_underline_tabs.dart)), not `SegmentedButton` on beacon detail. Labels stay at **13px** logical size; use **ellipsis** when width is tight, not scaled-down paint size. Vertical padding follows **`context.tt.rowGap`** (density), not a fixed px hack.
6. **Actions** — [`TenturaTextAction`](../packages/client/lib/design_system/components/tentura_text_action.dart) / [`TenturaCommandButton`](../packages/client/lib/design_system/components/tentura_command_button.dart); avoid filled buttons inside dense cards unless truly primary.
7. **Avatars** — size from `context.tt` (`avatarSize`, `metadataAvatarSize`, `cardAvatarSize`), circle + thin border ([`TenturaAvatar`](../packages/client/lib/design_system/components/tentura_avatar.dart)).
8. **A11y** — min tap targets (e.g. button height from tokens); respect system text scaling.

## Token summary (light)


| Token                                                              | Role               |
| ------------------------------------------------------------------ | ------------------ |
| `bg`                                                               | `#F8FAFC` scaffold |
| `surface`                                                          | `#FFFFFF` cards    |
| `border` / `borderSubtle`                                          | hairlines          |
| `text` / `textMuted` / `textFaint`                                 | hierarchy          |
| `info` (sky) / `good` (emerald) / `warn` (amber) / `danger` (rose) | semantics          |


## Components (use these)

- `TenturaTechCard` / `TenturaTechCardStatic`
- `TenturaStatusText`, `TenturaMetaText`, `TenturaTypeLabel`
- `TenturaTextAction`, `TenturaCommandButton`
- `TenturaUnderlineTabs`, `TenturaAvatar`, `TenturaHairlineDivider`

## Do / don’t (operational areas)


| Do                                               | Don’t                                                                                                                      |
| ------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------- |
| `context.tt` + `TenturaText` / `theme.textTheme` | `Color(0x…)`, `Colors.*` (except e.g. `Colors.transparent` where needed) in `beacon_view`, `my_work`, `inbox` feature code |
| `TenturaTechCard` for record rows                | Ad-hoc `TextStyle(fontSize: …)` in those folders                                                                           |
| Plain text status                                | `Chip` / `SegmentedButton` in `beacon_view` `widget/` + `screen/`                                                          |


Custom lint: `no_operational_raw_color`, `no_operational_raw_text_style`, `no_operational_pill_widgets_in_beacon_view` in [`packages/tentura_lints`](../packages/tentura_lints); plus `no_inline_font_size` for `features/**` and `ui/**` (allow-listed paths in rule).

## Web viewport

`packages/client/web/index.html` must use `width=device-width, initial-scale=1.0`, `viewport-fit=cover`. Do **not** set `maximum-scale=1` or `user-scalable=no` (hurts accessibility and zoom).

If the design doc and code disagree, update the doc after confirming product intent.