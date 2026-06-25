import 'package:ferry/ferry.dart' show ResponseFormatException, ServerException;
import 'package:gql_exec/gql_exec.dart';
import 'package:test/test.dart';

import 'package:tentura/data/service/remote_api_client/auth_loss_classifier.dart';
import 'package:tentura/data/service/remote_api_client/exception.dart';
import 'package:tentura/data/service/remote_api_client/session_fetch.dart';
import 'package:tentura/domain/exception/generic_exception.dart';
import 'package:tentura/domain/exception/server_exception.dart' hide ServerException;
import 'package:tentura/features/auth/domain/exception.dart';

void main() {
  group('mapRemoteFailure', () {
    test('GraphQL error surfaces the server message, not "no internet"', () {
      final mapped = mapRemoteFailure(
        const [GraphQLError(message: 'Contact name must be 3–32 characters')],
      );
      expect(mapped, isA<RemoteApiException>());
      expect(
        (mapped as RemoteApiException).toEn,
        'Contact name must be 3–32 characters',
      );
    });

    test('single GraphQL error also surfaces its message', () {
      final mapped = mapRemoteFailure(
        const GraphQLError(
          message: "field 'addressee_name' not found in type: 'invitation'",
        ),
      );
      expect(mapped, isA<RemoteApiException>());
      expect(
        (mapped as RemoteApiException).toEn,
        "field 'addressee_name' not found in type: 'invitation'",
      );
    });

    test('GraphQL error with blank message maps to UnknownException', () {
      final mapped = mapRemoteFailure(const [GraphQLError(message: '  ')]);
      expect(mapped, isA<UnknownException>());
    });

    test('jwt-flavored GraphQL error still maps to auth loss', () {
      final mapped = mapRemoteFailure(
        const [GraphQLError(message: 'Could not verify JWT: JWTExpired')],
      );
      expect(mapped, isA<AuthSessionLostException>());
    });

    test('transport-level failures keep the no-internet mapping', () {
      final mapped = mapRemoteFailure(Exception('SocketException: refused'));
      expect(mapped, isA<ConnectionUplinkException>());
    });

    test('web fetch failures keep the no-internet mapping', () {
      final mapped = mapRemoteFailure(
        Exception('ClientException: Failed to fetch'),
      );
      expect(mapped, isA<ConnectionUplinkException>());
    });

    test('a non-connectivity StateError surfaces its text, not "no internet"',
        () {
      final mapped = mapRemoteFailure(StateError('No element'));
      expect(mapped, isA<RemoteApiException>());
      expect((mapped as RemoteApiException).toEn, contains('No element'));
    });

    test('an unrecognized error surfaces its text, not "no internet"', () {
      final mapped = mapRemoteFailure(Exception('Deserialization failed: foo'));
      expect(mapped, isA<RemoteApiException>());
      expect(
        (mapped as RemoteApiException).toEn,
        contains('Deserialization failed'),
      );
    });

    test('ServerException with GraphQL errors surfaces them, not "no internet"',
        () {
      final mapped = mapRemoteFailure(
        const ServerException(
          statusCode: 400,
          parsedResponse: Response(
            response: {},
            errors: [
              GraphQLError(
                message: "field 'addressee_name' not found in type: 'invitation'",
              ),
            ],
          ),
        ),
      );
      expect(mapped, isA<RemoteApiException>());
      expect(
        (mapped as RemoteApiException).toEn,
        contains("field 'addressee_name' not found"),
      );
      expect(mapped.toEn, contains('HTTP 400'));
    });

    test('ServerException with auth-loss GraphQL error maps to auth loss', () {
      final mapped = mapRemoteFailure(
        const ServerException(
          statusCode: 400,
          parsedResponse: Response(
            response: {},
            errors: [GraphQLError(message: 'Could not verify JWT: JWTExpired')],
          ),
        ),
      );
      expect(mapped, isA<AuthSessionLostException>());
    });

    test('ServerException with only a status code surfaces the status', () {
      final mapped = mapRemoteFailure(
        const ServerException(statusCode: 502),
      );
      expect(mapped, isA<RemoteApiException>());
      expect((mapped as RemoteApiException).toEn, contains('502'));
    });

    test('ServerException with 401 status maps to auth loss', () {
      final mapped = mapRemoteFailure(
        const ServerException(statusCode: 401),
      );
      expect(mapped, isA<AuthSessionLostException>());
    });

    test('ServerException from a socket failure keeps the no-internet mapping',
        () {
      final mapped = mapRemoteFailure(
        ServerException(
          originalException: Exception('SocketException: refused'),
        ),
      );
      expect(mapped, isA<ConnectionUplinkException>());
    });

    test(
        'ServerException re-wrapping a RemoteApiException surfaces its message',
        () {
      // Reproduces the real bug: ErrorLink throws RemoteApiException for a
      // GraphQL error, and ferry re-wraps it as a ServerException with a null
      // parsedResponse. The original message must survive, not the wrapper's
      // toString().
      final mapped = mapRemoteFailure(
        const ServerException(
          originalException: RemoteApiException(
            "Invalid argument (value): Unsupported type: Instance of 'PgDateTime'",
          ),
        ),
      );
      expect(mapped, isA<RemoteApiException>());
      expect(
        (mapped as RemoteApiException).toEn,
        contains("Unsupported type: Instance of 'PgDateTime'"),
      );
    });

    test('unparseable response body surfaces a malformed-response message', () {
      final mapped = mapRemoteFailure(
        const ResponseFormatException(
          originalException: FormatException('Unexpected <'),
        ),
      );
      expect(mapped, isA<RemoteApiException>());
      expect(
        (mapped as RemoteApiException).toEn,
        contains('Malformed server response'),
      );
    });
  });

  group('mapRemoteFailure — auth-loss shapes', () {
    test('GraphQL extensions code invalid-jwt maps to auth loss', () {
      final mapped = mapRemoteFailure(
        const GraphQLError(
          message: 'JWT invalid',
          extensions: {'code': 'invalid-jwt'},
        ),
      );
      expect(mapped, isA<AuthSessionLostException>());
    });

    test('GraphQL extensions code invalid_jwt maps to auth loss', () {
      final mapped = mapRemoteFailure(
        const GraphQLError(
          message: 'JWT invalid',
          extensions: {'code': 'invalid_jwt'},
        ),
      );
      expect(mapped, isA<AuthSessionLostException>());
    });

    test('GraphQL message containing invalid-jwt maps to auth loss', () {
      final mapped = mapRemoteFailure(
        const GraphQLError(message: 'invalid-jwt: token expired'),
      );
      expect(mapped, isA<AuthSessionLostException>());
    });

    test('auth-loss GraphQL error in a list takes precedence over later errors',
        () {
      final mapped = mapRemoteFailure(
        const [
          GraphQLError(message: 'Contact name must be 3–32 characters'),
          GraphQLError(message: 'Could not verify JWT: JWTExpired'),
        ],
      );
      expect(mapped, isA<AuthSessionLostException>());
    });

    test('raw exception text with jwt markers maps to auth loss', () {
      for (final message in [
        'invalid-jwt',
        'invalid jwt',
        'JWTExpired',
        'Could not verify JWT: signature mismatch',
      ]) {
        expect(
          mapRemoteFailure(Exception(message)),
          isA<AuthSessionLostException>(),
          reason: message,
        );
      }
    });

    test('ServerException HTTP 403 maps to auth loss', () {
      final mapped = mapRemoteFailure(
        const ServerException(statusCode: 403),
      );
      expect(mapped, isA<AuthSessionLostException>());
    });

    test('SessionHttpException 401/403 maps to auth loss', () {
      expect(
        mapRemoteFailure(SessionHttpException(401)),
        isA<AuthSessionLostException>(),
      );
      expect(
        mapRemoteFailure(SessionHttpException(403)),
        isA<AuthSessionLostException>(),
      );
    });

    test('SessionHttpException other status maps to ServerStatusException', () {
      final mapped = mapRemoteFailure(SessionHttpException(502));
      expect(mapped, isA<ServerStatusException>());
      expect((mapped as ServerStatusException).statusCode, 502);
    });

    test('ServerStatusException 401 maps to auth loss', () {
      expect(
        mapRemoteFailure(const ServerStatusException(401)),
        isA<AuthSessionLostException>(),
      );
    });

    test('ServerStatusException 403 stays a resource error', () {
      final mapped = mapRemoteFailure(const ServerStatusException(403));
      expect(mapped, isA<ServerStatusException>());
      expect((mapped as ServerStatusException).statusCode, 403);
    });

    test('authentication failures from the link layer map to auth loss', () {
      expect(
        mapRemoteFailure(const AuthenticationNoKeyException()),
        isA<AuthSessionLostException>(),
      );
      expect(
        mapRemoteFailure(const AuthenticationFailedException()),
        isA<AuthSessionLostException>(),
      );
    });
  });

  group('mapRemoteFailure — pass-through', () {
    test('already-classified auth exceptions pass through unchanged', () {
      const authLost = AuthSessionLostException();
      const authRejected = SessionAuthRejectedException();
      expect(mapRemoteFailure(authLost), same(authLost));
      expect(mapRemoteFailure(authRejected), same(authRejected));
    });

    test('an already-classified domain exception passes through unchanged', () {
      const original = ConnectionUplinkException();
      expect(mapRemoteFailure(original), same(original));
    });
  });
}
