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
  });
}
