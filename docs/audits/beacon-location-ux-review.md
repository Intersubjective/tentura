---
status: done
kind: review
---
# UI/UX review: beacon location feature vs. the stated goal

Status: **review only, nothing implemented.**

Goal restated: (A) authors can easily select a concrete address/point on a map; (B) other users see a short human-readable address on the beacon card; (C) tapping it shows the map; (D) users can easily copy the address to route in e.g. Google Maps.

This reviews the current implementation against each of the four, and how much of the gap the Nominatim proxy plan (`docs/archive/plans/reverse-geocoding-server-proxy-plan.md`) actually closes.

## A. Author picking a concrete address — partial, imprecise

`ChooseLocationDialog` (`packages/client/lib/features/geo/ui/dialog/choose_location_dialog.dart`) is **tap-on-map only**:
- No address search / autocomplete box — an author has to already know roughly where on the world map to pan to, then tap. There's no way to type "123 Main St" and jump there.
- `maxZoom: 12` (`choose_location_dialog.dart:61`) caps zoom well below building-level (OSM tiles go to ~19). At zoom 12 a tap can easily land a block or more off — that's in tension with "concrete... points."
- The tap **commits immediately**: `onTap` resolves the place and calls `Navigator.of(context).pop(location)` in the same callback (`choose_location_dialog.dart:67-72`) — no "confirm / drag to adjust" step, no preview of the resolved address before committing. A mis-tap is only fixable by reopening the whole dialog.
- It does quietly re-center on the author's own location if known (`myCoordinates`, `onMapReady`, lines 73-85) — that part is a reasonable default, no complaint there.

The Nominatim plan does **not** address any of this — it only changes what happens *after* a tap (reverse-geocoding the point), not how the point gets picked. Search/autocomplete and a confirm step are the actual levers for "easily select a concrete address."

## B. Short human-readable address on the beacon card — mostly missing today, and only partly fixed by the proxy plan

`_LocationMeta` (`packages/client/lib/ui/widget/beacon_compact_metadata_strip.dart:333-372`):
```dart
final useStaticLabel = kIsWeb || isDesktopPlatform;
final label = useStaticLabel
    ? Text(l10n.beaconCardLocationSet, ...)   // "Location set" — no address
    : _CompactPlaceNameText(coords: coords, style: baseStyle);
```
- **Web and desktop show no address at all** — just a static "Location set" string. This is the same platform split the reverse-geocoding plan targets, so fixing `GeoRepository` server-side does make it possible to remove `useStaticLabel` and resolve on every platform.
- Even where it does resolve (`_CompactPlaceNameText`, lines 374-392), the label is `place?.displayLocality ?? coords.toString()` — **city name only**, e.g. "Paris", never a street. Nothing in the current card path renders a street address, so even after the proxy adds `road` to `Place` server-side, **this card widget needs its own follow-up change** (swap `displayLocality` for a short "`road, locality`"-style formatter) or goal B is still not met on the card.

So: closing goal B needs the server-side proxy (for web/desktop) **and** a client-side change to what string the card actually renders. The current plan's step 9 only adds `road` to the entity — it doesn't yet say the card should use it. Worth adding explicitly.

## C. Tap → see the map — works, but reuses the editable picker as a "viewer," which is a real bug

`beacon_definition_body.dart:88-91`:
```dart
onPressed: () => ChooseLocationDialog.show(context, center: beacon.coordinates),
```
This opens the **same** full-screen, tap-to-select dialog used for authoring, and just discards the returned `Location?`. Two concrete problems:
- The dialog's `AppBar` title is still `_l10n.tapToChooseLocation` ("tap to choose location") even when opened by a *viewer* who has no location to choose — it's telling someone reading a beacon "tap to choose a location," and their tap silently does nothing. That reads as broken, not read-only.
- It's also inconsistent per-platform: `beacon_definition_body.dart:82` checks only `kIsWeb` for the static-label fallback, while the card (`beacon_compact_metadata_strip.dart:348`) checks `kIsWeb || isDesktopPlatform` — desktop gets a resolved `PlaceNameText` button label in one place and not the other, for no apparent reason.

This is unrelated to the geocoding backend — it's a mode bug (no read-only variant of the map dialog) that should be fixed regardless of which geocoding provider you land on. Minimal fix: `ChooseLocationDialog` should take a `readOnly`/`interactive: false` flag that disables `onTap` and swaps the title to something like "Location" when opened from a viewer context.

## D. Copy the address to route in Google Maps — doesn't exist, and doesn't actually need to wait on the proxy

There is currently **no copy affordance anywhere near location** in the app, despite the app already having a consistent copy pattern elsewhere:
- `share_code_dialog.dart:91-93` — "Copy to Clipboard" action button.
- `fact_actions_sheet.dart:95-109` — `ListTile` with `Icons.copy_outlined`, `Clipboard.setData`, then a confirmation snackbar.

Two things worth separating here, because they have different dependencies:
1. **Copying a human-readable address string** (e.g. "Rue de Rivoli, Paris") — this *does* depend on the reverse-geocoding proxy, since that's the only source of a street-level string.
2. **"Plan a route" via Google Maps** doesn't actually require the address text at all — `beacon.coordinates` (lat/long) is already available on every beacon, proxy or not. A `geo:` URI on mobile or a `https://www.google.com/maps/search/?api=1&query=<lat>,<long>` link on web/desktop opens Maps at the exact point *today*, with zero dependency on geocoding quality, and is strictly better than copy-paste (one tap vs. copy → switch app → paste → search). Coordinates are also immune to Nominatim ever mis-resolving a street name.

Recommendation: ship a "**directions / open in Maps**" action (deep link from raw coordinates) as the primary D-goal fix — it can land independently of the geocoding proxy, this week if you want. Add "copy address text" as a secondary action once the proxy makes a real address string available; add "copy coordinates" too, since that's the most robust paste-target for any routing app, not just Google Maps.

## Design-system constraints on the fix

Per the `material-3-flutter` skill: **beacon detail/view surfaces are lint-forbidden from using `Chip`/`SegmentedButton`/pill-style widgets** (`no_operational_pill_widgets_in_beacon_view`). So:
- Do **not** implement the address as a chip/pill on `beacon_definition_body.dart` or the card. Keep the existing `TextButton.icon` / `BeaconCardMetaItem` row pattern, or add adjacent `IconButton`s (copy, directions) using themed Material 3 icon buttons — matching the `fact_actions_sheet.dart` `ListTile` + `Icons.copy_outlined` pattern for the "more actions" case (e.g. long-press or a small overflow next to the location row opening a small action sheet with "Copy address / Copy coordinates / Open in Maps").
- Tokens: spacing from `context.tt` (`iconTextGap`, `rowGap`), icon from `TenturaIcons.location`, text from `TenturaText.*`/`textTheme` — no literals.
- No existing "address chip" component in `design_system/` — none needed given the pill ban; reuse `BeaconCardMetaItem` (card) and the existing `TextButton.icon` row (detail view).

## Priority / sequencing recommendation

1. **C-bug fix (read-only map dialog)** — small, decoupled from everything else, currently actively misleading viewers. Do this regardless of the rest.
2. **D — "Open in Maps" deep link from coordinates** — small, immediately valuable, no backend dependency. Ship before or alongside the proxy.
3. **Server-side Nominatim proxy** (existing plan) — required for B (web/desktop address resolution) and for a real street string to power "copy address."
4. **A — address search/autocomplete + confirm-before-commit in `ChooseLocationDialog`** — the biggest single UX gap for authors, but the largest chunk of new work (needs a forward-geocoding search box, likely the same Nominatim `/search` endpoint, plus a redesigned picker flow: search → drag pin → confirm). Worth its own follow-up plan once the reverse-geocoding proxy (which most of the plumbing — port, service, rate gate — can be shared with) is in place.
5. **B follow-up — card/detail formatter using `road`** — small, do right after the proxy lands so the new field is actually visible somewhere.

Items 1-2 don't block on the Nominatim decision at all and could go out first if you want a quick win.
