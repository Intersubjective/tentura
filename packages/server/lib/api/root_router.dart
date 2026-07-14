import 'package:injectable/injectable.dart';
import 'package:shelf_plus/shelf_plus.dart';
import 'package:shelf_cors_headers/shelf_cors_headers.dart';

import 'package:tentura_server/env.dart';
import 'package:tentura_server/app/sentry/sentry_request_tracing.dart';

import 'controllers/account_credentials_controller.dart';
import 'controllers/account_profile_controller.dart';
import 'controllers/auth_email_controller.dart';
import 'controllers/unsubscribe_controller.dart';
import 'controllers/auth_google_controller.dart';
import 'controllers/firebase_sw_controller.dart';
import 'controllers/websocket_controller.dart';
import 'controllers/graphiql_controller.dart';
import 'controllers/graphql_controller.dart';
import 'controllers/invite_accept_existing_controller.dart';
import 'controllers/invite_preview_controller.dart';
import 'controllers/qa_email_sink_controller.dart';
import 'controllers/qa_integration_controller.dart';
import 'controllers/qa_send_fcm_controller.dart';
import 'controllers/room_attachment_download_controller.dart';
import 'controllers/realtime_watch_grant_controller.dart';
import 'controllers/session_controller.dart';
import 'controllers/app_link_redirect_controller.dart';
import 'http/request_log_sanitizer.dart';
import 'middleware/auth_middleware.dart';

@Injectable(order: 4)
class RootRouter {
  RootRouter(
    this._env,
    this._authMiddleware,
    this._wsController,
    this._graphqlController,
    this._graphiqlController,
    this._firebaseSwController,
    this._appLinkRedirectController,
    this._roomAttachmentDownloadController,
    this._invitePreviewController,
    this._inviteAcceptExistingController,
    this._accountCredentialsController,
    this._accountProfileController,
    this._sessionController,
    this._authGoogleController,
    this._authEmailController,
    this._qaEmailSinkController,
    this._qaIntegrationController,
    this._qaSendFcmController,
    this._unsubscribeController,
    this._realtimeWatchGrantController,
  );

  final Env _env;

  final AuthMiddleware _authMiddleware;

  final WebSocketController _wsController;

  final GraphqlController _graphqlController;

  final GraphiqlController _graphiqlController;

  final FirebaseSwController _firebaseSwController;

  final AppLinkRedirectController _appLinkRedirectController;

  final RoomAttachmentDownloadController _roomAttachmentDownloadController;

  final InvitePreviewController _invitePreviewController;

  final InviteAcceptExistingController _inviteAcceptExistingController;

  final AccountCredentialsController _accountCredentialsController;

  final AccountProfileController _accountProfileController;

  final SessionController _sessionController;

  final AuthGoogleController _authGoogleController;

  final AuthEmailController _authEmailController;

  final QaEmailSinkController _qaEmailSinkController;

  final QaIntegrationController _qaIntegrationController;

  final QaSendFcmController _qaSendFcmController;

  final UnsubscribeController _unsubscribeController;

  final RealtimeWatchGrantController _realtimeWatchGrantController;

  Handler routeHandler() {
    final router = Router().plus
      ..use(
        logRequests(
          logger: (message, isError) =>
              sanitizedRequestLogger(message, isError: isError),
        ),
      )
      ..use(
        corsHeaders(
          headers: {
            ACCESS_CONTROL_ALLOW_CREDENTIALS: 'false',
            // Browsers match Origin against scheme://host[:port], not a bare host.
            ACCESS_CONTROL_ALLOW_ORIGIN: _env.serverUri.origin,
            ACCESS_CONTROL_ALLOW_HEADERS:
                'sentry-trace, baggage, content-type, authorization, '
                '$kHeaderQueryContext, accept, user-agent',
          },
        ),
      )
      ..use(sentryRequestTracing(env: _env))
      ..get('/health', () => 'I`m fine!')
      ..get('/graphiql', _graphiqlController.handler)
      ..get(kPathAppLinkView, _appLinkRedirectController.handler)
      ..get(kPathFirebaseSwJs, _firebaseSwController.handler)
      ..get(kPathWebSocketEndpoint, _wsController.handler)
      ..post(
        kPathGraphQLEndpointV2,
        _graphqlController.handler,
        use: _authMiddleware.extractJwtClaims,
      )
      ..get(
        '$kPathRoomAttachmentDownload/<attachmentId>',
        _roomAttachmentDownloadController.handler,
        use: _authMiddleware.verifyBearerJwt,
      )
      ..get(
        '/api/v2/invite/<code>/preview',
        _invitePreviewController.handler,
        use: _authMiddleware.extractJwtOrSessionClaims,
      )
      ..post(
        '/api/v2/session/access-token',
        _sessionController.accessToken,
      )
      ..post(
        '/api/v2/session/logout',
        _sessionController.logout,
      )
      ..post(
        '/api/v2/session/from-bearer',
        _sessionController.fromBearer,
        use: _authMiddleware.verifyBearerJwt,
      )
      ..post(
        '/api/v2/realtime/watch-grant',
        _realtimeWatchGrantController.handler,
        use: _authMiddleware.verifyBearerJwt,
      )
      ..get(
        '/api/auth/google/start',
        _authGoogleController.start,
      )
      ..post(
        '/api/auth/google/link/intent',
        _authGoogleController.linkIntent,
        use: _authMiddleware.verifyBearerJwt,
      )
      ..get(
        '/api/auth/google/link/start',
        _authGoogleController.linkStart,
      )
      ..get(
        '/api/auth/google/callback',
        _authGoogleController.callback,
      )
      ..post(
        '/api/v2/auth/email/start',
        _authEmailController.start,
      )
      ..post(
        '/api/v2/auth/email/test-login',
        _authEmailController.testLogin,
      )
      ..post(
        '/api/v2/auth/email/link/start',
        _authEmailController.linkStart,
        use: _authMiddleware.verifyBearerJwt,
      )
      ..get(
        '/auth/email/verify',
        _authEmailController.verifyGet,
      )
      ..post(
        '/auth/email/verify',
        _authEmailController.verifyPost,
      )
      ..get(
        '/_qa/latest-email',
        _qaEmailSinkController.latestEmail,
      )
      ..post('/_qa/integration/bootstrap', _qaIntegrationController.bootstrap)
      ..post(
        '/_qa/send-fcm',
        _qaSendFcmController.sendFcm,
      )
      ..get(
        '/email/unsubscribe',
        _unsubscribeController.getPage,
      )
      ..post(
        '/email/unsubscribe',
        _unsubscribeController.post,
      )
      ..post(
        '/api/v2/invite/<code>/accept-as-existing',
        _inviteAcceptExistingController.handler,
        use: _authMiddleware.verifyBearerJwt,
      )
      ..get(
        '/api/v2/accounts/me/credentials',
        _accountCredentialsController.list,
        use: _authMiddleware.verifyBearerJwt,
      )
      ..post(
        '/api/v2/accounts/me/credentials',
        _accountCredentialsController.link,
        use: _authMiddleware.verifyBearerJwt,
      )
      ..post(
        '/api/v2/accounts/me/credentials/google',
        _accountCredentialsController.linkGoogle,
        use: _authMiddleware.verifyBearerJwt,
      )
      ..delete(
        '/api/v2/accounts/me/credentials/<credentialId>',
        _accountCredentialsController.remove,
        use: _authMiddleware.verifyBearerJwt,
      )
      // Cookie or Bearer: the static landing post-signup name step uses the
      // session cookie directly (no JWT in landing JS).
      ..get(
        '/api/v2/accounts/me/profile',
        _accountProfileController.get,
        use: _authMiddleware.extractJwtOrSessionClaims,
      )
      ..patch(
        '/api/v2/accounts/me/profile',
        _accountProfileController.patch,
        use: _authMiddleware.extractJwtOrSessionClaims,
      );

    // Unlike the legacy QA helpers, the realtime suspension route is not
    // registered at all in non-QA environments.
    if (_env.isQaAuthEnabled) {
      router.post(
        '/_qa/integration/realtime-socket',
        _qaIntegrationController.realtimeSocket,
      );
    }

    return router.call;
  }
}
