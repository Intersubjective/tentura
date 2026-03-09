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

        case 401:
          throw FcmUnauthorizedException(
            description: response.body,
          );

        case 404:
          throw FcmTokenNotFoundException(
            token: fcmToken,
            description: response.body,
          );

        default:
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
