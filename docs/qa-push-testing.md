# QA push testing (`POST /_qa/send-fcm`)

Send a one-shot FCM notification through the Tentura server without triggering beacon or room events. Uses the same QA auth gate as `GET /_qa/latest-email`.

## When to use

- Verify server Firebase credentials and FCM HTTP wiring
- Test push delivery to a specific user or device token
- Debug notification copy / deep links without reproducing coordination flows

## Prerequisites

1. **QA auth** (dev/staging only — never production):
   - `QA_AUTH_ENABLED=true`
   - `QA_AUTH_TOKEN=<secret>` in `.env`
   - Server `ENVIRONMENT` must not be `prod`

2. **Real Firebase HTTP** (optional but required for device delivery):
   - `FB_PROJECT_ID`
   - `FB_CLIENT_EMAIL`
   - `FB_PRIVATE_KEY` (PEM with `\n` escapes)

   If any server Firebase var is missing, the endpoint still returns `200` but sets `"mock": true` — the server logs `[FCM] mock send` and no HTTP call is made.

3. **A device target**:
   - **`userId`**: recipient must have registered FCM while signed in (notification permission granted). Rows live in `fcm_token`.
   - **`token`**: pass an explicit FCM device token (skips DB lookup).

   Client Firebase vars (`FB_API_KEY`, `FB_APP_ID`, `FB_VAPID_KEY`, …) are separate from server creds. A working service worker does not imply server push is enabled.

## Endpoint

```
POST /_qa/send-fcm?_qa_token=<QA_AUTH_TOKEN>
Content-Type: application/json
```

Bearer auth is also accepted: `Authorization: Bearer <QA_AUTH_TOKEN>`.

### Request body

| Field | Required | Description |
|-------|----------|-------------|
| `title` | yes | Notification title |
| `body` | yes | Notification body |
| `userId` | one of | Load all `fcm_token` rows for this user |
| `token` | one of | Send directly to this device token |
| `actionUrl` | no | Deep link, sent as `data.link` and opened by the client's own `notificationclick` handler |
| `beaconId` | no | Passed in FCM data payload |

If both `userId` and `token` are set, **`token` wins** (explicit override).

### Responses

| Status | Meaning |
|--------|---------|
| `404` | QA disabled, wrong token, or production |
| `400` | Invalid JSON, missing `title`/`body`, or missing target |
| `200` | See JSON body below |

**No tokens for userId:**

```json
{
  "ok": false,
  "reason": "no_fcm_token_rows",
  "userId": "U6fca01549512"
}
```

**Send attempted:**

```json
{
  "ok": true,
  "devices": 1,
  "sent": 1,
  "staleTokens": 0,
  "mock": false,
  "errors": []
}
```

- `mock: true` — server Firebase creds missing; no real HTTP
- `staleTokens` — count of expired/invalid tokens (pruned from DB)
- `errors` — per-token failures; only token **suffix** is returned, never the full token

## Examples

### Send by userId

```bash
curl -X POST "http://localhost:2080/_qa/send-fcm?_qa_token=$QA_AUTH_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{
    "userId": "U6fca01549512",
    "title": "QA test",
    "body": "Hello from Tentura",
    "beaconId": "B220d88332b35"
  }'
```

### Send by explicit token

```bash
curl -X POST "http://localhost:2080/_qa/send-fcm" \
  -H "Authorization: Bearer $QA_AUTH_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{
    "token": "YOUR_FCM_DEVICE_TOKEN",
    "title": "QA test",
    "body": "Direct token send"
  }'
```

### Inspect registered tokens

```sql
SELECT user_id, platform, length(token) AS token_len, last_refreshed_at
FROM fcm_token
WHERE user_id = 'U6fca01549512';
```

## Troubleshooting

| Server log / response | Fix |
|-----------------------|-----|
| `404` on curl | Set `QA_AUTH_ENABLED=true`, non-empty `QA_AUTH_TOKEN`, not prod |
| `"reason": "no_fcm_token_rows"` | Sign in as that user, grant notification permission; or pass explicit `token` |
| `"mock": true` | Set all three server `FB_*` creds and restart the API |
| `[FCM] FCM HTTP 200` but no device popup | Check client Firebase config, browser permission, service worker; if it's specifically an iOS PWA, see "iOS Safari: check the Feature Flag first" below before anything else |
| `staleTokens: 1` | Token expired; re-register from client (`fcmTokenRegister`) |

## iOS Safari: check the Feature Flag first

If an iOS PWA registers fine (permission granted, "registered on server: yes"), FCM accepts every send with `HTTP 200`, and a device-local test (`ServiceWorkerRegistration.showNotification()`, no push involved — the "Test direct notification" button in Settings → Debug) displays correctly, but real pushes still never arrive: **check Settings → Safari → Advanced → Feature Flags → Notifications on the device before debugging anything else.**

iOS 16.x shipped the web push APIs disabled by default behind that flag; Apple only enabled it by default starting iOS 17. A device stuck on iOS 16 (e.g. hardware that can't run 17+, like an iPhone 8) can look fully correctly configured on both the server and the client and still never receive a single push, because the underlying platform push-delivery machinery was never actually turned on. Confirmed 2026-07-05: toggling this flag on an iOS 16.7 device fixed delivery immediately, with zero code changes.

This was preceded by an incorrect theory (see git history / code comments predating this note) that the cause was Safari cancelling web push subscriptions that don't get a displayed notification. That specific mechanism is real and documented, and worth knowing about, but it was not what was happening in the case that was actually investigated and fixed here — don't reach for the payload-shape/service-worker explanation before ruling out the Feature Flag.

## Data-only push payloads

Every FCM message the server sends is **data-only** — `title`/`body`/`link`/`beaconId` all travel under `data`, and there is deliberately no top-level `notification` field. This is unrelated to the iOS Feature Flag issue above; it's kept for a different, still-valid reason:

With a `notification` field present, Chrome/Firefox display it automatically via Firebase's own service-worker handling, with no code of ours involved — and that automatic path is inconsistent across browsers (icon, `tag`/grouping, and click-navigation all end up depending on each browser's own default instead of something we control). The server never sends a `notification` field (see `buildFcmMessagePayload` in `packages/server/lib/data/service/fcm_service.dart`), and the generated service worker (`packages/server/lib/api/controllers/firebase_sw_controller.dart`) calls `self.registration.showNotification()` itself from `onBackgroundMessage`, on every browser, using the `data` payload. This is deliberate and must stay this way:

- **Do not re-add a `notification` field to the FCM payload.** If you do, Chrome/Firefox will show it via their own automatic path *in addition to* the explicit `showNotification()` call — every push becomes a duplicate (a well-documented firebase-js-sdk footgun: issues #4412, #5516, #6670).
- The service worker also owns click-to-open (`notificationclick` → focus/open `data.link`) for the same reason — the automatic path's `fcm_options.link` handling doesn't fire for data-only messages either.
- This can't be exercised by the Dart test suite — it only runs inside a real browser's service worker runtime. `buildFcmMessagePayload` is unit-tested to *never* emit a `notification` key, but verifying actual display still means testing in a real browser.

## Related

- [`GET /_qa/latest-email`](../packages/server/lib/api/controllers/qa_email_sink_controller.dart) — magic-link capture for QA email flows
- [`packages/server/rest/qa_send_fcm.http`](../packages/server/rest/qa_send_fcm.http) — REST Client examples
