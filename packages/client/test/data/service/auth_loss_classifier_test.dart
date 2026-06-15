import 'package:ferry/ferry.dart' show ResponseFormatException, ServerException;
import 'package:gql_exec/gql_exec.dart';
import 'package:test/test.dart';

import 'package:tentura/data/service/remote_api_client/auth_loss_classifier.dart';
import 'package:tentura/domain/exception/generic_exception.dart';
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
}
