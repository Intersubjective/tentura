import 'dart:async';
import 'package:logging/logging.dart';
import 'package:shelf_plus/shelf_plus.dart';

import 'package:tentura_root/domain/entity/auth_request_intent.dart';

import 'package:tentura_server/env.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/use_case/auth_case.dart';
import 'package:tentura_server/domain/use_case/user_presence_case.dart';

import 'websocket_user_session.dart';

export 'package:shelf_plus/shelf_plus.dart' show WebSocketSession;

base class WebsocketSessionHandlerBase {
  WebsocketSessionHandlerBase(
    this.env,
    this.logger,
    this.authCase,
    this.userPresenceCase,
  );

  final Env env;

  final Logger logger;

  final AuthCase authCase;

  final UserPresenceCase userPresenceCase;

  final _sessions = <WebSocketSession, WebsocketUserSession>{};

  ///
  /// Updates last seen timestamp
  ///
  JwtEntity? touchSession(WebSocketSession session) {
    final userSession = _sessions[session];
    userSession?.touch();
    return userSession?.jwt;
  }

  ///
  /// Remove session and stop its timer
  ///
  JwtEntity? removeSession(WebSocketSession session) {
    final removedSession = _sessions.remove(session);
    removedSession?.cancel();
    return removedSession?.jwt;
  }

  ///
  /// Returns JWT by session if any else throws [UnauthorizedException]
  ///
  JwtEntity getJwtBySession(WebSocketSession session) =>
      _sessions[session]?.jwt ?? (throw const UnauthorizedException());

  ///
  /// Add Timer worker for given session
  ///
  void addWorker(
    WebSocketSession session, {
    required Timer worker,
  }) => _sessions[session]?.addWorker(worker);

  ///
  /// Process type 'ping' and update presence
  ///
  Future<void> onPing(
    WebSocketSession session,
    Map<String, dynamic> message,
  ) async {
    final jwt = touchSession(session);
    if (jwt != null) {
      if (env.isPongEnabled) {
        session.send('{"type":"pong"}');
      }
      await userPresenceCase.touch(userId: jwt.sub);
    }
  }

  ///
  /// Process type 'auth' and update presence
  ///
  Future<void> onAuth(
    WebSocketSession session,
    Map<String, dynamic> message,
  ) async {
    switch (message['intent']) {
      case AuthRequestIntent.cnameSignIn:
        final jwt = authCase.parseAndVerifyJwt(
          token: message['token']! as String,
        );
        removeSession(session);
        _sessions[session] = WebsocketUserSession(jwt);
        session.send(_authLogInResponse);
        await userPresenceCase.setStatus(
          userId: jwt.sub,
          status: UserPresenceStatus.online,
        );
        logger.info(
          '[WebsocketSessionHandlerBase] Start session: [${jwt.sub}]',
        );

      case AuthRequestIntent.cnameSignOut:
        final jwt = removeSession(session);
        if (jwt != null) {
          session.send(_authLogOutResponse);
          await userPresenceCase.setStatus(
            userId: jwt.sub,
            status: UserPresenceStatus.offline,
          );
          logger.info(
            '[WebsocketSessionHandlerBase] Stop session: [${jwt.sub}]',
          );
        }

      default:
    }
  }

  static const _authLogInResponse =
      '{"type":"auth", '
      '"result":"success", '
      '"intent":"${AuthRequestIntent.cnameSignIn}"}';

  static const _authLogOutResponse =
      '{"type":"auth", '
      '"result":"success", '
      '"intent":"${AuthRequestIntent.cnameSignOut}"}';
}
