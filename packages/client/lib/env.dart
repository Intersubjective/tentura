import 'package:injectable/injectable.dart';

import 'consts.dart';

export 'consts.dart';

@singleton
class Env {
  const Env({
    // Common
    String? logLevel,
    String? serverUrlBase,
    String? complaintEmail,
    String? pathAppLinkView,
    String? osmUrlTemplate,
    String? inviteEmail,

    // Websocket
    Duration? wsPingInterval,

    // Firebase
    String? firebaseApiKey,
    String? firebaseVapidKey,
    String? firebaseAuthDomain,
    String? firebaseProjectId,
    String? firebaseStorageBucket,
    String? firebaseMessagingSenderId,
    String? firebaseAppId,

    // Feature flags
    bool? needInviteCode,

    // Google OAuth (native linking)
    String? googleServerClientId,
    String? googleIosClientId,
  }) : // Common
       logLevel = logLevel ?? const String.fromEnvironment('LOG_LEVEL'),
       serverUrlBase =
           serverUrlBase ?? const String.fromEnvironment('SERVER_NAME'),
       pathAppLinkView = pathAppLinkView ?? kPathAppLinkView,
       complaintEmail =
           complaintEmail ?? const String.fromEnvironment('COMPLAINT_EMAIL'),
       inviteEmail =
           inviteEmail ?? const String.fromEnvironment('INVITE_EMAIL'),
       osmUrlTemplate =
           osmUrlTemplate ??
           const String.fromEnvironment(
             'OSM_LINK_BASE',
             defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
           ),

       // Websocket
       wsPingInterval =
           wsPingInterval ??
           const Duration(
             seconds: int.fromEnvironment(
               'WS_PING_INTERVAL',
               defaultValue: 10,
             ),
           ),

       // Firebase
       firebaseAppId =
           firebaseAppId ?? const String.fromEnvironment('FB_APP_ID'),
       firebaseApiKey =
           firebaseApiKey ?? const String.fromEnvironment('FB_API_KEY'),
       firebaseProjectId =
           firebaseProjectId ?? const String.fromEnvironment('FB_PROJECT_ID'),
       firebaseAuthDomain =
           firebaseAuthDomain ?? const String.fromEnvironment('FB_AUTH_DOMAIN'),
       firebaseStorageBucket =
           firebaseStorageBucket ??
           const String.fromEnvironment('FB_STORAGE_BUCKET'),
       firebaseMessagingSenderId =
           firebaseMessagingSenderId ??
           const String.fromEnvironment('FB_SENDER_ID'),
       firebaseVapidKey =
           firebaseVapidKey ?? const String.fromEnvironment('FB_VAPID_KEY'),

       // Feature flags
       clearDatabase = const bool.fromEnvironment('CLEAR_DATABASE'),
       needInviteCode =
           needInviteCode ?? const bool.fromEnvironment('NEED_INVITE_CODE'),

       // Google OAuth (native linking; web uses server redirect)
       googleServerClientId = googleServerClientId ??
           const String.fromEnvironment('GOOGLE_CLIENT_ID'),
       googleIosClientId = googleIosClientId ??
           const String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');

  @factoryMethod
  const factory Env.fromEnvironment() = Env;

  // Common
  /// OFF | SHOUT | SEVERE | WARNING | INFO | CONFIG | FINE | FINER | FINEST
  final String logLevel;
  final String serverUrlBase;
  final String complaintEmail;
  final String pathAppLinkView;
  final String osmUrlTemplate;
  final String inviteEmail;

  // Websocket
  final Duration wsPingInterval;

  // Firebase
  final String firebaseAppId;
  final String firebaseApiKey;
  final String firebaseVapidKey;
  final String firebaseProjectId;
  final String firebaseAuthDomain;
  final String firebaseStorageBucket;
  final String firebaseMessagingSenderId;

  // Feature flags
  final bool clearDatabase;
  final bool needInviteCode;

  /// Web/server OAuth client id (= Android `serverClientId` for idToken `aud`).
  final String googleServerClientId;

  /// iOS OAuth client id for `google_sign_in` (optional on Android/web).
  final String googleIosClientId;

  bool get isGoogleNativeLinkConfigured => googleServerClientId.isNotEmpty;
}
