//
// Numbers
//

const kSeedLength = 32;

const kPublicKeyLength = 44;

const kIdLength = 13;

const kTitleMinLength = 3;

const kTitleMaxLength = 32;

/// Beacon `title` only (user/profile [kTitleMaxLength] remains shorter).
const kBeaconTitleMaxLength = 60;

const kDescriptionMaxLength = 2_048;

/// Beacon `description` — same cap as [kDescriptionMaxLength] (matches DB `beacon.description` check).
const kBeaconDescriptionMaxLength = kDescriptionMaxLength;

const int kRatingSector = 100 ~/ 4;

/// In seconds
const kJwtExpiresIn = 3_600;

const kAuthJwtExpiresIn = 30;

const kRequestTimeout = 15;

const kUserOfflineAfterSeconds = 3;

/// In hours
const int kInvitationDefaultTTL = 24 * 7;

//
// Strings
//
const kAppTitle = 'Tentura';

const kPathIcons = '/icons';
const kPathAppLinkChat = '/chat';
const kPathAppLinkView = '/shared/view';
const kPathWebSocketEndpoint = '/api/v2/ws';
const kPathGraphQLEndpoint = '/api/v1/graphql';
const kPathGraphQLEndpointV2 = '/api/v2/graphql';
/// Authenticated binary download for beacon room message file attachments (not images).
const kPathRoomAttachmentDownload = '/api/v2/room-attachments';
const kPathFirebaseSwJs = '/firebase-messaging-sw.js';

const String kUserAgent = kAppTitle;

const kContentTypeHtml = 'text/html';
const kContentTextPlain = 'text/plain';
const kContentTypeJpeg = 'image/jpeg';
const kContentApplicationJson = 'application/json';
const kContentApplicationJavaScript = 'application/javascript';
const kContentApplicationFormUrlencoded = 'application/x-www-form-urlencoded';

const kHeaderEtag = 'Etag';
const kHeaderAccept = 'Accept';
const kHeaderUserAgent = 'User-Agent';
const kHeaderContentType = 'Content-Type';
const kHeaderAuthorization = 'Authorization';
const kHeaderQueryContext = 'X-Hasura-Query-Context';

const kImageExt = 'jpg';
const kImagesPath = 'images';

/// Private attachment blobs (served only via [kPathRoomAttachmentDownload]).
const kRoomAttachmentsPath = 'room_attachments';

const kAvatarPlaceholderBlurhash =
    ':QPjJjoL?bxu~qRjD%xuM{j[%MayIUj[t7j[~qa{xuWBD%of%MWBRjj[j[ayxuj[M{ay?bj[IT'
    'WBayofayWBxuayRjofofWBWBj[Rjj[t7ayRjayRjofs:fQfQfRWBj[ofay';
