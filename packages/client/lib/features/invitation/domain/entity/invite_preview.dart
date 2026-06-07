/// Caller-aware invite preview from `GET /api/v2/invite/:code/preview`.
class InvitePreview {
  const InvitePreview({
    required this.codeStatus,
    required this.callerStatus,
    this.inviter,
    this.beacon,
  });

  factory InvitePreview.fromJson(Map<String, dynamic> json) => InvitePreview(
    codeStatus: InviteCodeStatusX.fromWire(json['codeStatus'] as String? ?? ''),
    callerStatus: InviteCallerStatusX.fromWire(
      json['callerStatus'] as String? ?? '',
    ),
    inviter: json['inviter'] == null
        ? null
        : InvitePreviewInviter.fromJson(
            (json['inviter'] as Map).cast<String, dynamic>(),
          ),
    beacon: json['beacon'] == null
        ? null
        : InvitePreviewBeacon.fromJson(
            (json['beacon'] as Map).cast<String, dynamic>(),
          ),
  );

  final InviteCodeStatus codeStatus;
  final InviteCallerStatus callerStatus;
  final InvitePreviewInviter? inviter;
  final InvitePreviewBeacon? beacon;

  bool get isAvailable => codeStatus == InviteCodeStatus.available;
}

enum InviteCodeStatus { available, consumed, expired, invalid }

extension InviteCodeStatusX on InviteCodeStatus {
  static InviteCodeStatus fromWire(String wire) => switch (wire) {
    'available' => InviteCodeStatus.available,
    'consumed' => InviteCodeStatus.consumed,
    'expired' => InviteCodeStatus.expired,
    _ => InviteCodeStatus.invalid,
  };
}

enum InviteCallerStatus {
  anonymous,
  existingUser,
  alreadyFriends,
  isInviter,
}

extension InviteCallerStatusX on InviteCallerStatus {
  static InviteCallerStatus fromWire(String wire) => switch (wire) {
    'anonymous' => InviteCallerStatus.anonymous,
    'existing-user' => InviteCallerStatus.existingUser,
    'already-friends' => InviteCallerStatus.alreadyFriends,
    'is-inviter' => InviteCallerStatus.isInviter,
    _ => InviteCallerStatus.anonymous,
  };
}

class InvitePreviewInviter {
  const InvitePreviewInviter({
    required this.id,
    required this.displayName,
    this.imageUrl,
  });

  factory InvitePreviewInviter.fromJson(Map<String, dynamic> json) =>
      InvitePreviewInviter(
        id: json['id'] as String? ?? '',
        displayName: json['displayName'] as String? ?? '',
        imageUrl: json['image'] as String?,
      );

  final String id;
  final String displayName;
  final String? imageUrl;
}

class InvitePreviewBeacon {
  const InvitePreviewBeacon({
    required this.title,
    this.snippet,
  });

  factory InvitePreviewBeacon.fromJson(Map<String, dynamic> json) =>
      InvitePreviewBeacon(
        title: json['title'] as String? ?? '',
        snippet: json['snippet'] as String?,
      );

  final String title;
  final String? snippet;
}
