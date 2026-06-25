---
name: Capability Non-ML Overhaul — phase progress
description: 5-phase non-ML capability system (private labels, forward reasons, commit roles, close acks); Phase 0 done
type: project
---

Active plan in `plan.md`. Phases 0–4 defined.

**Phase 0 — DONE (2026-04-30)**
- `docs/adr/0001-capability-event-storage.md` created
- `NetworkPersonCard` widget shell created at `packages/client/lib/features/capability/ui/widget/network_person_card.dart`
- `FriendsScreen._FriendsTabBody` replaced `ChatPeerListTile` with `NetworkPersonCard`
- `// DISABLED: capability-rework` comment added to `chat_peer_list_tile.dart`
- `screen_cubit.dart` comment added above `showChatWith`
- Client bumped 1.24.0 → 1.25.0

**Why:** Non-ML capability signals from 4 observer sources. No self-declared chips. All ops via V2 GraphQL.

**How to apply:** Next phase is Phase 1 (private labels + server table migration m0048). Read ADR 0001 and `docs/README.md` before starting.

**Phase 1 — PENDING**
- Server: migration m0048, CapabilityCase, CapabilityRepositoryPort, repo, GQL ops
- Client: capability domain (CapabilityTag, CapabilityGroup, CapabilityEventSource, PersonCapabilityCues), V2 op names, l10n, CapabilityChipSet, EditPrivateLabelsDialog, ProfileViewCubit extension, NetworkPersonCard cue strip
