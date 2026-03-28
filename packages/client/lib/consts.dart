import 'package:tentura_root/consts.dart';

export 'package:tentura_root/consts.dart';

// Numbers
const kMaxLines = 3;
const kCommentsShown = 3;
const kFetchWindowSize = 5;
const kSnackBarDuration = 5;
const kFetchListOffset = 0.9;
const kImageMaxDimension = 600;

// Strings
//   Routes
const kPathBack = '/back';
const kPathHome = '/home';
const kPathMyField = '/home/field';
const kPathFriends = '/home/friends';
const kPathProfile = '/home/profile';
const kPathFavorites = '/home/favorites';
const kPathChat = kPathAppLinkChat;
const kPathGraph = '/graph';
const kPathRating = '/rating';
const kPathSignIn = '/sign/in';
const kPathSignUp = '/sign/up';
const kPathSettings = '/settings';
const kPathComplaint = '/complaint';
const kPathInbox = '/home/inbox';
const kPathMyWork = '/home/work';
const kPathNetwork = '/home/network';
const kPathBeaconNew = '/beacon/new';
const kPathBeaconView = '/beacon/view';
const kPathBeaconViewAll = '/beacon/all';
const kPathForwardBeacon = '/forward';
const kPathProfileEdit = '/profile/edit';
const kPathProfileView = '/profile/view';
const kPathInvitations = '/invitations';

const kQueryIsDeepLink = 'is_deep_link';

/// First part of FQDN: `https://app.server.name`
const kServerName = String.fromEnvironment(
  'SERVER_NAME',
  defaultValue: 'http://localhost:2080',
);

/// WebSocket server base URL; defaults to [kServerName].
/// In dev without a reverse proxy, set to the Tentura API directly
/// (e.g. `http://localhost:2080`) since Flutter's dev server cannot proxy WS.
const kWsServerName = String.fromEnvironment(
  'WS_SERVER_NAME',
  defaultValue: kServerName,
);

/// First part of FQDN: `https://image.server.name`
const kImageServer = String.fromEnvironment('IMAGE_SERVER');

const kAvatarPlaceholderUrl =
    '$kImageServer/$kImagesPath/placeholder/avatar.$kImageExt';

const kBeaconPlaceholderUrl =
    '$kImageServer/$kImagesPath/placeholder/beacon.$kImageExt';

// Others

const kFastAnimationDuration = Duration(milliseconds: 250);

final kZeroAge = DateTime.fromMillisecondsSinceEpoch(0);

final kInvitationCodeRegExp = RegExp('I[a-f0-9]{0,12}');
