import 'dart:async';
import 'package:injectable/injectable.dart';

import 'package:tentura_server/env.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/entity/fcm_message_entity.dart';

import '../service/fcm_service.dart';

@Singleton(
  env: [
    Environment.prod,
  ],
  order: 1,
)
///
/// A repository for sending Firebase Cloud Messaging (FCM) push notifications.
///
/// This repository manages the FCM access token, automatically refreshing it
/// when it expires before sending a message.
///
class FcmRemoteRepository {
  FcmRemoteRepository(
    this._env,
    this._fcmService,
  );

  final Env _env;

  final FcmService _fcmService;

  late final _timeLag = _env.fbAccessTokenExpiresIn.inSeconds ~/ 100;

  ({DateTime expiresAt, String accessToken}) _credentials = (
    expiresAt: DateTime.fromMillisecondsSinceEpoch(0),
    accessToken: '',
  );

  Completer<String>? _tokenCompleter;

  ///
  /// Sends a chat push notification via FCM to a list of devices.
  ///
  Future<List<Exception>> sendChatNotification({
    required Iterable<String> fcmTokens,
    required FcmNotificationEntity message,
  }) => _sendFcmMessage(
    message: message,
    ttlInSeconds: 60,
    fcmTokens: fcmTokens,
    analyticsLabel: 'p2p_chat',
    webConfig: message.actionUrl == null
        ? null
        : {
            'fcm_options': {
              'link': message.actionUrl!,
            },
          },
  );

  ///
  /// Sends a general push notification via FCM to a list of devices.
  /// Returns list of Exceptions if any
  ///
  Future<List<Exception>> _sendFcmMessage({
    required FcmNotificationEntity message,
    required Iterable<String> fcmTokens,
    Map<String, Map<String, String>>? webConfig,
    Map<String, Map<String, String>>? androidConfig,
    String? analyticsLabel,
    int ttlInSeconds = 0,
  }) async {
    final accessToken = await _getAccessToken();
    final results = <Exception>[];

    for (final fcmToken in fcmTokens) {
      try {
        await _fcmService.sendFcmMessage(
          ttlInSeconds: ttlInSeconds,
          analyticsLabel: analyticsLabel,
          androidConfig: androidConfig,
          accessToken: accessToken,
          webConfig: webConfig,
          fcmToken: fcmToken,
          message: message,
        );
      } on FcmUnauthorizedException catch (e) {
        print(e);
        rethrow;
      } on FcmTokenNotFoundException catch (e) {
        results.add(e);
      } catch (e) {
        print(e);
      }
    }

    return results;
  }

  //
  //
  Future<String> _getAccessToken() async {
    final now = DateTime.timestamp();

    if (_credentials.expiresAt.isAfter(now)) {
      return _credentials.accessToken;
    }

    if (_tokenCompleter != null) {
      return _tokenCompleter!.future;
    }

    _tokenCompleter = Completer<String>();
    final expiresIn = _env.fbAccessTokenExpiresIn - Duration(seconds: _timeLag);
    try {
      final accessToken = await _fcmService.generateAccessToken();
      _credentials = (
        accessToken: accessToken,
        expiresAt: now.add(expiresIn),
      );
      _tokenCompleter?.complete(accessToken);
      return accessToken;
    } catch (e) {
      _tokenCompleter?.completeError(e);
      rethrow;
    } finally {
      _tokenCompleter = null;
    }
  }
}
