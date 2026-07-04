import 'dart:async';
import 'package:logging/logging.dart';

import 'package:tentura_server/env.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/entity/fcm_message_entity.dart';
import 'package:tentura_server/domain/port/fcm_remote_repository_port.dart';
import 'package:tentura_server/domain/port/fcm_token_repository_port.dart';

import '../service/fcm_service.dart';

///
/// A repository for sending Firebase Cloud Messaging (FCM) push notifications.
///
/// This repository manages the FCM access token, automatically refreshing it
/// when it expires before sending a message.
///
class FcmRemoteRepository implements FcmRemoteRepositoryPort {
  FcmRemoteRepository(
    this._env,
    this._fcmService,
    this._fcmTokenRepository,
    this._logger,
  );

  final Env _env;

  final FcmService _fcmService;

  final FcmTokenRepositoryPort _fcmTokenRepository;

  final Logger _logger;

  late final _timeLag = _env.fbAccessTokenExpiresIn.inSeconds ~/ 100;

  ({DateTime expiresAt, String accessToken}) _credentials = (
    expiresAt: DateTime.fromMillisecondsSinceEpoch(0),
    accessToken: '',
  );

  Completer<String>? _tokenCompleter;

  ///
  /// Sends a chat push notification via FCM to a list of devices.
  ///
  /// The wire payload is data-only (see [buildFcmMessagePayload] in
  /// fcm_service.dart for why — consistent explicit display across
  /// browsers, not a Safari-specific fix as originally theorized). Display
  /// is the generated service worker's job (firebase_sw_controller.dart),
  /// not FCM's automatic path.
  ///
  @override
  Future<List<Exception>> sendChatNotification({
    required Iterable<String> fcmTokens,
    required FcmNotificationEntity message,
  }) => _sendFcmMessage(
    message: message,
    // Generous on purpose: Apple's web push relay is an extra hop beyond
    // the platform-native paths (Chrome/Firefox talk to Google/Mozilla's
    // own infra more directly), so it can in principle add latency those
    // never see. A short TTL risks a message expiring before Apple ever
    // delivers it, with nothing in our logs to show for it — FCM still
    // returns 200 either way. Kept even though it turned out not to be the
    // fix for the one real case investigated (that was an iOS 16.x platform
    // setting — see buildFcmMessagePayload's docstring): delivered-late is
    // recoverable, expired-silently isn't, and there's no real downside to
    // a longer TTL for a chat-style notification.
    ttlInSeconds: 3600,
    fcmTokens: fcmTokens,
    analyticsLabel: 'notification',
  );

  ///
  /// Sends a general push notification via FCM to a list of devices.
  /// Returns list of Exceptions if any
  ///
  Future<List<Exception>> _sendFcmMessage({
    required FcmNotificationEntity message,
    required Iterable<String> fcmTokens,
    String? analyticsLabel,
    int ttlInSeconds = 0,
  }) async {
    final accessToken = await _getAccessToken();
    final results = <Exception>[];

    final tokenList = fcmTokens.toList();
    _logger.info(
      '[FCM] sendChatNotification devices=${tokenList.length} '
      'title="${message.title}"',
    );
    for (final fcmToken in tokenList) {
      try {
        await _fcmService.sendFcmMessage(
          ttlInSeconds: ttlInSeconds,
          analyticsLabel: analyticsLabel,
          accessToken: accessToken,
          fcmToken: fcmToken,
          message: message,
        );
        _logger.info(
          '[FCM] FCM HTTP 200 token=…${fcmToken.length > 8 ? fcmToken.substring(fcmToken.length - 8) : fcmToken}',
        );
      } on FcmUnauthorizedException catch (e) {
        _logger.severe('[FCM] unauthorized — aborting send batch: $e');
        rethrow;
      } on FcmTokenNotFoundException catch (e) {
        await _fcmTokenRepository.deleteToken(e.token);
        final suffix = e.token.length > 8
            ? e.token.substring(e.token.length - 8)
            : e.token;
        _logger.info(
          '[FCM] pruned stale token len=${e.token.length} suffix=$suffix',
        );
        results.add(e);
      } on FcmMessageRejectedException catch (e) {
        final suffix = e.token.length > 8
            ? e.token.substring(e.token.length - 8)
            : e.token;
        _logger.warning(
          '[FCM] send rejected suffix=$suffix errorCode=${e.errorCode}',
        );
        results.add(e);
      } catch (e) {
        final suffix = fcmToken.length > 8
            ? fcmToken.substring(fcmToken.length - 8)
            : fcmToken;
        _logger.warning('[FCM] send failed suffix=$suffix: $e');
        results.add(e is Exception ? e : Exception('$e'));
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
