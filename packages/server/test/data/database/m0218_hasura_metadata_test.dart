import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// Shape of the m0218 Hasura exposure: `user.shares_episode_with_viewer`
/// (#159, #104). Behaviour lives in `m0218_shares_episode_pg_test.dart`.
Map<String, dynamic> _userTable() {
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
      if (ref['name'] == 'user' && ref['schema'] == 'public') return t;
    }
  }
  fail('table user not found in hasura/metadata.json');
}

void main() {
  test('user declares the shares_episode_with_viewer computed field', () {
    final fields = (_userTable()['computed_fields'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final field = fields.singleWhere(
      (f) => f['name'] == 'shares_episode_with_viewer',
    );
    expect(field['definition'], {
      'function': {
        'name': 'user_get_shares_episode_with_viewer',
        'schema': 'public',
      },
      'session_argument': 'hasura_session',
      'table_argument': 'user_row',
    });
  });

  test('role user may select shares_episode_with_viewer', () {
    final permissions = (_userTable()['select_permissions'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final permission =
        permissions.singleWhere((p) => p['role'] == 'user')['permission']
            as Map<String, dynamic>;
    expect(
      permission['computed_fields'] as List<dynamic>,
      contains('shares_episode_with_viewer'),
    );
  });
}
