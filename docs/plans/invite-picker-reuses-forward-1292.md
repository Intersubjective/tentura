# #1292 Post→Request invite step: real names, reuse the Forward picker

Status: planned (2026-11-15). Epic: see beads labelled `issue-1292`. Runs after epic tentura-gkcp (#1288) because both touch the ARB files, the docs and the version.

## Symptom

On step 2 of budding a Request from a Post («Кого позвать» / «Who to invite»), most rows show «Неизвестный человек» and «?» instead of an avatar. Posts with up to about 10 members look fine.

## Root cause

- `postBudInviteCandidates` returns ids only (`userId`, `viaUserId` and flags).
- `PostBudCase.inviteStep` (`packages/client/lib/domain/use_case/post_bud_case.dart:46-61`) resolves all of them in one `ProfileRepository.fetchProfilesByIds` call (`profile_repository.dart:55`), which runs Hasura `user(where:{id:{_in:$ids}})`.
- The `user` select permission for role `user` has `"limit": 10` (`hasura/metadata.json:1204`). Hasura silently returns at most 10 rows, in no fixed order.
- A missing id renders as `unknownPerson` with an empty avatar (`post_bud_invite_step.dart:138-152`).

Evidence from the local stack (read-only): 25 existing ids returned 10 rows as `user` and 25 as admin. A 4-member Post resolves all members, the cold «через X» ones included, so the row filter is not the cause (it only hides blocked users).

The cap is deliberate: it bounds user search (`docs/plans/user-block-design.md`). So the metadata stays as it is.

## Decisions

- **D1. Fix the data path in the repository, for every caller.** `fetchProfilesByIds` requests ids in chunks no larger than the Hasura `user` limit. A named constant holds the size, and a `repo-files` test keeps it equal to the metadata value. The chunks run concurrently and their rows are merged. This also fixes the same silent cut-off in:
  - `AttentionActorProfilesCase` (Activity avatars)
  - `PeopleTagProfiles.ensure`
  - `GraphCubit` peer refresh
  - `ForwardCase` lineage extras and preview
- **D2. One picker.** The invite step becomes `ForwardRecipientPicker` + `ForwardCubit`, set up for this use by a new `ForwardTargetProfile.postBudInvite`. The existing profile getters (`showsBand`, `showsReasons`, `showsLineage`, `showsAttribution`, `showsRequirements`, `nudgesOfferHelp`) are already the switch mechanism. Add getters for:
  - the invite-a-new-person bar
  - tag chips
  - scope links
  - the shared note and the send composer
- **D3. Candidate source.** For this profile, `ForwardCubit` loads its list from `ForwardCase.loadPostBudInviteCandidates(postId)` instead of `forwardCandidates`.
  - The list holds the invitable Post members only, in server order (writers first).
  - Warm members get `ForwardReach(kind: direct)`. Members with a «через X» person get `ForwardReach(kind: viaConnection, via: [X])`.
  - The first load ticks `autoSelectIds` = the server's `pretick`.
  - The cubit gets no beacon id (`''`), so there is no involvement data and no «already forwarded» markers.
- **D4. What stays bud-specific.** Owner: `BeaconCreateCubit`.
  - Kept: «Close the post» (author only), the facts checklist (step 1), and submitting.
  - Picker `header`: the explanation and the «many invites» warning.
  - Screen bottom bar: «Оформить запрос».
  - `submitBud` takes the invitees (ticked ids + per-person notes) from the `ForwardCubit`.
  - `PostBudForm` loses `candidates`, `profiles`, `selectedIds`, `notes`, `candidatesLoaded` and `candidatesFailed`.
  - `canClosePost` becomes «the budder is the Post's author».
- **D5. Off for invites.** The invite-new-person bar, band, lineage, tag chips, «Not yet seen / Already involved» scope links, forward reasons, attribution dialog, shared note and the picker's send composer.
- **D6. On for invites.** Search, multi-select, one optional note per person (hint `postBudInviteNoteHint`), the reach «через X» line, the person row and its context sheet, and availability blocking (a paused person cannot be ticked, as in Forward).
- **D7. Delete the old list.** `_InviteeRow`, the invite `ListView` in `PostBudInviteStep`, `PostBudCase.inviteStep` and its `PostBudInviteStep` typedef are deleted, and the ARB keys that end up unused go too.

## Reuse contract (blocking in every bead)

Extend these; never create a parallel picker, row, list or cubit:
- `ForwardRecipientPicker` (`features/forward/ui/widget/forward_recipient_picker.dart`)
- `ForwardRecipientRow` / `ForwardRecipientPickerEntry`
- `ForwardCubit` / `ForwardState`
- `ForwardCase`
- `ForwardTargetProfile`

The verifier rejects a diff that adds:
- a new recipient row or list widget
- a new picker cubit
- a copy of picker code

## Units

| # | Unit | Area | Complexity |
|---|------|------|------------|
| 1 | `fetchProfilesByIds` chunks by the Hasura user limit, plus a regression test | client data | medium |
| 2 | `ForwardTargetProfile.postBudInvite`, `ForwardCase.loadPostBudInviteCandidates`, cubit routing + pre-tick | client domain/cubit | complex |
| 3 | Picker honours the profile: features off/on (D5/D6), invite empty state | client UI | complex |
| 4 | Bud invite step = embedded picker; `PostBudForm`/`submitBud` rewired; old list and `inviteStep` deleted | client UI + cubit | complex |
| 5 | L10n RU/EN: invite empty state, dead keys removed, 375×667 RU check | client l10n | medium |
| 6 | Web integration: a 12-member Post, every invite row named, invite two, Request created | e2e | fast-track |
| 7 | Docs: budding design + `beacon_room.md` invite-step paragraph, plan status | docs | simple |
| 8 | Ship: next patch version, ship recipe | ship | simple |

Order: 1 → 2 → 3 → 4 → {5, 7} → 6 (after 5) → 8 (after 5, 6, 7). Unit 1 waits for tentura-gkcp's ship bead.

## Sibling matrix (summary)

| Row | Decision |
|---|---|
| surface | Bud invite step (picker); the D1 callers: Activity actors, people tags, Field peers, Forward lineage |
| role | Budder is the Post author (close-post offered) or a co-member (not offered) |
| state | Open Post; Post with forwarding off (D4 warnings unchanged); paused member (unpickable) |
| freshness | Cold open of the step; members load failure (picker error panel + retry) |
| width / locale | 375×667 RU and desktop EN widget tests (unit 5) |
| input | Mouse/touch tick and search in the web integration test (unit 6) |

## Open questions

1. An alternative to D1 is to have the server return profiles inline in `postBudInviteCandidates`: add `user` / `viaUser` fields of the public user type, as `forwardCandidates` does. That takes one round trip instead of N/10, but adds a wire field. This plan keeps D1, which is client-only and also fixes the sibling callers.
2. Should tag chips stay, limited to tag members who are also Post members? The plan turns them off (D5).
3. Should unit 1 ship on its own before #1288 to give relief sooner? The plan keeps the epic block order.
