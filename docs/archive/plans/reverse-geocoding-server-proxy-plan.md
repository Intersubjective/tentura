---
status: superseded
kind: plan
superseded_by: docs/plans/beacon-location-google-maps-plan.md
---
# Plan: server-side reverse geocoding (replace client-only `geocoding` package)

**Superseded by `docs/plans/beacon-location-google-maps-plan.md`.** After further review the decision moved to a Google Maps picker (rendered only during authoring, not on every view) + external Maps hand-off for viewing/routing, dropping the Nominatim proxy. Kept below for history/context only — do not implement this version.

Status: **plan only, not implemented.** Decision: proxy through Nominatim server-side (see comparison in the appendix for why this beats "Google Maps on web + native geocoder on mobile"). See also `docs/audits/beacon-location-ux-review.md` — this proxy fixes web/desktop address *resolution*, but the picker (no address search), the read-only map dialog (reuses the editable picker, bug), and "copy/open in Maps" need their own follow-ups.

## Problem

`GeoRepository.getPlaceNameByCoords` (`packages/client/lib/features/geo/data/repository/geo_repository.dart:38-55`) reverse-geocodes via the `geocoding` package, which wraps each OS's native geocoder:

```dart
if (kIsWeb || isDesktopPlatform) return null;   // line 42 — no geocoder available there
final places = await placemarkFromCoordinates(coords.lat, coords.long);
```

Consequences:
- Web and desktop always get `null` — no city/country, no street.
- `Place` (`packages/client/lib/features/geo/domain/entity/place.dart`) only carries `country` + `locality`; there's no street name on any platform today.
- Server has zero involvement — `Coordinates` are stored on `BeaconEntity` but never looked up server-side, so nothing can be cached, rate-limited, or made consistent across platforms.

## Proposed solution: server-side Nominatim proxy

Follows the existing port/service + GraphQL query/use_case layering already used for outbound HTTP (`ResendEmailSender` implementing `EmailSenderPort`, `resend_email_sender.dart`).

1. **`GeocodingPort`** (`domain/port/geocoding_port.dart`) + **`NominatimGeocodingService`** (`data/service/geocoding/nominatim_geocoding_service.dart`) — calls `nominatim.openstreetmap.org/reverse` with `format=jsonv2&addressdetails=1`, a compliant `User-Agent`, parses `address.country`, `address.city|town|village`, `address.road`.
2. **Global rate gate + TTL cache** in the service (same shape as `DebugSendRateLimiter`, but a single shared min-interval gate, not per-user) — required by Nominatim's usage policy (~1 req/s) and cheap to add since coord taps cluster.
3. **Env knobs** in `packages/server/lib/env.dart`: `GEOCODING_PROVIDER_BASE_URL` (default public Nominatim, swappable for a self-hosted instance later), `GEOCODING_MIN_INTERVAL_MS`, `GEOCODING_CACHE_TTL`. Unset → service returns `null`, same as today's web behavior, so this is safe to land without config.
4. **Use case** `GeocodeReverseCase` (`domain/use_case/`) — requires an authenticated JWT (reuse `getCredentials(args)`) purely to stop the proxy being an open, unauthenticated relay to Nominatim.
5. **GraphQL**: `QueryGeocode` (`api/controllers/graphql/query/query_geocode.dart`) exposing `geocodeReverse(coordinates: CoordinatesInput!): Place`, reusing the existing `InputFieldCoordinates` input type; add `gqlTypePlace` to `custom_types.dart`; wire into `_queries_all.dart`; regenerate `schema.graphql`.
6. **Client**: extend `Place` with `road`; replace the platform-branching body of `getPlaceNameByCoords` with one GraphQL call (keep the existing `Map<Coordinates, Place?> cache`); delete the now-dead `geocoding_web_service.dart` stub and the `geocoding` pubspec dependency once the native path is gone.
7. **Attribution — corrected**: per OSMF's Attribution Guidelines, "a group of geocoding results need not maintain attribution attached to the results, as long as it does not form a Derivative Database" — compact beacon cards showing a resolved place name do **not** need a per-card credit. What's required is a single consolidated "reasonably calculated to make aware" notice somewhere always-reachable in the app (About/Legal/Settings page or a persistent footer), crediting OSM/Nominatim app-wide.
   - Separately, and more strictly: the **map tiles themselves** need their own visible attribution — `grep -rn "AttributionWidget" packages/client/lib` currently returns nothing, so `ChooseLocationDialog`'s `FlutterMap` renders OSM tiles with no corner credit at all. That's a pre-existing gap under OSM's Tile Usage Policy (unrelated to this geocoding plan) — fix by adding flutter_map's `RichAttributionWidget` to every `FlutterMap` in the app, regardless of which geocoding provider is chosen.

Net effect: **one code path for all platforms** (mobile/web/desktop identical), no new vendor, no API key to manage, street-level data added for the first time.

## Implementation steps (ordered, for later execution)

**Server**

1. `domain/port/geocoding_port.dart` — abstract `GeocodingPort` with `Future<Place?> reverseGeocode(Coordinates coords)`. `Place`/entity shape mirrors the client one (`country`, `locality`, `road`); add this entity under `domain/entity/place.dart` on the server side too (server currently has no `Place` type — check for a shared root package first, e.g. `tentura_root`, before duplicating; `Coordinates` is already shared via `tentura_root/domain/entity/coordinates.dart`, `road` isn't in the client entity yet either — see client step 1 below).
2. `data/service/geocoding/nominatim_geocoding_service.dart` — `NominatimGeocodingService implements GeocodingPort`, `http.Client`-based, same shape as `ResendEmailSender` (`data/service/email/resend_email_sender.dart:17-21`): constructor takes `Env`, one private `_client`, throws/returns `null` on non-2xx after logging via `Logger`.
   - Request: `GET {env.geocodingProviderBaseUrl}/reverse?lat=..&lon=..&format=jsonv2&addressdetails=1&zoom=18`, header `User-Agent: tentura/<version> (contact: <complaint email>)`.
   - Parse `address.country`, `address.city ?? address.town ?? address.village`, `address.road`.
   - Internal: a shared min-interval gate (module-level `DateTime? _lastCall`) before each outbound call, and a `Map<Coordinates, Place?>` TTL cache (reuse the `DebugSendRateLimiter` file, `domain/util/debug_send_rate_limiter.dart`, as the closest existing pattern for an in-memory per-process throttle — this one is global, not per-user/channel, so it needs a slightly different shape, not a literal reuse).
3. `env.dart` — add `geocodingProviderBaseUrl` (`GEOCODING_PROVIDER_BASE_URL`, default `https://nominatim.openstreetmap.org`), `geocodingMinInterval` (`GEOCODING_MIN_INTERVAL_MS`, default `1100`), `geocodingCacheTtl` (`GEOCODING_CACHE_TTL_SECONDS`, default e.g. `3600`) — same `String?`/`Duration?` constructor-param + `fromEnvironment` pattern as the existing `emailAuthRateLimitWindow` (`env.dart:49,173,439`).
4. `domain/use_case/geocode_reverse_case.dart` — `GeocodeReverseCase(this._geocodingPort)`, one method `Future<Place?> call({required String userId, required Coordinates coords})`; no DB/repository layer needed (nothing persisted), so this use case talks to the port directly rather than through a repository.
5. DI: register `GeocodingPort → NominatimGeocodingService` and `GeocodeReverseCase` via the existing `@singleton`/`@LazySingleton` injectable annotations, then run `build_runner` (per `[[security-hardening-pass]]` memory note: rerun build_runner after DI changes).
6. GraphQL type: in `custom_types.dart`, add `gqlTypePlace = GraphQLObjectType('place', null)..fields.addAll([field('country', graphQLString), field('locality', graphQLString), field('road', graphQLString)])`, following the `gqlTypeMutualScore` pattern (`custom_types.dart:355-359`). Register it in the `customTypes` list.
7. `api/controllers/graphql/query/query_geocode.dart` — `QueryGeocode extends GqlNodeBase`, one field `geocodeReverse` with `arguments: [InputFieldCoordinates.field]`, resolver calls `getCredentials(args)` for auth then `InputFieldCoordinates.fromArgs(args)` (existing helper, `input_field_coordinates.dart:18-25`) then `_geocodeReverseCase.call(...)`, mapped to a `Map<String, dynamic>` for the gql response — mirrors `QueryMutualFriends` (`query_mutual_friends.dart`).
8. Wire into `_queries_all.dart` (`...QueryGeocode().all`) and regenerate `schema.graphql`.

**Client**

9. Extend `Place` (`packages/client/lib/features/geo/domain/entity/place.dart`) with a `road` field (default `''`), update `toString`/`displayLocality` only if needed for street display.
10. Add a `.graphql` query doc + generated Ferry method for `geocodeReverse(coordinates: ...)`, alongside the existing `graph_fetch.graphql`-style files.
11. Rewrite `GeoRepository.getPlaceNameByCoords` (`geo_repository.dart:38-55`) to call the new GraphQL query instead of `placemarkFromCoordinates`; drop the `if (kIsWeb || isDesktopPlatform) return null;` branch entirely; keep the existing `cache` map as-is (client-side cache stays useful even with a server cache behind it, since it also saves a network round-trip for repeated taps in the same picker session).
12. Delete `geocoding_web_service.dart` and the conditional import in `geo_repository.dart:7-9` once nothing references the `geocoding` package; remove `geocoding: ^4.0.0` from `pubspec.yaml`.
13. Attribution: add an OSM credit line near the picked-location display (`ChooseLocationDialog` or wherever `Place` is rendered after pick), not just on the map tiles.

**Rollout**

14. Ship server pieces first (steps 1-8) behind the "unset env → `null`" default so it's inert; then land client pieces (9-13) once the query is live in an environment; confirm the picker flow end-to-end on web (the platform that's currently always `null`) before removing the `geocoding` dependency.

## Appendix: alternative considered — Google Maps on web + native geocoder on mobile (no server change)

This keeps mobile exactly as-is (Apple/Android native geocoders via the `geocoding` package) and adds Google Maps' Geocoding API purely on the web build.

| | Server-proxy (Nominatim) plan | Google Maps (web) + native (mobile) |
|---|---|---|
| **Desktop** | Fixed — same server call as web | **Still broken.** Google Maps Flutter/JS integration doesn't give desktop builds a geocoder either; you'd be back to `null` on desktop, the same bug that exists today. |
| **Code paths** | 1 (server call from every platform) | 3 (Google JS geocoder / Apple CLGeocoder / Android Geocoder) — reintroduces the exact platform-branching that caused today's web/desktop gap, now with 3 different data shapes/quality to normalize into `Place`. |
| **Street-level accuracy** | Good (Nominatim/OSM data — varies by region, generally weaker than Google in sparsely-mapped areas) | **Better** — Google's geocoding is generally best-in-class, especially outside dense OSM-coverage areas. |
| **Vendor / secrets** | None new — public Nominatim needs no API key | New: Google Maps Geocoding API key for web (must be HTTP-referrer-restricted, still ships in the client bundle), separate Maps SDK keys for Android/iOS if you also swap the mobile map widget. Some of this rides on an existing relationship — Firebase (FCM) and Google OAuth (`env.dart`'s `googleServerClientId`) already make Google a trusted vendor here, so it's a new *API surface*, not a wholly new vendor trust boundary. |
| **Cost** | Free at current scale; would need self-hosted Nominatim/Photon only if volume grows | Pay-per-request beyond Google's free tier — ongoing bill that scales with usage |
| **Server involvement** | New: proxy endpoint, caching, rate limiting | None — but also loses the chance to centrally cache/rate-limit/log geocoding calls the way uploads and messages already are |
| **Effort** | Medium (new port/service/use_case/query + client wiring) | Low for web (swap one call), zero for mobile — but doesn't actually close the gap that motivated this (desktop), so effort saved is partly illusory |

**Read**: the Google alternative buys better accuracy but keeps (and worsens) exactly the platform-fragmentation bug that's the actual problem statement, and still leaves desktop unsolved. It's a reasonable choice only if desktop reverse-geocoding is out of scope and result quality matters more than reducing code paths / avoiding a new billed dependency.

## Rollout / safety

- No DB migration — `Place` stays derived/ephemeral, not persisted on `BeaconEntity`.
- Ships dark: unset `GEOCODING_PROVIDER_BASE_URL` degrades to `null` everywhere, matching current web behavior.

## Testing

- Server: unit test `NominatimGeocodingService` against a fake `http.Client` (pattern already used for `ResendEmailSender`); `GeocodeReverseCase` test; GraphQL controller test following `query_invite_genealogy_test.dart`.
- Client: `GeoRepository` test with a mocked GraphQL client, asserting one code path (no `kIsWeb`/`isDesktopPlatform` branch left).

## Open questions

- Self-host Nominatim/Photon now vs. later — recommend starting on the public API + the rate gate/cache above, and only self-hosting if usage outgrows the ~1 req/s policy.
- Persist geocoded `Place` on `BeaconEntity` at creation time (denormalize so graph/genealogy views don't re-request) vs. keep it display-only as today — current code treats it as ephemeral, no indication that needs to change.
