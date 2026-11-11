import 'package:injectable/injectable.dart' show Environment;
import 'package:shelf_plus/shelf_plus.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/account_credentials_controller.dart';
import 'package:tentura_server/api/controllers/account_profile_controller.dart';
import 'package:tentura_server/api/controllers/auth_email_controller.dart';
import 'package:tentura_server/api/controllers/unsubscribe_controller.dart';
import 'package:tentura_server/api/controllers/auth_google_controller.dart';
import 'package:tentura_server/api/controllers/firebase_sw_controller.dart';
import 'package:tentura_server/api/controllers/websocket_controller.dart';
import 'package:tentura_server/api/controllers/graphiql_controller.dart';
import 'package:tentura_server/api/controllers/health_controller.dart';
import 'package:tentura_server/api/controllers/graphql_controller.dart';
import 'package:tentura_server/api/controllers/invite_accept_existing_controller.dart';
import 'package:tentura_server/api/controllers/invite_preview_controller.dart';
import 'package:tentura_server/api/controllers/room_attachment_download_controller.dart';
import 'package:tentura_server/api/controllers/session_controller.dart';
import 'package:tentura_server/api/controllers/push_action_controller.dart';
import 'package:tentura_server/api/controllers/qa_email_sink_controller.dart';
import 'package:tentura_server/api/controllers/qa_integration_controller.dart';
import 'package:tentura_server/api/controllers/qa_send_fcm_controller.dart';
import 'package:tentura_server/api/controllers/websocket/session/qa_realtime_socket_gate.dart';
import 'package:tentura_server/api/middleware/auth_middleware.dart';
import 'package:tentura_server/api/root_router.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/domain/port/fcm_remote_repository_port.dart';
import 'package:tentura_server/domain/port/fcm_token_repository_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/port/invitation_repository_port.dart';
import 'package:tentura_server/domain/port/vote_user_friendship_lookup_port.dart';
import 'package:tentura_server/domain/port/email_auth_transaction_repository_port.dart';
import 'package:tentura_server/domain/port/email_sender_port.dart';
import 'package:tentura_server/domain/port/user_trust_edge_repository_port.dart';
import 'package:tentura_server/domain/port/trust_maintenance_port.dart';
import 'package:tentura_server/domain/port/meritrank_repository_port.dart';
import 'package:tentura_server/domain/port/witness_window_port.dart';
import 'package:tentura_server/domain/port/closure_repository_port.dart';
import 'package:tentura_server/domain/port/mutating_unit_of_work_port.dart';
import 'package:tentura_server/domain/port/closure_finalizer_port.dart';
import 'package:tentura_server/domain/port/session_repository_port.dart';
import 'package:tentura_server/domain/port/verified_contact_repository_port.dart';
import 'package:tentura_server/env.dart';

import '../support/session_database_di_harness.dart';

final _collaboratorCalls = <String>[];

mixin _RejectCollaboratorCalls {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    final call = '$runtimeType.${invocation.memberName}';
    _collaboratorCalls.add(call);
    throw StateError('Denied or invalid QA request touched $call');
  }
}

final class _UnusedFcmRemoteRepositoryPort
    with _RejectCollaboratorCalls
    implements FcmRemoteRepositoryPort {}

final class _UnusedFcmTokenRepositoryPort
    with _RejectCollaboratorCalls
    implements FcmTokenRepositoryPort {}

final class _UnusedUserRepositoryPort
    with _RejectCollaboratorCalls
    implements UserRepositoryPort {}

final class _UnusedInvitationRepositoryPort
    with _RejectCollaboratorCalls
    implements InvitationRepositoryPort {}

final class _UnusedVoteUserFriendshipLookupPort
    with _RejectCollaboratorCalls
    implements VoteUserFriendshipLookupPort {}

final class _UnusedEmailAuthTransactionRepositoryPort
    with _RejectCollaboratorCalls
    implements EmailAuthTransactionRepositoryPort {}

final class _UnusedEmailSenderPort
    with _RejectCollaboratorCalls
    implements EmailSenderPort {}

final class _UnusedUserTrustEdgeRepositoryPort
    with _RejectCollaboratorCalls
    implements UserTrustEdgeRepositoryPort {}

final class _UnusedTrustMaintenancePort
    with _RejectCollaboratorCalls
    implements TrustMaintenancePort {}

final class _UnusedMeritrankRepositoryPort
    with _RejectCollaboratorCalls
    implements MeritrankRepositoryPort {}

final class _UnusedWitnessWindowPort
    with _RejectCollaboratorCalls
    implements WitnessWindowPort {}

final class _UnusedClosureRepositoryPort
    with _RejectCollaboratorCalls
    implements ClosureRepositoryPort {}

final class _UnusedMutatingUnitOfWorkPort
    with _RejectCollaboratorCalls
    implements MutatingUnitOfWorkPort {}

final class _UnusedClosureFinalizerPort
    with _RejectCollaboratorCalls
    implements ClosureFinalizerPort {}

final class _UnusedSessionRepositoryPort
    with _RejectCollaboratorCalls
    implements SessionRepositoryPort {}

final class _UnusedVerifiedContactRepositoryPort
    with _RejectCollaboratorCalls
    implements VerifiedContactRepositoryPort {}

const _token = 'qa-router-secret';
const _qaUser = 'Uqa-router-user';
const _validBody =
    '{"runId":"router-guard","userId":"$_qaUser",'
    '"action":"suspend","beaconId":"Bqa-router-request",'
    '"token":"qa-device-token","title":"QA","body":"Guard probe"}';
const _routes = <({String method, String path})>[
  (method: 'GET', path: '/_qa/latest-email'),
  (method: 'POST', path: '/_qa/integration/bootstrap'),
  (method: 'POST', path: '/_qa/integration/witness-fixture'),
  (method: 'POST', path: '/_qa/send-fcm'),
  (method: 'POST', path: '/_qa/integration/realtime-socket'),
  (method: 'POST', path: '/_qa/integration/closure-fixture'),
  (method: 'POST', path: '/_qa/integration/expire-closure'),
];

Env _env({required bool enabled}) => Env(
  environment: Environment.dev,
  publicKey: Env.kJwtPublicKey,
  privateKey: Env.kJwtPrivateKey,
  serverUri: Uri.parse('https://test.tentura.local'),
  qaAuthEnabled: enabled,
  qaAuthToken: _token,
  qaEmailDomains: const ['test.tentura.local'],
);

Request _request(
  ({String method, String path}) route, {
  String? authorization = 'Bearer $_token',
  String? queryToken,
  String? email,
  String rawBody = 'not JSON',
}) => Request(
  route.method,
  Uri.parse('https://test.tentura.local${route.path}').replace(
    queryParameters: {
      '_qa_token': ?queryToken,
      'email': ?email,
    },
  ),
  headers: {
    'content-type': 'application/json',
    'authorization': ?authorization,
  },
  body: route.method == 'POST' ? rawBody : null,
);

// Use real controllers and middleware. The optional router environment lets
// the registration boundary be tested independently of the handler guard:
// enabled controllers would answer 400 if a disabled router dispatched to them.
Future<T> _resolve<T extends Object>() async =>
    getIt.findFirstObjectRegistration<T>()!.isAsync
    ? await getIt.getAsync<T>()
    : getIt<T>();

Future<Handler> _router(Env env) async => RootRouter(
  env,
  await _resolve<AuthMiddleware>(),
  await _resolve<WebSocketController>(),
  await _resolve<GraphqlController>(),
  await _resolve<GraphiqlController>(),
  await _resolve<HealthController>(),
  await _resolve<FirebaseSwController>(),
  await _resolve<RoomAttachmentDownloadController>(),
  await _resolve<InvitePreviewController>(),
  await _resolve<InviteAcceptExistingController>(),
  await _resolve<AccountCredentialsController>(),
  await _resolve<AccountProfileController>(),
  await _resolve<SessionController>(),
  await _resolve<AuthGoogleController>(),
  await _resolve<AuthEmailController>(),
  await _resolve<QaEmailSinkController>(),
  await _resolve<QaIntegrationController>(),
  await _resolve<QaSendFcmController>(),
  await _resolve<UnsubscribeController>(),
  await _resolve<PushActionController>(),
).routeHandler();

Future<Response> _direct(
  ({String method, String path}) route,
  Request request,
) async => switch (route.path) {
  '/_qa/latest-email' => (await _resolve<QaEmailSinkController>()).latestEmail(
    request,
  ),
  '/_qa/send-fcm' => (await _resolve<QaSendFcmController>()).sendFcm(request),
  '/_qa/integration/bootstrap' =>
    (await _resolve<QaIntegrationController>()).bootstrap(
      request,
    ),
  '/_qa/integration/witness-fixture' =>
    (await _resolve<QaIntegrationController>()).witnessFixture(request),
  '/_qa/integration/realtime-socket' =>
    (await _resolve<QaIntegrationController>()).realtimeSocket(request),
  '/_qa/integration/closure-fixture' =>
    (await _resolve<QaIntegrationController>()).closureFixture(request),
  '/_qa/integration/expire-closure' =>
    (await _resolve<QaIntegrationController>()).expireClosure(request),
  _ => throw ArgumentError.value(route.path),
};

void main() {
  for (final enabled in [false, true]) {
    group('QA HTTP routes with controller QA auth ${enabled ? 'enabled' : 'disabled'}', () {
      late Handler handler;
      late Handler disabledRouter;
      late QaRealtimeSocketGate realtimeGate;

      setUpAll(() async {
        await getIt.reset();
        final env = _env(enabled: enabled);
        // Keep real routing, controllers and use cases; replace external
        // collaborators with fail-on-call ports and background I/O stubs.
        getIt
          ..skipDoubleRegistration = true
          ..registerSingleton<FcmRemoteRepositoryPort>(
            _UnusedFcmRemoteRepositoryPort(),
          )
          ..registerSingleton<FcmTokenRepositoryPort>(
            _UnusedFcmTokenRepositoryPort(),
          )
          ..registerSingleton<UserRepositoryPort>(
            _UnusedUserRepositoryPort(),
          )
          ..registerSingleton<InvitationRepositoryPort>(
            _UnusedInvitationRepositoryPort(),
          )
          ..registerSingleton<VoteUserFriendshipLookupPort>(
            _UnusedVoteUserFriendshipLookupPort(),
          )
          ..registerSingleton<EmailAuthTransactionRepositoryPort>(
            _UnusedEmailAuthTransactionRepositoryPort(),
          )
          ..registerSingleton<EmailSenderPort>(_UnusedEmailSenderPort())
          ..registerSingleton<UserTrustEdgeRepositoryPort>(
            _UnusedUserTrustEdgeRepositoryPort(),
          )
          ..registerSingleton<TrustMaintenancePort>(
            _UnusedTrustMaintenancePort(),
          )
          ..registerSingleton<MeritrankRepositoryPort>(
            _UnusedMeritrankRepositoryPort(),
          )
          ..registerSingleton<WitnessWindowPort>(_UnusedWitnessWindowPort())
          ..registerSingleton<ClosureRepositoryPort>(
            _UnusedClosureRepositoryPort(),
          )
          ..registerSingleton<MutatingUnitOfWorkPort>(
            _UnusedMutatingUnitOfWorkPort(),
          )
          ..registerSingleton<ClosureFinalizerPort>(
            _UnusedClosureFinalizerPort(),
          )
          ..registerSingleton<SessionRepositoryPort>(
            _UnusedSessionRepositoryPort(),
          )
          ..registerSingleton<VerifiedContactRepositoryPort>(
            _UnusedVerifiedContactRepositoryPort(),
          );
        await configureSessionDatabaseTestGraph(env);
        handler = (await getIt.getAsync<RootRouter>()).routeHandler();
        disabledRouter = enabled
            ? await _router(_env(enabled: false))
            : handler;
      });

      setUp(() {
        _collaboratorCalls.clear();
        realtimeGate = getIt<QaRealtimeSocketGate>()
          ..registerBootstrappedUser(_qaUser)
          ..registerSession(
            userId: _qaUser,
            session: _qaUser,
            close: () async {
              _collaboratorCalls.add('QA socket closed');
            },
          );
      });
      tearDown(() {
        expect(realtimeGate.isAuthenticationSuspended(_qaUser), isFalse);
        realtimeGate.unregisterSession(_qaUser);
        expect(
          _collaboratorCalls,
          isEmpty,
          reason: 'Gates must reject requests before accessing collaborators',
        );
      });

      tearDownAll(() async {
        await getIt.reset();
        getIt.skipDoubleRegistration = false;
      });

      for (final route in _routes) {
        if (!enabled) {
          test(
            '${route.method} ${route.path} uses the unmatched-route response',
            () async {
              final missing = await handler(
                Request(
                  route.method,
                  Uri.parse('https://test.tentura.local/_qa/absent-route'),
                ),
              );
              final missingBody = await missing.readAsString();
              expect(missing.statusCode, 404);
              final response = await handler(
                _request(
                  route,
                  queryToken: _token,
                  email: 'router@test.tentura.local',
                ),
              );
              expect(response.statusCode, 404);
              expect(await response.readAsString(), missingBody);
            },
          );

          test(
            '${route.method} ${route.path} preserves its direct handler rejection when disabled',
            () async {
              final response = await _direct(
                route,
                _request(
                  route,
                  rawBody: _validBody,
                  email: 'router@test.tentura.local',
                ),
              );
              expect(response.statusCode, 404);
              expect(
                await response.readAsString(),
                await Response.notFound(null).readAsString(),
              );
            },
          );
        } else {
          test(
            '${route.method} ${route.path} reaches validation with a Bearer token',
            () async {
              final response = await handler(_request(route));
              expect(response.statusCode, 400);
              expect(
                await response.readAsString(),
                route.method == 'GET'
                    ? 'invalid QA email'
                    : 'invalid JSON body',
              );
            },
          );

          test(
            '${route.method} ${route.path} reaches validation with a query token',
            () async {
              final response = await handler(
                _request(
                  route,
                  authorization: null,
                  queryToken: _token,
                ),
              );
              expect(response.statusCode, 400);
              expect(
                await response.readAsString(),
                route.method == 'GET'
                    ? 'invalid QA email'
                    : 'invalid JSON body',
              );
            },
          );

          test(
            'disabled router never invokes ${route.method} ${route.path} even when its handler permits QA',
            () async {
              // Positive control: these real handlers permit this request.
              // Calling one returns validation's 400, not its auth-guard 404.
              // Only RootRouter receives the QA-disabled environment.
              expect(getIt<Env>().isQaAuthEnabled, isTrue);
              final directResponse = await _direct(route, _request(route));
              expect(directResponse.statusCode, 400);
              expect(
                await directResponse.readAsString(),
                route.method == 'GET'
                    ? 'invalid QA email'
                    : 'invalid JSON body',
              );

              final missing = await disabledRouter(
                Request(
                  route.method,
                  Uri.parse('https://test.tentura.local/_qa/absent-route'),
                ),
              );
              expect(missing.statusCode, 404);
              final missingBody = await missing.readAsString();
              final response = await disabledRouter(_request(route));
              expect(
                response.statusCode,
                404,
                reason: 'Dispatch would return the real handler validation 400',
              );
              expect(await response.readAsString(), missingBody);
            },
          );

          for (final credential in [
            (name: 'missing token', bearer: null, query: null),
            (name: 'wrong Bearer token', bearer: 'Bearer wrong', query: null),
            (name: 'wrong query token', bearer: null, query: 'wrong'),
          ]) {
            test(
              '${route.method} ${route.path} conceals the handler with ${credential.name}',
              () async {
                final response = await handler(
                  _request(
                    route,
                    authorization: credential.bearer,
                    queryToken: credential.query,
                    rawBody: _validBody,
                    email: 'router@test.tentura.local',
                  ),
                );
                expect(response.statusCode, 404);
              },
            );
          }
        }
      }
    });
  }
}
