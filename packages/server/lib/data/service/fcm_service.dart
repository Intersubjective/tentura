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
    Map<String, Map<String, String>>? webConfig,
    Map<String, Map<String, String>>? androidConfig,
    String? analyticsLabel,
    int ttlInSeconds = 0,
  }) async {
    final messageBody = jsonEncode({
      'message': {
        'token': fcmToken,
        'notification': {
          'title': message.title,
          'body': message.body,
          if (message.imageUrl != null) 'image': message.imageUrl,
        },
        if (message.actionUrl != null)
          'data': {
            'link': message.actionUrl!,
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
          ...?androidConfig,
        },
        'webpush': {
          'headers': {
            'TTL': ttlInSeconds.toString(),
          },
          ...?webConfig,
        },
        if (analyticsLabel != null)
          'fcm_options': {
            'analytics_label': analyticsLabel,
          },
      },
    });
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
