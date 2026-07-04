import 'dart:convert';

import 'package:injectable/injectable.dart';

import 'package:tentura_server/consts.dart';
import 'package:tentura_server/domain/entity/fcm_message_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/fcm_remote_repository_port.dart';
import 'package:tentura_server/domain/port/fcm_token_repository_port.dart';

import '../http/cookies.dart';
import '_base_controller.dart';

/// Development/staging-only endpoint to send a one-shot FCM push for QA.
@Injectable(order: 3)
final class QaSendFcmController extends BaseController {
  const QaSendFcmController(
    super.env,
    this._fcmRemote,
    this._fcmTokens,
  );

  final FcmRemoteRepositoryPort _fcmRemote;

  final FcmTokenRepositoryPort _fcmTokens;

  Future<Response> sendFcm(Request request) async {
    if (!_qaAllowed(request)) {
      return Response.notFound(null);
    }

    Map<String, dynamic> body;
    try {
      body = (await request.body.asJson as Map).cast<String, dynamic>();
    } catch (_) {
      return Response.badRequest(body: 'invalid JSON body');
    }

    final title = _nonEmptyString(body['title']);
    final messageBody = _nonEmptyString(body['body']);
    if (title == null || messageBody == null) {
      return Response.badRequest(body: 'title and body are required');
    }

    final explicitToken = _nonEmptyString(body['token']);
    final userId = _nonEmptyString(body['userId']);

    late final Set<String> fcmTokens;
    if (explicitToken != null) {
      fcmTokens = {explicitToken};
    } else if (userId != null) {
      final rows = await _fcmTokens.getTokensByUserId(userId);
      if (rows.isEmpty) {
        return Response.ok(
          jsonEncode({
            'ok': false,
            'reason': 'no_fcm_token_rows',
            'userId': userId,
          }),
          headers: _jsonNoStore,
        );
      }
      fcmTokens = rows.map((e) => e.token).toSet();
    } else {
      return Response.badRequest(body: 'userId or token is required');
    }

    final message = FcmNotificationEntity(
      title: title,
      body: messageBody,
      actionUrl: _optionalString(body['actionUrl']),
      beaconId: _optionalString(body['beaconId']),
    );

    final results = await _fcmRemote.sendChatNotification(
      fcmTokens: fcmTokens,
      message: message,
    );

    final staleTokens = results.whereType<FcmTokenNotFoundException>().length;
    final sent = fcmTokens.length - results.length;
    final errors = [
      for (final e in results)
        if (e is FcmTokenNotFoundException)
          {
            'type': 'token_not_found',
            'tokenSuffix': _tokenSuffix(e.token),
          }
        else if (e is FcmMessageRejectedException)
          {
            'type': 'message_rejected',
            'errorCode': e.errorCode,
            'tokenSuffix': _tokenSuffix(e.token),
          }
        else
          {
            'type': e.runtimeType.toString(),
            'message': e.toString(),
          },
    ];

    return Response.ok(
      jsonEncode({
        'ok': true,
        'devices': fcmTokens.length,
        'sent': sent,
        'staleTokens': staleTokens,
        'mock': !env.isFcmConfigured,
        'errors': errors,
      }),
      headers: _jsonNoStore,
    );
  }

  bool _qaAllowed(Request request) {
    if (!env.isQaAuthEnabled) {
      return false;
    }

    final queryToken = request.url.queryParameters['_qa_token'];
    final authorization = request.headers['authorization'] ?? '';
    final bearerToken = authorization.toLowerCase().startsWith('bearer ')
        ? authorization.substring(7).trim()
        : null;
    return queryToken == env.qaAuthToken || bearerToken == env.qaAuthToken;
  }

  String? _nonEmptyString(Object? value) {
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String? _optionalString(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String _tokenSuffix(String token) {
    if (token.length <= 8) {
      return token;
    }
    return token.substring(token.length - 8);
  }

  Map<String, String> get _jsonNoStore => {
    kHeaderContentType: kContentApplicationJson,
    kHeaderCacheControl: kCacheControlNoStore,
  };

  @override
  Future<Response> handler(Request request) => sendFcm(request);
}
