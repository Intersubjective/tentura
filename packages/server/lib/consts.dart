import 'dart:io' show Platform;

import 'package:tentura_root/consts.dart';

export 'package:tentura_root/consts.dart';

const kContextJwtKey = 'contextJwt';

/// Max accepted bytes for an uploaded image (avatars, beacon images). Larger
/// uploads are rejected before they reach object storage. Kept in step with
/// `kMaxRoomMessageAttachmentBytes` so no single upload field is unbounded.
const kMaxImageUploadBytes = 10 * 1024 * 1024;

const kSentryRequestContextKey = 'sentryRequestContext';

final kInvitationTTL = Duration(
  hours:
      int.tryParse(Platform.environment['INVITATION_TTL'] ?? '') ??
      kInvitationDefaultTTL,
);

/// Part of FQDN before path: `https://app.server.name`
final kServerName = Platform.environment['SERVER_NAME'] ?? '';

/// Part of FQDN before path: `https://image.server.name`
final kImageServer = Platform.environment['IMAGE_SERVER'] ?? '';

final kAvatarPlaceholderUrl =
    '$kImageServer/$kImagesPath/placeholder/avatar.$kImageExt';

final kBeaconPlaceholderUrl =
    '$kImageServer/$kImagesPath/placeholder/beacon.$kImageExt';
