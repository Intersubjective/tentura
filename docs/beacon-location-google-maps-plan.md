# Plan: Google Maps picker + external Maps hand-off for beacon location

Status: **plan only, not implemented.** Supersedes `reverse-geocoding-server-proxy-plan.md`. Builds on findings in `beacon-location-ux-review.md`.

## Decision recap

- **Picker (authoring)**: replace `flutter_map`+OSM with `google_maps_flutter` + Google Places Autocomplete (New), embedded **only** in the create/edit location dialog.
- **Viewing/routing**: no embedded map for viewers at all — tapping a beacon's location launches the platform's own Maps app/site via `url_launcher`, built from `beacon.coordinates`.
- **Cost control**: because the SDK only ever mounts in the picker, billed Google usage scales with *beacon-creation* activity, not *view* activity (views are the larger, unbounded number). Reference: [appunite.com — reducing Places Autocomplete spend by 80%](https://www.appunite.com/blog/how-we-reduced-cloud-spends-of-google-place-autocomplete-by-80-a-case-study) — their levers, in order of impact, were **session tokens** (~40% alone: bundling the keystroke predictions + the final Place Details lookup into one billed session instead of paying per request), **field masking** (only request the specific fields you use — an unmasked Details call silently pulls in paid Contact/Atmosphere data you never asked for), and **country/region restriction** (fewer irrelevant results, fewer retries). This plan applies all three, plus goes further by never re-querying Google after authoring time at all (see below).

## Requirement coverage (A/B/C/D)

| Goal | How it's met | Depends on Google APIs? |
|---|---|---|
| A — author picks a concrete address | `GoogleMap` + Places Autocomplete (New) search box, tap-on-map fallback, drag-to-adjust marker, confirm step before commit, zoom up to building level | Yes — Autocomplete + Place Details, and Geocoding for the tap/drag fallback |
| B — short address on the card | `Place`/address text resolved **once at authoring time** and stored on the `Beacon` row; card renders it directly, no live lookup | Yes, but only once per beacon, not per view |
| C — tap → see the map | No embedded map for viewers. Tap opens the OS/browser's own Maps app at the exact coordinates | No — pure deep link, zero Google API calls |
| D — copy/route | Same deep link as C doubles as "get directions"; "copy address" (stored text) and "copy coordinates" (always available) as secondary actions | No |

## Picker UI/UX (`ChooseLocationDialog` rewrite)

Replace the current tap-only, instant-commit flow (`packages/client/lib/features/geo/ui/dialog/choose_location_dialog.dart`) with:

1. **Search**: a Material 3 `SearchAnchor`/`SearchBar` at the top of the dialog (per `material-3-flutter` skill — prefer the themed MD3 component over a raw `TextField` + manual overlay). Debounce input ~300ms, don't fire a request below 3 characters (reduces the number of *abandoned* sessions — sessions that never resolve to a Place Details call are still billed under a separate, lower-value SKU, so starting fewer of them still matters even though within-session keystrokes are free).
2. Each keystroke (post-debounce) calls Places Autocomplete (New) with a **session token** generated once when the search box gains focus (`uuid` package — already a client dependency) and reused for every prediction request in that interaction.
3. Selecting a prediction calls Place Details (New) **with the same session token** and a field mask limited to `location,formattedAddress,addressComponents` — closes the session (Google bills the whole interaction once here); result moves the camera, drops a marker, and fills in the resolved address text — but does **not** close the dialog yet.
4. **Fallback**: user can still tap directly on the map, or drag the marker, bypassing search entirely. On tap/drag-**end** only (not per drag frame — throttle to one call after the gesture settles), call the classic Geocoding API (`reverse`) to resolve `address_label`. This has no session-token concept (that's Places-specific); volume is inherently low since it only fires on deliberate author gestures.
5. **Confirm step** (fixes the "instant commit" issue from the UX review): show the resolved address text + an explicit "Use this location" button. No more accidental commits from a single mis-tap.
6. Raise `maxZoom` from 12 to ~18-19 (building-level), matching what `GoogleMap` supports natively.
7. **Attribution**: none of this needs manual handling — the Google logo/attribution renders inside the `GoogleMap` widget itself automatically, unlike the current unattributed OSM tiles (see `beacon-location-ux-review.md`, the missing `RichAttributionWidget` finding — that finding is moot once OSM tiles are gone).

## Card / detail view — persist, don't re-resolve

Today, address text is **never stored** — `PlaceNameText` (`packages/client/lib/features/geo/ui/widget/place_name_text.dart:26-34`) calls `GeoRepository.getLocationByCoords` fresh on every build via a `FutureBuilder`, and `GeoRepository`'s cache is an in-memory `Map` that resets every app session. If this pattern were kept, every card render of every location-bearing beacon, by every viewer, forever, would be a billed Google Geocoding/Places call — reintroducing exactly the unbounded, view-scaled cost this plan exists to avoid.

Instead: **capture the resolved address once, at authoring time, and store it on the beacon.**

- Client: `BeaconCreateCubit.setLocation` (`beacon_create_cubit.dart:235`) already carries `Coordinates?` + a `String locationName` together — this is the exact shape needed; the location name becomes the value persisted server-side, not just local UI state.
- Server: add a `address_label text` column, thread it through the same path `coordinates` already takes.
- Card/detail widgets (`_LocationMeta`/`_CompactPlaceNameText` in `beacon_compact_metadata_strip.dart:333-392`, and `beacon_definition_body.dart:82-87`) read `beacon.addressLabel` directly — no `FutureBuilder`, no `GeoRepository` call, no `PlaceNameText` widget needed for beacons created after this ships.
- **Legacy beacons** (created before this migration) have coordinates but no `addressLabel` — no backfill job; they fall back to the existing generic "Location set" label / raw coordinates display. Acceptable one-time cosmetic gap, not worth a batch re-geocoding job.
- `GeoRepository`'s reverse-geocoding responsibility goes away entirely (superseded by the picker's own Geocoding/Places calls); what's left of it (device `getMyCoords`/permission handling) stays.

## Viewing / routing — external hand-off (collapses C + D)

Replace the "Show on Map" button's `ChooseLocationDialog.show(...)` call (`beacon_definition_body.dart:88-91`, and wherever the card links out) with a "directions" action built purely from `beacon.coordinates`, via `url_launcher` (already a dependency, zero new packages):

- **Android**: `geo:<lat>,<long>?q=<lat>,<long>(<label>)` — resolves to the user's default maps app.
- **iOS**: `https://maps.apple.com/?ll=<lat>,<long>&q=<label>` — opens Apple Maps.
- **Web**: `https://www.google.com/maps/search/?api=1&query=<lat>,<long>` — universal fallback, no app to hand off to.

Present as a small action row/sheet next to the location line — reuse the `ListTile` + `Icons.copy_outlined`/directions-icon pattern from `fact_actions_sheet.dart`, **not** a `Chip`/pill (forbidden on beacon-view surfaces by `no_operational_pill_widgets_in_beacon_view`). Actions: **Open in Maps** (primary — the deep link above), **Copy address** (stored `addressLabel` text via `Clipboard.setData`, same pattern as `share_code_dialog.dart:91-93`), **Copy coordinates** (always available, most robust paste target regardless of address quality).

This also retires the earlier-planned "give `ChooseLocationDialog` a read-only mode" fix — there's no read-only *map* state to build at all, since viewers never see an embedded map.

## Implementation steps

**Client**

1. `pubspec.yaml`: add `google_maps_flutter` (federated — pulls in Android/iOS/Web implementations automatically). Remove `flutter_map`, `geocoding` once the picker rewrite lands. `uuid` and `url_launcher` are already present.
2. New `GooglePlacesService` (Dart, `package:http`) — thin wrapper over Places API (New) REST: `POST places.googleapis.com/v1/places:autocomplete` (predictions) and `GET places.googleapis.com/v1/{place_id}` (Details), auth via `X-Goog-Api-Key` header, field masking via `X-Goog-FieldMask` header (verify exact current header/field-path names against Google's docs at implementation time — New API surface, don't assume this plan's wording is byte-exact). Owns session-token lifecycle (one `uuid.v4()` per search interaction, reused across predictions + the closing Details call).
3. New `GoogleGeocodingService` — thin wrapper over the classic Geocoding API (`maps.googleapis.com/maps/api/geocode/json?latlng=...`) for the tap/drag-end fallback path only.
4. Rewrite `ChooseLocationDialog` per the UI/UX section above: `GoogleMap` widget, `SearchAnchor` search row, marker drag, confirm step, `maxZoom` ~18.
5. Extend `Place` (`packages/client/lib/features/geo/domain/entity/place.dart`) with the fields needed for a short label (or drop `Place` in favor of a single `addressLabel` string, since it's now captured once as formatted text rather than re-derived per platform each time — simpler than maintaining `country`/`locality`/`road` separately if nothing downstream needs them individually).
6. `BeaconCreateCubit.setLocation` / the beacon-create GraphQL mutation call: send `addressLabel` alongside `coordinates`.
7. `_LocationMeta`, `_CompactPlaceNameText`, `beacon_definition_body.dart`'s location button: read `beacon.addressLabel` directly; delete `PlaceNameText` and the now-unused reverse-geocoding half of `GeoRepository`, delete `geocoding_web_service.dart` (already dead code today — see below).
8. Add the "Open in Maps / Copy address / Copy coordinates" action row (or sheet), per the pattern in `fact_actions_sheet.dart`.

**Server**

9. Migration `packages/server/lib/data/database/migration/m0110.dart` (next after `m0109`), following the `m0087.dart` add-column template:
   ```sql
   ALTER TABLE public.beacon ADD COLUMN IF NOT EXISTS address_label text;
   ```
10. Drift mirror: `packages/server/lib/data/database/table/beacons.dart` — add `late final addressLabel = text().nullable()();` alongside the existing `lat`/`long` columns.
11. `BeaconEntity` (`packages/server/lib/domain/entity/beacon_entity.dart`): add `String? addressLabel` next to the existing `Coordinates? coordinates` field.
12. GraphQL mutation (`mutation_beacon.dart`): add a plain `address_label: String` argument alongside the existing `InputFieldCoordinates.field` in `create`/`update`/`updateDraft` (lines ~77/95, 130/147, 168/185); thread it through `beacon_case.dart` and `beacon_repository.dart` the same way `latitude`/`longitude` already flow (`Value(addressLabel)` into Drift's `managers.beacons`).
13. Display path: beacon cards are served via Hasura's auto-tracked `public.beacon` table (not the hand-written `gqlTypeBeacon`, which is mutation-return-only today) — the new `address_label` column becomes queryable automatically once migrated; confirm/refresh Hasura's metadata tracking picks it up (metadata reload, or explicit tracking step depending on how `hasura/metadata.json` is managed in this repo).
14. Rerun `build_runner` after the DI/entity changes (per prior project convention).

## Rollout

- Ship server pieces (9-13) first — inert until the client sends `address_label`.
- Ship client pieces once Google Cloud credentials exist (see chat instructions) — old `ChooseLocationDialog` behavior can be feature-flagged or just cut over directly given this is a full rewrite, not an incremental patch.
- No backfill for existing beacons (see "Card / detail view" above).

## Testing

- Client: widget test for the rewritten `ChooseLocationDialog` covering search → select → confirm, and tap → drag → confirm, with `GooglePlacesService`/`GoogleGeocodingService` mocked (no real network calls in tests). Golden test if the dialog becomes a reusable component per the design-system skill's guidance.
- Server: migration smoke test (`-x pg` tag per project convention), mutation test asserting `address_label` round-trips through create/update/updateDraft.
