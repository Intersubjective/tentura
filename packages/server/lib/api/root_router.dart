import 'package:injectable/injectable.dart';
import 'package:shelf_plus/shelf_plus.dart';
import 'package:shelf_cors_headers/shelf_cors_headers.dart';

import 'package:tentura_server/env.dart';

import 'controllers/account_credentials_controller.dart';
import 'controllers/auth_email_controller.dart';
import 'controllers/auth_google_controller.dart';
import 'controllers/firebase_sw_controller.dart';
import 'controllers/websocket_controller.dart';
import 'controllers/graphiql_controller.dart';
import 'controllers/graphql_controller.dart';
import 'controllers/invite_accept_existing_controller.dart';
import 'controllers/invite_preview_controller.dart';
import 'controllers/room_attachment_download_controller.dart';
import 'controllers/session_controller.dart';
import 'controllers/shared_view_controller.dart';
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
    this._sharedViewController,
    this._roomAttachmentDownloadController,
    this._invitePreviewController,
    this._inviteAcceptExistingController,
    this._accountCredentialsController,
    this._sessionController,
    this._authGoogleController,
    this._authEmailController,
  );

  final Env _env;

  final AuthMiddleware _authMiddleware;

  final WebSocketController _wsController;

  final GraphqlController _graphqlController;

  final GraphiqlController _graphiqlController;

  final FirebaseSwController _firebaseSwController;

  final SharedViewController _sharedViewController;

  final RoomAttachmentDownloadController _roomAttachmentDownloadController;

  final InvitePreviewController _invitePreviewController;

  final InviteAcceptExistingController _inviteAcceptExistingController;

  final AccountCredentialsController _accountCredentialsController;

  final SessionController _sessionController;

  final AuthGoogleController _authGoogleController;

  final AuthEmailController _authEmailController;

  Handler routeHandler() {
    final router = Router().plus
      ..use(logRequests())
      ..use(
        corsHeaders(
          headers: {
            ACCESS_CONTROL_ALLOW_CREDENTIALS: 'false',
            ACCESS_CONTROL_ALLOW_ORIGIN: _env.serverUri.host,
          },
        ),
      )
      ..get('/health', () => 'I`m fine!')
      ..get('/graphiql', _graphiqlController.handler)
      ..get(kPathAppLinkView, _sharedViewController.handler)
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
        '/api/v2/auth/email/link/start',
        _authEmailController.linkStart,
        use: _authMiddleware.verifyBearerJwt,
      )
      ..get(
        '/auth/email/verify',
        _authEmailController.verify,
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
      );

    return router.call;
  }
}
