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
const kPathFriends = '/home/friends';
const kPathProfile = '/home/profile';
const kPathGraph = '/graph';
const kPathInviteGenealogy = '/invite-genealogy';

/// When set, [kPathInviteGenealogy] shows the pairwise lineage between the
/// viewer and this target user id (else the viewer's own genealogy).
const kQueryGenealogyWith = 'with';
const kPathForwardsGraph = '/graph/forwards';
const kPathRating = '/rating';
const kPathSignIn = '/sign/in';
const kPathSignUp = '/sign/up';
const kPathRecover = '/recover-seed';
const kPathAcceptInvite = '/accept-invite';
const kPathSettings = '/settings';
const kPathSignInMethods = '/settings/sign-in-methods';

/// Flash after Settings credential link redirect (`google`, `email`, `conflict`).
const kQueryCredentialLinked = 'linked';
const kPathComplaint = '/complaint';
const kPathInbox = '/home/inbox';
const kPathInboxRejected = '$kPathInbox/rejected';
const kPathNotifications = '/notifications';
const kPathNotificationSettings = '/settings/notifications';
const kPathDebugSettings = '/settings/debug';
const kPathMyWork = '/home/work';
const kPathNetwork = '/home/network';
const kPathBeaconNew = '/beacon/new';
const kPathBeaconView = '/beacon/view';
const kPathBeaconViewAll = '/beacon/all';
const kPathBeaconInvolvedAll = '/beacon/involved';
const kPathBeaconRoom = '/beacon/room';
const kPathReviewContributions = '/beacon/review';
const kPathForwardBeacon = '/forward';
const kPathForwardPerson = '/forward-person';
const kPathProfileEdit = '/profile/edit';
const kPathProfileView = '/profile/view';
const kPathInvitations = '/invitations';
const kQueryHomeTab = 'tab';
const kHomeTabInvitations = 'invitations';

const kQueryIsDeepLink = 'is_deep_link';

/// Query param for opening the beacon create screen in server-draft edit mode.
const kQueryBeaconDraftId = 'draft_id';

/// Initial tab on beacon create: `info` (default), `image`, or [kBeaconCreateTabRecipients].
const kQueryBeaconCreateTab = 'tab';

/// [kQueryBeaconCreateTab] value — open the Recipients tab.
const kBeaconCreateTabRecipients = 'recipients';

/// Preselect a recipient when opening beacon create from a profile action.
const kQueryBeaconForwardTo = 'forward_to';

/// Query param for opening the beacon edit screen for an open (published) beacon.
const kQueryBeaconEditId = 'edit_id';

/// Optional initial operational tab: `items`, `people`, `log` (+ legacy aliases).
/// Room: use `tab=room` or [kQueryBeaconSurface]=`room` (not a segment tab).
const kQueryBeaconViewTab = 'tab';

/// When truthy with [kQueryBeaconViewTab]=`help_offers`, pulse/highlight the People tab until interaction.
const kQueryBeaconPeopleTabAttention = 'people_tab_attention';

/// Full-screen room vs operational beacon view: `status` (default) | `room`.
/// Same effect as `?tab=room` on [kQueryBeaconViewTab].
const kQueryBeaconSurface = 'surface';

/// Entry provenance for beacon view resolution (`my_work`, `inbox`, …).
const kQueryBeaconEntry = 'entry';

/// [kQueryBeaconSurface] value for Room mode.
const kBeaconSurfaceRoomQueryValue = 'room';

/// [kQueryBeaconSurface] value for Status mode.
const kBeaconSurfaceStatusQueryValue = 'status';

/// Coordination item to focus when opening room from a notification deep link.
const kQueryCoordinationItemId = 'item';

/// [kQueryBeaconEntry] string values (snake_case).
const kBeaconEntryMyWork = 'my_work';
const kBeaconEntryInbox = 'inbox';
const kBeaconEntryForward = 'forward';
const kBeaconEntryRoomNotification = 'room_notification';
const kBeaconEntryDeepLink = 'deep_link';
const kBeaconEntryUnknown = 'unknown';

/// When false, blocked closure readiness hides author Close (HUD + overflow).
/// Product may enable force-close despite unresolved blockers later.
const kBeaconAllowForceCloseWhenBlocked = false;

/// First part of FQDN: `https://dev.tentura.io` (single public origin).
const kServerName = String.fromEnvironment('SERVER_NAME');

/// Share URL for invitation codes — `/invite/I…` on the public origin.
Uri inviteShareUri(String invitationId) {
  return Uri.parse(kServerName).replace(path: '/invite/$invitationId');
}

/// WebSocket server base URL; defaults to [kServerName].
/// In dev without a reverse proxy, set to the Tentura API directly
/// (e.g. `http://localhost:2080`) since Flutter's dev server cannot proxy WS.
const kWsServerName = String.fromEnvironment(
  'WS_SERVER_NAME',
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
