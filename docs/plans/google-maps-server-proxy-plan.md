---
status: active
kind: plan
---
# Server-side Google Maps Platform proxy (Geocoding + Places), OAuth-authenticated

Plan date: 2026-07-04. Not implemented yet — this is a design doc for review.

## Context

Picking a location on the map calls `GoogleGeocodingService.reverseGeocode()`, which hits
the classic REST endpoint `maps.googleapis.com/maps/api/geocode/json` directly from the
client with the project's Google Maps API key. That key is HTTP-referrer-restricted
(required for the Maps JS SDK to render in-browser), and the classic Geocoding REST API
categorically refuses referrer-restricted keys ("API keys with referrer restrictions cannot
be used with this API") — confirmed by curling the exact request with the real key. That's
why the map shows the address bubble (native SDK, trusted under the referrer) while our own
field kept saying no address was found (our REST call was rejected every time, silently
treated as "no results").

Investigating the equivalent fix for native Android surfaced a deeper issue: Android-app-
restricted keys are validated for raw REST calls only via two client-supplied headers
(`X-Android-Package`, `X-Android-Cert`) — both trivially extracted from any APK (manifest +
signing cert). So an Android-restricted key gives no real protection for a direct REST call.

Decision: stop calling Google Maps Platform APIs directly from any client. Add authenticated
server endpoints that make these calls server-side, using **OAuth 2.0 with a service
account** rather than an API key — confirmed via Google's own docs that both the Geocoding
API v4 (GA, "designed as a server-to-server API... enhanced security options like OAuth") and
Places API (New) support OAuth 2.0 service-account auth with the `cloud-platform` scope, the
same JWT-bearer flow this codebase already uses for FCM
(`data/service/fcm_service.dart:generateAccessToken()`). OAuth means no IP restriction is
needed at all: the credential is a service-account private key held server-side only, and
access is governed by IAM permissions, not network location — directly answering "won't the
server need to be IP-bound" (no).

Per user request, this covers **both** Geocoding and Places (New) — search/autocomplete was
going to keep the same latent weakness otherwise — and includes a full audit of every other
Google-Maps-adjacent touchpoint in the codebase (see below) so nothing else "bites" the same
way later.

Sources: [Geocoding API v4 overview](https://developers.google.com/maps/documentation/geocoding/geocoding-v4-overview),
[Get started with Geocoding API v4](https://developers.google.com/maps/documentation/geocoding/start-v4),
[Places API (New) OAuth](https://developers.google.com/maps/documentation/places-aggregate/oauth-token),
[OAuth 2.0 for server-to-server apps](https://developers.google.com/identity/protocols/oauth2/service-account).

## Full inventory: every Google-Maps-adjacent touchpoint (grepped `googleapis.com`/`google.com/maps` across the whole repo)

| Touchpoint | File | Assessment |
|---|---|---|
| Geocoding REST (classic v3) | `client: features/geo/data/service/google_geocoding_service.dart` | **Fixed by this plan** — moves server-side, v4 + OAuth |
| Places API (New) autocomplete + details | `client: features/geo/data/service/google_places_service.dart` | **Fixed by this plan** — moves server-side, OAuth |
| Maps JavaScript SDK (renders the interactive map) | `client: web/index.html` script tag | **Reviewed, fine as-is.** Can't be proxied — needs to run in-browser to render a live map. Referrer restriction is the Google-sanctioned mechanism here and isn't spoofable the way raw REST calls are (the browser attaches the real `Referer`, not the client code). No change. |
| Native map rendering | `client: android/app/build.gradle` + `AndroidManifest.xml`, `ios/Runner/AppDelegate.swift` (`GMSServices.provideAPIKey`) | **Reviewed, pre-existing open item (unchanged by this plan), and genuinely safe to keep client-side.** Unlike a raw REST call, the native SDK doesn't rely on self-reported `X-Android-Package`/`X-Android-Cert` header strings — it asks the Android OS what package/signing certificate the *currently running, installed* process actually has, which the OS only reports truthfully for a package whose signature it verified at install time. Spoofing that requires the app's actual private signing key (not just the public cert fingerprint extractable from an APK) or a compromised/rooted device — a materially higher bar than "grep the APK and curl it," and not something that can be routed through a server proxy anyway (an interactive, pannable/zoomable map needs the SDK talking to Google's tile servers directly, same as the web Maps JS SDK). Still needs its own Android/iOS-app-restricted key(s) (package name + SHA-1 / bundle ID) — it's currently wired to the same referrer-restricted web key, which won't authenticate for native rendering at all. Flagged earlier in this conversation; still the user's Cloud Console action. |
| `google_sign_in` package | client pubspec dependency | Unrelated — Google Identity/OAuth sign-in, not Maps Platform, no API-key exposure of this kind. No action. |
| FCM push, Google OIDC | `server: data/service/fcm_service.dart`, `data/service/oidc/google_oidc_service.dart` | Unrelated to Maps, but confirms this exact JWT-bearer OAuth pattern already works and is the precedent being reused. |
| Static Maps / Street View / Directions / Distance Matrix / Elevation / Roads APIs | — | **None found anywhere in the repo.** Nothing else to fix. |

## UX redesign: place name vs. address

Prompted by reviewing this feature from a UX standpoint: the current design conflates two
different things into one `addressLabel` string — *what a place is called* (a venue/POI
name) and *where it is* (a postal address). Social/event apps (Facebook Events, Eventbrite,
Meetup, Partiful, Luma) all make place search primary and display results as **venue name
bold, address as a muted secondary line** — nobody thinks in postal addresses; they think in
names ("Blue Bottle on Valencia", "Golden Gate Park"). Map-tap/pin-drop is universally a
*secondary* affordance in these apps, not because it's less useful, but because reverse
geocoding structurally can't produce a venue name — it's address-oriented, not POI-oriented.

**Data model**: split the current single `addressLabel` into two nullable fields:
- `placeName` — e.g. "Golden Gate Park" (from Places Details' `displayName`, only available
  via the search path)
- `formattedAddress` — e.g. "501 Stanyan St, San Francisco, CA 94117" (available from both
  search and map-tap/reverse-geocode)

Search (Places autocomplete → details) fills both. Map-tap/drag (reverse geocode) can only
ever fill `formattedAddress` — that's inherent to what reverse geocoding is, not a gap to
close.

**Display rule** (three tiers, each mapping to a real situation instead of one string doing
double duty):
1. `placeName` present → show it bold/primary, `formattedAddress` muted/secondary beneath.
2. `placeName` absent, `formattedAddress` present → address becomes the primary line (the
   "middle of nowhere" fallback).
3. Both absent → the existing "Pinned location (no address found)" placeholder.

**What this touches, beyond the proxy work below:**
- Places fieldMask needs `displayName` added
  (`location,formattedAddress,addressComponents,displayName`) so the venue name is actually
  fetched — currently isn't requested at all.
- Server: `beacons` table needs a new nullable `place_name` column (migration; check the next
  free migration number — this codebase's schema is raw migrant SQL, not Drift) and the
  GraphQL beacon type/mutations need a `placeName` field alongside `addressLabel`. Regenerate
  client GraphQL codegen after the schema change.
- Client: `domain/entity/beacon.dart` gets `String? placeName` alongside `addressLabel`;
  `BeaconCreateState`/`BeaconCreateCubit.setLocation()` carries both; the picker dialog's
  returned `Location` shape needs a distinct slot for the venue name (note:
  `features/geo/domain/entity/place.dart`'s `Place` class already means something else —
  a city/country locality summary for compact card metadata — don't overload it; add a
  separate field instead).
- Display: `beacon_definition_body.dart`'s `_locationLabel` and `info_tab.dart`'s location
  field builder both need the three-tier rule above. The view screen has room for a
  two-line treatment (name + muted address); the single-line editable field is more
  space-constrained and may want a combined truncated "Name · Address" or name-only-when-
  present treatment — exact per-surface layout is a design pass to do at implementation
  time, not fully specified here.

**Explicitly separate, not solved here**: since Tentura is a mutual-aid coordination app (not
a public event board), a Request's location might be someone's home address rather than a
public venue. Whether the exact address should be visible to everyone who can see a Request,
versus only revealed after being admitted to help, is a privacy-model question this redesign
doesn't answer — worth a deliberate look on its own.

## Server changes (`packages/server`)

Mirrors this codebase's existing port → repository → module → controller pattern (the FCM
stack: `domain/port/fcm_remote_repository_port.dart`,
`data/repository/fcm_remote_repository.dart` + `_module.dart`, and the REST-controller
conventions in `api/controllers/account_profile_controller.dart`).

1. **`env.dart`**: add `googleMapsSaClientEmail` / `googleMapsSaPrivateKey`
   (`GOOGLE_MAPS_SA_CLIENT_EMAIL` / `GOOGLE_MAPS_SA_PRIVATE_KEY`), same `_env['...'] ?? ''`
   idiom as `fbClientEmail`/`fbPrivateKey`. Add `isGoogleMapsPlatformConfigured` getter
   (mirrors `isFcmConfigured`) for the mock-fallback module pattern. No project-ID env var
   needed — neither the Geocoding v4 nor Places (New) endpoint paths are project-scoped
   (unlike FCM's `.../projects/{id}/messages:send`); the project is implied by the service
   account's credentials.

2. **`data/service/google_maps_platform_auth_service.dart`** (new): JWT-bearer OAuth flow,
   copied from `FcmService.generateAccessToken()`'s shape (RSA private key,
   `dart_jsonwebtoken`, POST to `https://oauth2.googleapis.com/token`) but scoped to
   `https://www.googleapis.com/auth/cloud-platform` and reading the new env vars. Unlike
   FCM (which splits mint vs. cache across `FcmService`/`FcmRemoteRepository`), cache the
   token *inside* this service — both new repositories share one token, so one cache is
   simpler than duplicating FCM's split. Give it a `.withClient` test constructor (the
   pattern already used client-side in `GoogleGeocodingService`/`GooglePlacesService`) so
   the token flow is directly unit-testable, which FCM's version currently isn't.

3. **Ports** (`domain/port/`):
   - `geocoding_remote_repository_port.dart`:
     `Future<String?> reverseGeocode({required double lat, required double long});`
   - `places_remote_repository_port.dart`:
     `Future<List<PlacePredictionEntity>> autocomplete({required String input, required String sessionToken});`
     `Future<PlaceDetailsEntity> details({required String placeId, required String sessionToken});`
     (new small entities in `domain/entity/`, mirroring the client's current
     `GooglePlacePrediction`/`GoogleResolvedPlace` shapes — `PlaceDetailsEntity` needs a
     `placeName` field alongside `formattedAddress`, per the UX redesign section above)

4. **Repositories** (`data/repository/`):
   - `geocoding_remote_repository.dart`: calls
     `https://geocode.googleapis.com/v4/geocode/location/{lat},{lng}` with
     `Authorization: Bearer <token>`. Response has a `results[]` array with a
     `formattedAddress` field (camelCase — v4 uses modern camelCase JSON, unlike v3's
     `formatted_address`); **verify the exact nesting against a live call while
     implementing** — doc fetches confirm the field name but not the full schema with
     certainty.
   - `places_remote_repository.dart`: same existing endpoints as today's client-side
     `google_places_service.dart` (`places.googleapis.com/v1/places:autocomplete`,
     `/v1/places/{placeId}`), just swap the `X-Goog-Api-Key` header for
     `Authorization: Bearer <token>` (keep `X-Goog-FieldMask`, unchanged).
   - Mock variants + `_module.dart` per repository, mirroring
     `fcm_remote_repository_module.dart`'s real-when-configured/mock-otherwise branch on
     `isGoogleMapsPlatformConfigured`.

5. **Rate limiting**: one per-user in-memory limiter,
   `domain/util/geo_action_rate_limiter.dart`, generalizing
   `debug_send_rate_limiter.dart`'s exact shape (`@singleton`, `tryAcquire(userId, action)`,
   `@visibleForTesting` cooldown ctor + `clear()`) with an action enum
   (`reverseGeocode`, `placesAutocomplete`, `placesDetails`) instead of hardcoding one
   channel. Default cooldown ~1s per action — these are one-shot-per-interaction calls
   (tap, drag-end, keystroke-debounced search), not a continuous stream.

6. **Controller** (`api/controllers/geo_controller.dart`, new, `@Injectable(order: 3)`):
   handlers `reverseGeocode`, `placesAutocomplete`, `placesDetails`. Each: resolve
   `accountId` from `kContextJwtKey` → 401 if absent; rate-limiter check → 429; parse/
   validate JSON body → 400; call the port; map `ExceptionBase` → error response,
   catch-all → `internalServerError()`. `reverseGeocode` returns
   `{'formattedAddress': result}` where `result` may legitimately be `null` (200, not an
   error — the client already renders "no address found" for that case).

7. **`api/root_router.dart`**: inject `GeoController`, add three routes under
   `/api/v2/geo/reverse-geocode`, `/api/v2/geo/places/autocomplete`,
   `/api/v2/geo/places/details`, all behind `_authMiddleware.verifyBearerJwt`.

8. Run server DI codegen (`dart run build_runner build --delete-conflicting-outputs`) after
   adding the new `@Injectable`/`@singleton`/`@module` classes.

9. Tests: `geo_action_rate_limiter_test.dart` (mirror `debug_send_rate_limiter_test.dart`);
   `google_maps_platform_auth_service_test.dart` (mock HTTP client for the token endpoint,
   assert caching/re-mint-on-expiry); `geo_controller_test.dart` (mirror
   `account_profile_controller_test.dart`/`qa_send_fcm_controller_test.dart`) — fake ports,
   assert 401/429/400/200 paths for all three handlers.

## Client changes (`packages/client`, shared across web/Android/iOS)

1. **New** `features/geo/data/repository/reverse_geocode_repository.dart` and
   `places_repository.dart`, both extending `RemoteRepository` (same pattern as
   `credentials/data/repository/credentials_repository.dart`), calling the three new
   server endpoints via `remoteApiService.postAuthenticatedJson(...)`. Keep methods
   non-`final` so tests can subclass them directly, matching the existing
   `_FakeGeocodingService extends GoogleGeocodingService` /
   `_FakePlacesService extends GooglePlacesService` pattern already used in
   `choose_location_dialog_test.dart`.

2. **Remove**: `features/geo/data/service/google_geocoding_service.dart`,
   `google_places_service.dart`, `google_maps_json.dart` (its parsing helpers move
   server-side alongside the repositories that now need them), and this session's
   web-only JS-SDK workaround (`google_maps_geocoder.dart`, `_stub.dart`, `_web.dart`) —
   no client talks to Google's Geocoding or Places APIs directly anymore.

3. **Update** `features/geo/ui/dialog/choose_location_dialog.dart`: swap
   `GetIt.I<GoogleGeocodingService>()` → `GetIt.I<ReverseGeocodeRepository>()` and
   `GetIt.I<GooglePlacesService>()` → `GetIt.I<PlacesRepository>()`. Call sites
   (`.reverseGeocode(...)`, `.autocomplete(...)`, `.details(...)`) are unchanged in shape.

4. Register both new repositories for DI the way `CredentialsRepository` is registered
   (`@Singleton(env: [Environment.dev, Environment.prod])`), then run client DI codegen.

5. Tests: replace the `GoogleGeocodingService`/`GooglePlacesService`-specific cases in
   `test/features/geo/data/service/google_location_services_test.dart` with equivalents
   for the new repositories (check for a `credentials_repository_test.dart` for this
   codebase's `RemoteRepository` fake-service test harness). Update the fakes in
   `choose_location_dialog_test.dart` to extend the new repository classes — the existing
   dialog tests (search-select, map-tap, marker-drag, and this session's
   "disables confirm until resolved" test) keep working unchanged since they only depend
   on the `reverseGeocode(Coordinates) → Future<String?>` / autocomplete/details shapes.

## Explicitly out of scope

- Provisioning the actual Android/iOS native-map-rendering keys (app-restricted) — the
  pre-existing open item from earlier in this conversation, independent of this proxy work.
- Whether the new server-side service account is a dedicated one or reuses the existing
  Firebase one (if it's granted the right IAM role) — the user's Cloud Console decision;
  either works with just the two new env vars.
- Confirming the exact Geocoding v4 IAM role name and full response schema — verify against
  the live API during implementation rather than assume further.

## Verification

- Server: `cd packages/server && dart test test/domain/util/geo_action_rate_limiter_test.dart test/data/service/google_maps_platform_auth_service_test.dart test/api/controllers/geo_controller_test.dart`
- Client: `cd packages/client && flutter test test/features/geo/`
- Live, **local dev note**: the current `.env`'s `GOOGLE_MAPS_API_KEY` is referrer-restricted
  and has no bearing on the new OAuth flow — you'll need a service account (client email +
  private key) with the Geocoding API v4 and Places API (New) enabled/granted on its
  project, set as `GOOGLE_MAPS_SA_CLIENT_EMAIL`/`GOOGLE_MAPS_SA_PRIVATE_KEY`, before this can
  be tested end-to-end locally.
- Once configured: restart the local server + hot-restart the Flutter web app, repeat the
  Eiffel Tower map-tap and search flows via Playwright, and confirm (a) both resolve
  addresses correctly and (b) the browser's network tab shows only calls to our own
  `/api/v2/geo/...` endpoints, never `maps.googleapis.com`/`places.googleapis.com` directly.
