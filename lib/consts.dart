const kIdLength = 13;

const kCodeLength = 7;

const kTitleMinLength = 3;

const kTitleMaxLength = 32;

const kDescriptionLength = 2048;

const kCommentsShown = 3;

const kMaxLines = 3;

const kAppTitle = 'Tentura';

const kZeroNodeId = 'U000000000000';

const kSettingsThemeMode = 'themeMode';

const kSettingsIsIntroEnabledKey = 'isIntroEnabled';

const kAppLinkBase = String.fromEnvironment('APP_LINK_BASE');

const kApiUri = String.fromEnvironment(
  'API_URI',
  defaultValue: 'https://$kAppLinkBase',
);

const kOsmUrlTemplate = String.fromEnvironment(
  'OSM_LINK_BASE',
  defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
);

const kJwtExpiresIn = Duration(
  seconds: int.fromEnvironment(
    'JWT_EXPIRES_IN',
    defaultValue: 3600,
  ),
);

const kSnackBarDuration = Duration(seconds: 5);
