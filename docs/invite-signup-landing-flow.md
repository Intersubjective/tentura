# Invite, signup, and landing flow

> **Status:** Implemented (client + landing). Describes current routing and UX as
> shipped. Domain terms: [`CONTEXT.md`](../CONTEXT.md) § Public web entry.

## Purpose

Invite links are opened in messengers, captive webviews, and native app links. The
product must:

1. Keep **`/invite/<code>`** as the only share URL (the **basic invite URL**).
2. Carry invite context into Flutter web (hash routes) and native without query-param
   hacks (`?invite=` is ignored by AutoRoute on WASM).
3. **Consume the invite once** — at signup for new users; via `accept-as-existing`
   only for already-authenticated users who confirm.
4. Avoid loops, double befriending, and pointless “open the app” bounces for anonymous
   visitors.

Route **names** (not query params) are the control surface.

## Surfaces and routes

| Surface | Host path | Who sees it |
|---------|-----------|-------------|
| **Landing** | `/invite/<code>`, `/` (signed out) | Static HTML/JS; preview + signup/sign-in entry |
| **WASM (Flutter web)** | `/#/…` when session cookie present at `/`, or any deep hash route | Full product |
| **Native app** | AutoRoute paths (`/accept-invite/…`, `/sign/up/…`, …) | Full product |

### Client routes (WASM hash + native)

| Route | Constant | Audience | Server effect |
|-------|----------|----------|---------------|
| Basic invite URL | *(server/landing only)* `/invite/<code>` | Everyone (share + OG) | Preview only |
| Signup-with-invite | `kPathSignUp` → `/sign/up/<code>` | Unauthenticated native; web bounces to landing | Invite **consumed at account creation** |
| Accept-invite | `kPathAcceptInvite` → `/accept-invite/<code>` | Authenticated user, not yet friends | `POST …/accept-as-existing` after confirm |

**WASM deep links** use hash URLs, e.g. `https://tentura.io/#/accept-invite/Iabc123`.
The server only ever sees `/`; no Caddy change is required for landing → app handoff.

## End-to-end flow (overview)

Landing `render()` branches on **`suggestedAction`** from preview JSON (derived from
`codeStatus` + `callerStatus` on the server — not raw `callerStatus` alone). Invalid,
expired, or consumed codes map to `suggestedAction` of the same name and show
`renderInvalid()` with no auth CTAs.

```mermaid
flowchart TB
  subgraph entry["Entry"]
    shareBtn["Share action"] --> basicUrl["Basic invite URL /invite/I…"]
    rootSlash["Signed-out /"] --> pasteOrSignIn["Paste invite OR sign-in reveal"]
    pasteOrSignIn --> basicUrl
    pasteOrSignIn --> rootAuth["Email / Google / recover<br/>(no invite code)"]
  end

  basicUrl --> platform{"How link opens"}

  platform -->|"Browser / iOS / dev / app not installed"| landing["Landing GET preview"]
  platform -->|"Android prod App Link<br/>(OS opens installed app)"| nativeDL["deepLinkTransformer"]

  subgraph landingDispatch["Landing (suggestedAction)"]
    landing --> sa{"suggestedAction"}
    sa -->|"accept-as-new"| anon["Anonymous invite page<br/>Tier1: email+Google+recover<br/>Tier2: email+browser escape"]
    sa -->|"accept-as-existing"| hashAccept["CTA → origin#/accept-invite/I…"]
    sa -->|"already-friends"| openProd1["CTA → origin/"]
    sa -->|"self"| openProd2["CTA → origin/"]
    sa -->|"invalid / expired / consumed"| invalidLanding["Explain; no auth CTA"]
  end

  subgraph newAccount["New account (invite consumed at signup)"]
    anon --> newSignup["Email OTP or Google on landing<br/>(inviteCode in start/OAuth)"]
    newSignup --> signedIn["Redirect /invite/I…?signed_in=1&new=1"]
    signedIn --> nameStep["Landing name step<br/>(PATCH …/me/profile, cookie)"]
    nameStep --> pager["Onboarding 3-page pager<br/>(WASM warms in background)"]
    pager --> openProd3["Open product"]
  end

  subgraph returningOnLanding["Returning user on landing (invite befriended at login)"]
    anon --> returnAuth["Email OTP or Google sign-in<br/>(same page or root / reveal)"]
    returnAuth --> signedIn2["Redirect ?signed_in=1"]
    signedIn2 --> rePreview2["Re-preview → already-friends"]
    rePreview2 --> openProd4["Open product<br/>(no accept-invite)"]
  end

  subgraph seedRecover["Returning user via seed (Tier 1 only)"]
    anon --> recoverWASM["/recover?invite=I…#/recover-seed"]
    recoverWASM --> acceptRoute
  end

  subgraph nativeRoute["Native App Link"]
    nativeDL --> nAuth{"Authenticated<br/>in app?"}
    nAuth -->|"No"| signUpRoute["/sign/up/I… → AuthRegisterScreen<br/>(server consumes invite)"]
    nAuth -->|"Yes"| acceptRoute["/accept-invite/I…"]
  end

  hashAccept --> acceptGuard
  acceptRoute --> acceptGuard

  subgraph acceptGuard["Accept-invite guard"]
    acceptGuard --> gAuth{"Authenticated?"}
    gAuth -->|"Yes"| acceptScreen["AcceptInviteScreen"]
    gAuth -->|"No, web"| leaveWeb["goToLanding /invite/I…<br/>(page unloading)"]
    gAuth -->|"No, native"| signUpRoute
  end

  subgraph acceptFlow["Accept-invite screen"]
    acceptScreen --> previewAPI["GET preview"]
    previewAPI --> decide{"codeStatus + callerStatus"}
    decide -->|"invalid / expired / consumed"| msgBad["Message → home"]
    decide -->|"is-inviter"| msgSelf["Message → home"]
    decide -->|"already-friends"| msgFriends["Message → home"]
    decide -->|"anonymous / stale auth"| bounce["Web → landing<br/>Native → /sign/up/I…"]
    decide -->|"existing-user + available"| dialog["InvitationAcceptDialog"]
    dialog -->|"Cancel"| home["replaceAll → HomeRoute"]
    dialog -->|"Confirm"| postAccept["POST accept-as-existing"]
    postAccept --> home
  end

  openProd1 --> product["WASM / native product<br/>(session cookie or JWT required)"]
  openProd2 --> product
  openProd3 --> product
  openProd4 --> product
  home --> product
  rootAuth --> product
```

**Not shown above (same doc, other sections):** notification `/#/shared/view?id=I…`
uses the same native transform table as App Links; in-app paste/QR uses a separate
GraphQL path (`ConnectBottomSheet`).

## Landing preview dispatcher

The landing calls `GET /api/v2/invite/<code>/preview` (optional-auth: session cookie
and/or bearer). Response drives UI and CTAs in `packages/landing/main.js`.

| `callerStatus` | `suggestedAction` (when code available) | Landing behavior | App URL opened |
|----------------|----------------------------------------|------------------|----------------|
| `anonymous` | `accept-as-new` | **Tier 1:** email OTP, Google, and “Recover from seed” (WASM). **Tier 2:** email + browser escape (card-level escape also shown). **No** generic “Open the app” | `/recover?invite=<code>#/recover-seed` for seed recovery; otherwise stay on landing |
| `existing-user` | `accept-as-existing` | “Open Tentura to accept” | `{origin}#/accept-invite/{code}` |
| `already-friends` | `already-friends` | “Open Tentura” (+ signed-in completion copy when `?signed_in=1`) | `{origin}/` (product only) |
| `is-inviter` | `self` | Share hint + open product | `{origin}/` |

When the code is not available, `suggestedAction` is `invalid`, `expired`, or
`consumed` (regardless of `callerStatus`) and the landing shows `renderInvalid()`.

**Post-signup return (`?signed_in=1&new=1`):** appended by the server only when
a **brand-new account** was created (`CredentialAuthCase.resolveOrCreate` →
`isNewAccount`; logins and credential-links into an existing account never get
it). The landing then shows the **name step** (display name pre-filled from the
server-derived default via `GET …/me/profile`) followed by the **3-page
onboarding pager** (`packages/landing/onboarding.js`), regardless of preview
state — the invite is already consumed. While the user reads, `app_preload.js`
finishes warming WASM assets, so the final "Open Tentura" boots from cache. A
one-shot `sessionStorage` flag (`tentura_post_signup_done`) prevents replay on
reload/back; a shared or replayed `new=1` URL without the session cookie falls
back to the normal render (profile GET returns 401). New accounts with no
invite context redirect to `/invite/?signed_in=1&new=1` (not `/`, which would
route into WASM per ADR 0002).

**Signed-out `/` (no invite code):** `renderNoInvite()` — invite paste is the primary
path. **“I already have an account”** reveals tier-specific sign-in options and hides
the invite paste form and invite-oriented copy. **“Have an invite link?”** restores
invite mode. When `?signed_in=1`, show flash + **Open Tentura** CTA.

**Google OAuth** on the landing includes `returnTo=/invite/<code>` so after sign-in
the user returns to the invite page, re-previews as `already-friends`, and opens the
product without calling accept-as-existing.

**“I already have an account”** (root `/` only) reveals tier-specific login options
instead of opening WASM with a broken `?invite=` query param. Revealing sign-in hides
the invite paste UI to avoid dual-path ambiguity:

- **Tier 1 (system browser):** email magic link + Google OAuth (when `googleEnabled`) + recover-from-seed.
- **Tier 2 (in-app browser):** email magic link + browser escape; Google and recover stay hidden.

On `/invite/<code>` anonymous pages, email/Google/recover remain visible immediately
for new-user signup (no reveal toggle).

## WASM hash routing

Flutter web does **not** use path URL strategy. Relevant implications:

```mermaid
flowchart LR
  subgraph broken["Broken (old)"]
    oldCta["origin?invite=I…"]
    oldCta --> wasmIgnore["AutoRoute ignores root query"]
    wasmIgnore --> lost["Invite code dropped"]
  end

  subgraph fixed["Fixed (current)"]
    newCta["origin#/accept-invite/I…"]
    newCta --> autoRoute["AutoRoute matches path param"]
    autoRoute --> guard["Accept-invite guard"]
  end
```

Landing helpers:

- `appHashUrl(path)` → `{origin}#{path}`
- `openAcceptInviteUrl(code)` → `#/accept-invite/{encoded code}`
- `openProductUrl()` → `{origin}/` only

## Native deep links

`RootRouter.deepLinkTransformer()` normalizes invite entry before navigation:

| Incoming | Authenticated | Transformed path |
|----------|---------------|------------------|
| `/invite/<code>` (App Link) | yes | `/accept-invite/<code>` |
| `/invite/<code>` | no | `/sign/up/<code>` |
| `/shared/view?id=I…` | yes | `/accept-invite/<code>` |
| `/shared/view?id=I…` | no | `/sign/up/<code>` |

Implementation: `packages/client/lib/app/router/invite_deep_link.dart`.

**Platform coverage:**

- **Android prod** (`tentura.io`): verified App Links for all paths including `/invite/…`.
- **Android dev / iOS**: no verified universal link → browser → landing flow.
- **In-app paste/QR**: `ConnectBottomSheet` (separate GraphQL accept path; not this doc’s REST flow).

## Accept-invite guard

Unauthenticated hits to `#/accept-invite/<code>` are resolved in
`packages/client/lib/app/router/accept_invite_guard.dart`:

| Condition | Outcome |
|-----------|---------|
| Authenticated | Allow `AcceptInviteScreen` |
| Web + `goToLanding('/invite/…')` returns `true` | Block navigation (page unloading) |
| Native + `goToLanding` returns `false` | Redirect to `AuthRegisterRoute` (`/sign/up/<code>`) |

`goToLanding` is platform-split: real navigation on web, no-op on native.

## Accept-invite screen state machine

After the guard, `AcceptInviteCubit` always re-fetches preview (defense in depth):

```mermaid
stateDiagram-v2
  [*] --> Loading: start(code)
  Loading --> InvalidMsg: code fails kInvitationCodeRegExp
  Loading --> Preview: valid code
  Preview --> InvalidMsg: codeStatus not available
  Preview --> SelfMsg: is-inviter
  Preview --> FriendsMsg: already-friends
  Preview --> Bounce: anonymous / 401
  Preview --> Confirm: existing-user + available
  Confirm --> Accepting: user confirms dialog
  Confirm --> Home: user cancels
  Accepting --> AcceptedMsg: POST 200
  Accepting --> InvalidMsg: POST 404
  Accepting --> SelfMsg: POST 400
  Accepting --> Bounce: POST 401/403
  InvalidMsg --> Home: replaceAll HomeRoute
  SelfMsg --> Home
  FriendsMsg --> Home
  AcceptedMsg --> Home
  Bounce --> LandingOrSignup: web landing / native sign-up
  Home --> [*]
```

Terminal navigation uses `context.router.replaceAll([const HomeRoute()])` so Back
cannot re-open the accept flow.

## Server API (V2 REST)

| Method | Path | Auth | Role |
|--------|------|------|------|
| `GET` | `/api/v2/invite/<code>/preview` | Optional (cookie or bearer) | Caller-aware preview for landing + accept screen |
| `POST` | `/api/v2/invite/<code>/accept-as-existing` | Bearer JWT required | Befriend issuer + forward beacon; **not** for new signups |
| `GET` | `/api/v2/accounts/me/profile` | Cookie or bearer | `{id, displayName}` of the calling account (landing name-step prefill) |
| `PATCH` | `/api/v2/accounts/me/profile` | Cookie or bearer | Update display name from the landing post-signup step |

### Profile endpoint (canonical spec)

`AccountProfileController`; route guard `extractJwtOrSessionClaims` (Bearer JWT
first, then `__Host-tentura_session` cookie). Exists so the **static landing
can read/write the display name with the session cookie alone — landing JS
never handles JWTs.**

```http
GET /api/v2/accounts/me/profile
→ 200 {"id": "U…", "displayName": "…"}
→ 401 when neither bearer nor session cookie resolves

PATCH /api/v2/accounts/me/profile
Content-Type: application/json
{"displayName": "Ada L."}
→ 200 {"id": "U…", "displayName": "Ada L."}   (value is trimmed first)
→ 400 {"error": …} — missing/non-string or trimmed length outside 3–32
      (`kTitleMinLength`–`kTitleMaxLength`, same as GraphQL `userUpdate`)
→ 401 unauthenticated
```

**CSRF rationale:** the session cookie is `SameSite=Lax`, so cross-site
`PATCH` requests do not carry it; additionally the endpoint only accepts a
JSON body, which plain HTML forms cannot produce. No CSRF token is needed.

Preview JSON fields used by the client: `codeStatus`, `callerStatus`, `inviter`,
`beacon`, `suggestedAction`.

Accept-as-existing outcomes:

| HTTP | Meaning | Client mapping |
|------|---------|----------------|
| 200 | Success or already friends | OK |
| 400 | Self-invite / bad request | `InvitationSelfOrInvalid` |
| 404 | Missing / consumed / expired | `InvitationNoLongerValid` |
| 401/403 | Stale bearer | `InvitationAuthLost` → bounce |

## Who consumes the invite?

```mermaid
flowchart TD
  subgraph consumeAtSignup["Invite consumed at signup"]
    email["Email magic link + invite param"]
    google["Google OAuth + invite param"]
    nativeReg["Native AuthRegisterScreen<br/>signUp(invitationCode:)"]
  end

  subgraph consumeAtAccept["Invite consumed at accept"]
    accept["POST accept-as-existing<br/>after InvitationAcceptDialog"]
  end

  newUser["New account"] --> consumeAtSignup
  existingUser["Existing signed-in user"] --> consumeAtAccept

  consumeAtSignup --> neverAccept["Must NOT call accept-as-existing<br/>(would 404)"]
```

## Corner cases (deliberate)

| Scenario | Behavior |
|----------|----------|
| New web user (email/Google) | Never reaches accept-invite; server consumed invite at signup; landing shows name step + onboarding (`new=1`) |
| Google merging into existing account via verified contact | Credential **link**, not signup: no `new=1`, no name step (existing display name preserved) |
| Web onboarding vs WASM intro | Web never shows `IntroScreen` (intro guards are `!kIsWeb`); native keeps the 3-page intro with the same copy |
| Returning user via WASM seed recovery | Recovery sign-in → `#/accept-invite/…` → accept-as-existing |
| Double-tap / refresh on `#/accept-invite/…` | Preview + confirm again; first accept wins; later 404 is non-fatal |
| Self-invite | Preview `is-inviter` short-circuit; POST 400 handled defensively |
| Already friends | Preview short-circuit; POST 200 safe if race |
| Malformed code | `kInvitationCodeRegExp` fails client-side; no server call |
| Stale JWT at accept screen | Preview `anonymous` or GET 401 → bounce; no POST |
| Seed recovery + invite | Landing `/recover?invite=I…#/recover-seed` → WASM recover → `#/accept-invite/I…` |
| Notification deep link `/#/shared/view?id=I…` | Transformed like App Link (see table above) |

## Key source files

| Area | Path |
|------|------|
| Route constants | `packages/client/lib/consts.dart` |
| Deep link transforms | `packages/client/lib/app/router/invite_deep_link.dart` |
| Accept guard logic | `packages/client/lib/app/router/accept_invite_guard.dart` |
| Router + guard wiring | `packages/client/lib/app/router/root_router.dart` |
| Preview entity | `packages/client/lib/features/invitation/domain/entity/invite_preview.dart` |
| Repository (preview + accept) | `packages/client/lib/features/invitation/data/repository/invitation_repository.dart` |
| Accept cubit + screen | `packages/client/lib/features/invitation/ui/bloc/accept_invite_cubit.dart`, `…/screen/accept_invite_screen.dart` |
| Landing CTAs | `packages/landing/main.js` |
| Landing post-signup (name + onboarding) | `packages/landing/onboarding.js` |
| Profile REST controller | `packages/server/lib/api/controllers/account_profile_controller.dart` |
| Native 3-page intro | `packages/client/lib/features/intro/ui/screen/intro_screen.dart` |
| Server preview | `packages/server/lib/domain/use_case/invitation_case.dart`, `…/entity/invite_preview_result.dart` |

## Tests

| Suite | Path |
|-------|------|
| Deep link transforms | `packages/client/test/app/invite_deep_link_test.dart` |
| Guard decisions | `packages/client/test/app/accept_invite_guard_test.dart` |
| Preview parsing + status maps | `packages/client/test/features/invitation/invite_preview_test.dart`, `invitation_repository_accept_test.dart` |
| Accept cubit outcomes | `packages/client/test/features/invitation/accept_invite_cubit_test.dart` |
| Landing URL construction | `packages/landing/test/url_dispatch_test.mjs` |
| Landing post-signup flow | `packages/landing/test/onboarding_test.mjs` |
| Profile endpoint | `packages/server/test/api/controllers/account_profile_controller_test.dart` |
| isNewAccount propagation | `packages/server/test/domain/use_case/credential_auth_case_test.dart`, `…/oidc_case_test.dart`, `…/email_auth_case_test.dart`, `packages/server/test/api/http/oauth_return_uri_test.dart` |

## Manual smoke checklist

- [ ] Signed-out `/` (no cookie): landing with invite paste; sign-in behind **“I already have an account”** reveal; no default “Open Tentura”
- [ ] Signed-out `/`: paste invite code/link → redirects to `/invite/I…` preview
- [ ] Signed-in desktop web: `/invite/I…` → landing → `#/accept-invite/I…` → confirm → home once
- [ ] Signed-out web: `/invite/I…` → landing signup only → after signup, product (no accept-as-existing)
- [ ] New signup: lands on `?signed_in=1&new=1` → name step (pre-filled) → 3-page pager → Open Tentura boots from cache, no WASM intro
- [ ] Existing-user sign-in: no `new=1`, no name step; reload after onboarding does not replay it
- [ ] Android prod App Link, authed: preview → confirm → accept; anon → register
- [ ] iOS / dev host: browser landing fallback; in-app paste/QR still works
- [ ] After success: refresh / Back does not repeat befriending

## Related documents

- [`CONTEXT.md`](../CONTEXT.md) — vocabulary (basic invite URL, signup-with-invite route, accept-invite route)
- [`adr/0002-root-session-routing.md`](adr/0002-root-session-routing.md) — cookie-presence routing at `/`
- [`adr/0009-landing-sentry-observability.md`](adr/0009-landing-sentry-observability.md) — landing funnel observability
