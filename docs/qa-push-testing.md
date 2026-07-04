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
| `[FCM] FCM HTTP 200` but no device popup | Check client Firebase config, browser permission, service worker; see "Data-only push payloads" below if it's specifically iOS Safari |
| `staleTokens: 1` | Token expired; re-register from client (`fcmTokenRegister`) |

## Data-only push payloads (iOS Safari quirk)

Every FCM message the server sends is **data-only** — `title`/`body`/`link`/`beaconId` all travel under `data`, and there is deliberately no top-level `notification` field. This isn't the FCM default; it was changed on 2026-07-04 after this exact sequence, confirmed on an iOS Safari PWA:

1. `sendChatNotification`/QA send returns `200`/`"sent"`, so the server-side send genuinely succeeded.
2. No notification ever appears on the device.
3. On the next app open, the account shows `"registered on server": false` even though nothing about the registration flow failed — the token is simply dead.

The cause: with a `notification` field present, Chrome/Firefox display it automatically via Firebase's own service-worker handling, with no code of ours involved. That same automatic path is unreliable on iOS Safari — and **Safari cancels a web push subscription outright if a push event arrives and the service worker doesn't end up calling `showNotification()` for it.** So a delivery that silently fails to display on Safari doesn't just look broken once; it kills the subscription, and the *next* registration attempt is what you actually observe failing.

The fix: the server never sends a `notification` field (see `buildFcmMessagePayload` in `packages/server/lib/data/service/fcm_service.dart`), and the generated service worker (`packages/server/lib/api/controllers/firebase_sw_controller.dart`) calls `self.registration.showNotification()` itself from `onBackgroundMessage`, on every browser, using the `data` payload. This is deliberate and must stay this way:

- **Do not re-add a `notification` field to the FCM payload.** If you do, Chrome/Firefox will show it via their own automatic path *in addition to* the explicit `showNotification()` call below — every push becomes a duplicate (a well-documented firebase-js-sdk footgun: issues #4412, #5516, #6670).
- The service worker also owns click-to-open (`notificationclick` → focus/open `data.link`) for the same reason — the automatic path's `fcm_options.link` handling doesn't fire for data-only messages either.
- This can't be exercised by the Dart test suite — it only runs inside a real browser's service worker runtime. `buildFcmMessagePayload` is unit-tested to *never* emit a `notification` key, but verifying actual display still means testing in a real browser (Chrome, Firefox, and specifically Safari-iOS, since that's the one that silently breaks).

## Related

- [`GET /_qa/latest-email`](../packages/server/lib/api/controllers/qa_email_sink_controller.dart) — magic-link capture for QA email flows
- [`packages/server/rest/qa_send_fcm.http`](../packages/server/rest/qa_send_fcm.http) — REST Client examples
