const kIdLength = 13;
const kCodeLength = 7;
const kTitleMinLength = 3;
const kTitleMaxLength = 32;
const kDescriptionLength = 2048;

const kSnackBarDuration = Duration(seconds: 5);

const kAppTitle = 'Tentura';
const kZeroNodeId = 'U000000000000';
const kAppLinkBase = String.fromEnvironment('APP_LINK_BASE');
const kOsmLinkBase = String.fromEnvironment(
  'OSM_LINK_BASE',
  defaultValue: 'tile.openstreetmap.org',
);
const kJwtExpiresIn = Duration(
  seconds: int.fromEnvironment(
    'JWT_EXPIRES_IN',
    defaultValue: 3600,
  ),
);

final zeroDateTime = DateTime.fromMillisecondsSinceEpoch(0);
