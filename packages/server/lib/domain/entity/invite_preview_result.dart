import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';

/// What an invite code means at the moment of preview (reuse
/// `InvitationEntity.isAccepted` / `InvitationEntity.isExpired`). No `revoked`
/// state is modeled in Phase 0 — a deleted invitation row reads back as
/// [InviteCodeStatus.invalid].
enum InviteCodeStatus { available, consumed, expired, invalid }

/// Who the caller is relative to the invite issuer. Anonymous when the request
/// carries no (non-anon) JWT; self-invite is surfaced as [isInviter] and blocked.
enum InviteCallerStatus { anonymous, existingUser, alreadyFriends, isInviter }

/// Read-only result of `InvitationCase.preview` — decides what an invite means
/// for a specific caller before any UI loads. Serialized by
/// `InvitePreviewController`.
class InvitePreviewResult {
  const InvitePreviewResult({
    required this.codeStatus,
    required this.callerStatus,
    this.inviter,
    this.beacon,
  });

  final InviteCodeStatus codeStatus;
  final InviteCallerStatus callerStatus;

  /// The invite issuer; null only when the code is invalid.
  final UserEntity? inviter;

  /// Present when the invite can show beacon details or a lapsed Request title.
  final InvitePreviewBeacon? beacon;

  /// Hint the landing uses to pick the primary CTA. Derived, not stored.
  String get suggestedAction {
    if (codeStatus == InviteCodeStatus.invalid) return 'invalid';
    switch (callerStatus) {
      case InviteCallerStatus.isInviter:
        return 'self'; // self-invite blocked
      case InviteCallerStatus.alreadyFriends:
        return 'already-friends';
      case InviteCallerStatus.existingUser:
        return codeStatus == InviteCodeStatus.available
            ? 'accept-as-existing'
            : codeStatus.name; // consumed | expired
      case InviteCallerStatus.anonymous:
        return codeStatus == InviteCodeStatus.available
            ? 'accept-as-new'
            : codeStatus.name; // consumed | expired
    }
  }

  Map<String, Object?> toJson() => {
    'inviter': inviter == null
        ? null
        : {
            'id': inviter!.id,
            'displayName': inviter!.displayName,
            'image': inviter!.hasImage ? inviter!.imageUrl : null,
          },
    'codeStatus': codeStatus.name,
    'callerStatus': _callerStatusJson,
    if (beacon case final preview?) 'beacon': preview.toJson(),
    'suggestedAction': suggestedAction,
  };

  String get _callerStatusJson => switch (callerStatus) {
    InviteCallerStatus.anonymous => 'anonymous',
    InviteCallerStatus.existingUser => 'existing-user',
    InviteCallerStatus.alreadyFriends => 'already-friends',
    InviteCallerStatus.isInviter => 'is-inviter',
  };
}

class InvitePreviewBeacon {
  const InvitePreviewBeacon.visible({
    required this.id,
    required this.kind,
    required this.title,
    required this.description,
  }) : lapsed = false;

  const InvitePreviewBeacon.lapsedRequest({
    required this.id,
    required this.title,
  }) : kind = BeaconKind.request,
       description = '',
       lapsed = true;

  final String id;
  final BeaconKind kind;
  final String title;
  final String description;
  final bool lapsed;

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind == BeaconKind.post ? 'post' : 'request',
    'title': title,
    'snippet': _snippet(description),
    'description': description.trim(),
    'lapsed': lapsed,
  };

  static String _snippet(String description, {int max = 140}) {
    final trimmed = description.trim();
    return trimmed.length <= max ? trimmed : '${trimmed.substring(0, max)}…';
  }
}
