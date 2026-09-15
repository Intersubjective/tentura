# Issue #166 — Add-friend / accept-invite link dead on cold screen until F5

**GitHub:** [Intersubjective/tentura#166](https://github.com/Intersubjective/tentura/issues/166)  
**Parent:** [#142](https://github.com/Intersubjective/tentura/issues/142)  
**Related:** [#73](https://github.com/Intersubjective/tentura/issues/73) (relationship changes without reload), [#97](https://github.com/Intersubjective/tentura/issues/97) (invite identity / canonical naming on People)

**Source:** 2026-09-14 product testing (participant note 1)

## Symptom

On a **cold** product surface (fresh WASM load or first navigation after landing handoff), the **add friend** path — opening the shared invite and accepting as an **existing** signed-in user — **appears to do nothing**. After **F5**, the same flow succeeds (confirmation dialog → befriending).

## User-facing expectation

- From landing `suggestedAction: accept-as-existing`, follow **Open Tentura to accept** (`origin#/accept-invite/<code>`).
- Without manual reload: preview → **Accept friend invitation?** → `POST accept-as-existing` → home (or inbox handoff for beacon invites).
- If the session is not ready, show a **retryable** error — not a silent no-op or wrong signup detour.

## Product path (invite → add person / friend)

| Step | Surface | Path / API |
|------|---------|------------|
| Share URL | Landing + messengers | `/invite/<code>` |
| Existing-user CTA | Landing `main.js` | `ctaOpenAcceptInvite` → `#/accept-invite/<code>` |
| Route | Client | `kPathAcceptInvite` → [`AcceptInviteScreen`](../../packages/client/lib/features/invitation/ui/screen/accept_invite_screen.dart) |
| Guard | [`accept_invite_guard.dart`](../../packages/client/lib/app/router/accept_invite_guard.dart) | Authenticated → screen; unauthenticated web → landing |
| Preview | Client REST | `GET /api/v2/invite/<code>/preview` via [`InvitationRepository.fetchInvitePreview`](../../packages/client/lib/features/invitation/data/repository/invitation_repository.dart) |
| Befriend | Server + client | `POST /api/v2/invite/<code>/accept-as-existing` via [`acceptExistingInvite`](../../packages/client/lib/features/invitation/data/repository/invitation_repository.dart) |
| Confirm UI | Dialog | [`InvitationAcceptDialog`](../../packages/client/lib/features/invitation/ui/dialog/invitation_accept_dialog.dart) (`confirmFriendAccept` / beacon copy) |

**Note:** In-app **Trust this user** on profiles/graph is a separate like/trust mutation ([`ProfileViewCase.addFriend`](../../packages/client/lib/features/profile_view/domain/use_case/profile_view_case.dart)); QA note 1 is aligned with the **invite link** handoff above (landing → accept-invite), not the forward **invite new person** bar.

Full map: [`docs/invite-signup-landing-flow.md`](../../docs/invite-signup-landing-flow.md).

## Cold-start orchestration (client)

| Component | Behavior on cold `#/accept-invite/…` |
|-----------|----------------------------------------|
| [`AcceptInviteScreen`](../../packages/client/lib/features/invitation/ui/screen/accept_invite_screen.dart) | `initState` → single `postFrameCallback` → `AcceptInviteCubit.start(id)` — **no** auth listener, **no** retry |
| [`AcceptInviteCubit.start`](../../packages/client/lib/features/invitation/ui/bloc/accept_invite_cubit.dart) | Preview once; `InvitationAuthLost` → `_bounceUnauthenticated` |
| Preview 401/403 | [`mapPreviewAuthStatus`](../../packages/client/lib/features/invitation/data/repository/invitation_repository.dart) → `InvitationAuthLost` |
| Auth loss handling | Sets `pendingSignupCode` (native) or `goToLanding` (web) — same branch as **anonymous** caller |
| JWT for preview | [`getAuthenticatedJson`](../../packages/client/lib/data/service/remote_api_client/remote_api_client_base.dart) always sends Bearer from `getAuthToken()` |

**Race class:** User is authenticated in product terms (session cookie / account picked) but the **first** preview runs while Bearer is missing or rejected → treated as logged-out → signup bounce or empty terminal state. Remount (F5) runs `start` again after `AuthCubit` bootstrap + `signIn` completed → preview returns `existing-user` → dialog works.

## Root cause (system)

1. **Single-shot `start()`** on accept-invite screen with no subscription to `AuthCubit` / token readiness.
2. **`InvitationAuthLost` on preview** is handled like **anonymous** (`pendingSignupCode` / landing), not as a **transient** authenticated failure — no automatic retry and no retryable error surface.
3. **Empty UI** after bounce: builder shows `SizedBox.shrink()` when not loading and not awaiting confirmation — matches “link did nothing” until reload.

## #73 / #97 overlap

- **#73:** Broader “relationship / coordination without F5” theme; this issue is the **invite accept** entry slice (befriending via link), not realtime graph/list projection.
- **#97:** Display-name / People invite identity; does not change accept-invite mechanics — only copy and post-accept presentation.

## Observed test run (2026-09-15)

**Command:**

```bash
cd packages/client && ../../scripts/run_with_test_cleanup.sh --timeout 10m -- flutter test \
  test/features/invitation/issue_166_accept_invite_cold_auth_test.dart \
  --dart-define=ENV=test \
  --dart-define-from-file=env/test.env
```

**Result:** `+1 -1` (regression pin green; acceptance red).

| Test | Result | Meaning |
|------|--------|---------|
| `regression: first preview success reaches confirmation dialog state` | Pass | Happy path cubit contract intact |
| `transient preview auth loss recovers to befriending without remount (issue #166)` | **Fail** | After first `InvitationAuthLost`, state stays `pendingSignupCode=…` with `needsConfirmation == false`; no second preview / accept |

## Expected behavior (fix acceptance)

- Cold `#/accept-invite/<code>` for a signed-in user completes befriending without F5.
- Engineering options: defer preview until JWT ready; retry preview on auth stream; distinguish auth-loss vs anonymous in cubit/screen; surface retryable error instead of signup detour for authenticated sessions.

## Files touched (TDD only)

- `packages/client/test/features/invitation/issue_166_accept_invite_cold_auth_test.dart` — failing acceptance + regression pin
- `docs/plans/qa-2026-09-14-engineering/issue-166-anamnesis.md` — this note

**No production code changes** in this pass.
