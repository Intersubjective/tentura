# ADR 0005: Unified avatar system

## Status

Accepted (2026-06-19)

## Context

The client had two parallel avatar families (`AvatarRated` with MeritRank chrome and `TenturaAvatar` as a plain identifier), ad-hoc size constants across ~30 call sites, and inconsistent author/self decoration (e.g. beacon People tab author row at 18px with star but no halo, coordination footer at 16px with neither).

Clean Architecture requires the design-system layer to stay inward-only (no `ProfileCubit`, no feature imports).

## Decision

1. **One humble DS widget:** evolve `TenturaAvatar` with `TenturaAvatarSize` buckets (`big` / `medium` / `small` / `tiny`) resolved from `TenturaTokens`, plus plain-bool flags `showAuthorStar`, `isSelf`, `withRating`, `withContactBadge`, and `overlayBadge`.
2. **Self resolution at the UI boundary:** keep a single `SelfAwareAvatar` wrapper that reads `ProfileCubit` and passes `isSelf` into `TenturaAvatar`. Call sites never import `ProfileCubit` for avatars.
3. **Retire** `AvatarRated`, `AuthorStarAvatar`, `PlainMiniAvatar`, `SelfAwarePlainMiniAvatar`; fold painters into `TenturaAvatar`. Relocate `TenturaIcons` into `design_system/` for DS purity.
4. **Remove** `cardAvatarSize` token; list rows use `avatarSize` (medium).
5. **Facepiles:** `OverlappingPeopleAvatars` computes per-face `isSelf` / `showAuthorStar` from `selfUserId` + `starredProfileId`; self slot paints above other profile slots; `+N` stays topmost.

## Consequences

- All avatar sizes and semantics are discoverable from one widget + four tokens (`avatarSize`, `metadataAvatarSize`, `avatarTinySize`, fixed big=160).
- MeritRank decoration is opt-in; personal avatars stay plain by default (rating never shown on the signed-in user's avatar in product usage).
- Feature-specific rings (graph help-offerer, forward-row neighbor) remain compositions wrapping `TenturaAvatar`, not DS flags.
- Golden tests for beacon room / my work / beacon view may need regeneration when avatar sizes change.
