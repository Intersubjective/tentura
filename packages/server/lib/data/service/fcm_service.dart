import 'dart:convert';
import 'package:http/http.dart';
import 'package:injectable/injectable.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

import 'package:tentura_server/env.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/entity/fcm_message_entity.dart';

@singleton
class FcmService {
  FcmService(this._env);

  final Env _env;

  late final _fcmEndpointUri = Uri.parse(
    'https://fcm.googleapis.com/v1/projects/${_env.fbProjectId}/messages:send',
  );

  late final _publicKey = RSAPrivateKey(
    _env.fbPrivateKey.replaceAll(r'\n', '\n'),
  );

  //
  //
  Future<void> sendFcmMessage({
    required String fcmToken,
    required String accessToken,
    required FcmNotificationEntity message,
    String? analyticsLabel,
    int ttlInSeconds = 0,
  }) async {
    final messageBody = jsonEncode(
      buildFcmMessagePayload(
        fcmToken: fcmToken,
        message: message,
        analyticsLabel: analyticsLabel,
        ttlInSeconds: ttlInSeconds,
      ),
    );
    try {
      final response = await post(
        _fcmEndpointUri,
        headers: {
          kHeaderContentType: kContentApplicationJson,
          kHeaderAuthorization: 'Bearer $accessToken',
        },
        body: messageBody,
      );

      switch (response.statusCode) {
        case 200:
          return;

        case 404:
          throw FcmTokenNotFoundException(
            token: fcmToken,
            description: response.body,
          );

        default:
          // FCM reports many per-message failures (THIRD_PARTY_AUTH_ERROR,
          // SENDER_ID_MISMATCH, ...) as HTTP 401/400 too, indistinguishable
          // from "our own access token is bad" by status code alone. Only
          // the latter should abort the whole send batch, so check the
          // structured FcmError body first.
          final fcmErrorCode = extractFcmErrorCode(response.body);
          if (fcmErrorCode != null) {
            throw FcmMessageRejectedException(
              token: fcmToken,
              errorCode: fcmErrorCode,
              description: response.body,
            );
          }
          if (response.statusCode == 401) {
            throw FcmUnauthorizedException(
              description: response.body,
            );
          }
          throw Exception(
            '[FcmService] Failed to send FCM message\n'
            'Response code: [${response.statusCode}, ${response.reasonPhrase}]\n'
            'Response body: ${response.body}',
          );
      }
    } catch (e) {
      print(e);
      rethrow;
    }
  }

  ///
  /// Generates an OAuth2.0 access token for FCM.
  ///
  Future<String> generateAccessToken() async {
    try {
      final response = await post(
        _oAuthTokenEndpointUri,
        headers: const {
          kHeaderContentType: kContentApplicationFormUrlencoded,
        },
        body: {
          'grant_type': _grantType,
          'assertion':
              JWT(
                _scopes,
                audience: _audience,
                issuer: _env.fbClientEmail,
              ).sign(
                _publicKey,
                algorithm: JWTAlgorithm.RS256,
                expiresIn: _env.fbAccessTokenExpiresIn,
              ),
        },
      );

      if (response.statusCode != 200) {
        throw Exception(
          '[FcmService] Failed to obtain FCM access token\n'
          'Response code: [${response.statusCode}, ${response.reasonPhrase}]\n'
          'Response body: ${response.body}',
        );
      }

      final tokenInfo = json.decode(response.body) as Map<String, dynamic>;
      print(
        '[FcmService] '
        '${_env.isDebugModeOn ? tokenInfo : 'FCM access token generated'}',
      );
      return tokenInfo['access_token']! as String;
    } catch (e) {
      print(e);
      rethrow;
    }
  }

  static const _grantType = 'urn:ietf:params:oauth:grant-type:jwt-bearer';

  static const _scopes = {
    'scope': 'https://www.googleapis.com/auth/firebase.messaging',
  };

  static final _audience = Audience([
    'https://oauth2.googleapis.com/token',
  ]);

  static final _oAuthTokenEndpointUri = Uri.parse(
    'https://oauth2.googleapis.com/token',
  );
}

/// Builds the `messages:send` request body for one FCM v1 push.
///
/// DELIBERATELY DATA-ONLY: every field (including `title`/`body`) goes under
/// `data`, and there is NO top-level `notification` block. Do not add one
/// back — see docs/qa-push-testing.md "Data-only push payloads" for the full
/// story, but in short:
///
///  1. With a `notification` field present, Chrome/Firefox display it
///     automatically via Firebase's own service-worker handling, with no
///     code of ours involved — that's a real inconsistency across browsers
///     (icon, click-through, and grouping/`tag` behavior all end up
///     depending on Firebase's per-browser default instead of something we
///     control). NOTE: an early theory here was that this automatic path
///     was *also* why an iOS Safari PWA received nothing at all, on the
///     premise that Safari cancels a subscription outright if a push
///     arrives and nothing calls `showNotification()`. That theory was
///     wrong — the actual root cause of that specific failure was
///     unrelated to our payload shape: iOS 16.x ships web push disabled by
///     default behind Settings → Safari → Advanced → Feature Flags →
///     Notifications (Apple enabled it by default starting iOS 17;
///     confirmed 2026-07-05 by toggling that flag on an iOS 16.7 device).
///     This data-only approach is kept anyway, on its own merits — explicit
///     control over notification content and click-navigation, not
///     dependent on each browser's inconsistent automatic-display default —
///     not because it was "the" iOS fix.
///  2. Given that, the generated service worker
///     (packages/server/lib/api/controllers/firebase_sw_controller.dart)
///     calls `showNotification()` itself from `onBackgroundMessage`, reading
///     title/body out of `data`. If a `notification` field is ever
///     reintroduced here, Chrome/Firefox will show it via their own
///     automatic path AND our explicit call fires too — every push becomes
///     a duplicate. See firebase/firebase-js-sdk issues #4412, #5516,
///     #6670.
///
/// `data` values must all be strings per the FCM v1 API.
Map<String, Object?> buildFcmMessagePayload({
  required String fcmToken,
  required FcmNotificationEntity message,
  String? analyticsLabel,
  int ttlInSeconds = 0,
}) => {
  'message': {
    'token': fcmToken,
    'data': {
      'title': message.title,
      'body': message.body,
      if (message.imageUrl != null) 'image': message.imageUrl!,
      if (message.actionUrl != null) 'link': message.actionUrl!,
      if (message.kind != null) 'kind': message.kind!.name,
      if (message.priority != null) 'priority': message.priority!.name,
      if (message.beaconId != null && message.beaconId!.isNotEmpty)
        'beaconId': message.beaconId!,
      if (message.coordinationItemId != null &&
          message.coordinationItemId!.isNotEmpty)
        'item': message.coordinationItemId!,
    },
    'android': {
      'ttl': '${ttlInSeconds}s',
    },
    'webpush': {
      'headers': {
        'TTL': ttlInSeconds.toString(),
      },
    },
    if (analyticsLabel != null)
      'fcm_options': {
        'analytics_label': analyticsLabel,
      },
  },
};

/// Pulls the FCM-specific `errorCode` (e.g. `THIRD_PARTY_AUTH_ERROR`,
/// `SENDER_ID_MISMATCH`, `QUOTA_EXCEEDED`) out of a `messages:send` error
/// body's `error.details[]`, where one entry's `@type` is
/// `google.firebase.fcm.v1.FcmError`. Returns null for a body with no such
/// detail (a genuine, non-FCM-specific error, e.g. a bad access token).
String? extractFcmErrorCode(String responseBody) {
  try {
    final decoded = jsonDecode(responseBody);
    if (decoded is! Map<String, dynamic>) {
      return null;
    }
    final error = decoded['error'];
    if (error is! Map<String, dynamic>) {
      return null;
    }
    final details = error['details'];
    if (details is! List) {
      return null;
    }
    for (final detail in details) {
      if (detail is Map<String, dynamic> &&
          (detail['@type'] as Object?) ==
              'type.googleapis.com/google.firebase.fcm.v1.FcmError') {
        return detail['errorCode'] as String?;
      }
    }
    return null;
  } catch (_) {
    return null;
  }
}
