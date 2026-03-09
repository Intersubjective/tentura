import 'dart:io' show Platform;

import 'package:tentura_root/consts.dart';

export 'package:tentura_root/consts.dart';

const kContextJwtKey = 'contextJwt';

final kInvitationTTL = Duration(
  hours:
      int.tryParse(Platform.environment['INVITATION_TTL'] ?? '') ??
      kInvitationDefaultTTL,
);

/// Part of FQDN before path: `https://app.server.name`
final kServerName =
    Platform.environment['SERVER_NAME'] ?? 'http://localhost:2080';

/// Part of FQDN before path: `https://image.server.name`
final kImageServer = Platform.environment['IMAGE_SERVER'] ?? '';

final kAvatarPlaceholderUrl =
    '$kImageServer/$kImagesPath/placeholder/avatar.$kImageExt';

final kBeaconPlaceholderUrl =
    '$kImageServer/$kImagesPath/placeholder/beacon.$kImageExt';
