// SPDX-License-Identifier: AGPL-3.0-only
import 'package:postgres/postgres.dart' show PgException;
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/unmapped_graphql_error.dart';

void main() {
  group('unmappedGraphqlError', () {
    test('never forwards a database driver error to the client', () {
      final error = PgException(
        '23503: insert or update on table "ego_witness_window" violates '
        'foreign key constraint "ego_witness_window_witness_user_id_fkey" '
        'detail: Key (witness_user_id)=(Vde0a2ed44ac8) is not present in '
        'table "user"',
      );

      final entry = unmappedGraphqlError(error);

      expect(entry['message'], kUnmappedDatabaseErrorMessage);
      expect(entry['extensions'], containsPair('code', '1000'));
      final text = entry.toString();
      for (final leak in [
        '23503',
        'ego_witness_window',
        'fkey',
        'Vde0a2ed44ac8',
        'Severity',
      ]) {
        expect(text, isNot(contains(leak)));
      }
    });

    test('keeps the message of other unmapped exceptions', () {
      expect(
        unmappedGraphqlError(StateError('Request is not open.')),
        {'message': 'Bad state: Request is not open.'},
      );
    });
  });
}
