@Tags(['repo-files'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// Shape of the Hasura exposure of the Post lifetime: role `user` may select
/// `beacon.expires_at`. The shape alone proves nothing about validity; see
/// `test/api/hasura_beacon_expires_at_pg_test.dart` for the behaviour through a
/// real Hasura.
Map<String, dynamic> _beaconTable() {
  final metadata =
      jsonDecode(File('../../hasura/metadata.json').readAsStringSync())
          as Map<String, dynamic>;
  final sources =
      (metadata['metadata'] as Map<String, dynamic>)['sources']
          as List<dynamic>;
  for (final source in sources) {
    for (final table
        in (source as Map<String, dynamic>)['tables'] as List<dynamic>) {
      final t = table as Map<String, dynamic>;
      final ref = t['table'] as Map<String, dynamic>;
      if (ref['name'] == 'beacon' && ref['schema'] == 'public') return t;
    }
  }
  fail('table beacon not found in hasura/metadata.json');
}

void main() {
  group('beacon select permission', () {
    test('role user may select expires_at', () {
      final permissions =
          _beaconTable()['select_permissions'] as List<dynamic>;
      final entry = permissions.cast<Map<String, dynamic>>().singleWhere(
        (p) => p['role'] == 'user',
      );
      final permission = entry['permission'] as Map<String, dynamic>;
      expect(permission['columns'] as List<dynamic>, contains('expires_at'));
    });
  });
}
