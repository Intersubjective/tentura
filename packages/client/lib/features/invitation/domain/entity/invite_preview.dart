import 'package:tentura/consts.dart';

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

  /// The id of the inviter's photo, read back from [imageUrl] (the server
  /// sends the URL it builds as `…/images/<userId>/<imageId>.jpg`), so the
  /// app can show it like any other avatar (#388). Null when there is no
  /// photo or the URL is not this inviter's.
  String? get imageId {
    final url = imageUrl;
    if (url == null) return null;
    final segments = Uri.tryParse(url)?.pathSegments ?? const <String>[];
    if (segments.length < 3) return null;
    final [folder, userId, file] = segments.sublist(segments.length - 3);
    const suffix = '.$kImageExt';
    if (folder != kImagesPath || userId != id || !file.endsWith(suffix)) {
      return null;
    }
    final imageId = file.substring(0, file.length - suffix.length);
    return imageId.isEmpty ? null : imageId;
  }
}

class InvitePreviewBeacon {
  const InvitePreviewBeacon({
    required this.id,
    required this.title,
    this.snippet,
  });

  factory InvitePreviewBeacon.fromJson(Map<String, dynamic> json) =>
      InvitePreviewBeacon(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        snippet: json['snippet'] as String?,
      );

  final String id;
  final String title;
  final String? snippet;
}
