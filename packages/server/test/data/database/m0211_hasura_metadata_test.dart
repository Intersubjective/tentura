import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// Shape of the m0211 Hasura exposure: `viewer_can_forward` computed field and
/// the Post columns on `beacon`, `pinned_at` on `beacon_pinned`. The shape
/// alone proves nothing about validity; see `post_hasura_read_pg_test.dart`
/// for the behaviour through a real Hasura.
Map<String, dynamic> _table(String name) {
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
      if (ref['name'] == name && ref['schema'] == 'public') return t;
    }
  }
  fail('table $name not found in hasura/metadata.json');
}

Map<String, dynamic> _userSelect(Map<String, dynamic> table) {
  final permissions = table['select_permissions'] as List<dynamic>;
  final entry = permissions.cast<Map<String, dynamic>>().singleWhere(
    (p) => p['role'] == 'user',
  );
  return entry['permission'] as Map<String, dynamic>;
}

void main() {
  group('beacon table', () {
    test('declares the viewer_can_forward computed field', () {
      final fields = (_table('beacon')['computed_fields'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final field = fields.singleWhere(
        (f) => f['name'] == 'viewer_can_forward',
      );
      expect(field['definition'], {
        'function': {
          'name': 'beacon_get_viewer_can_forward',
          'schema': 'public',
        },
        'session_argument': 'hasura_session',
        'table_argument': 'beacon_row',
      });
    });

    test('role user may select viewer_can_forward', () {
      final permission = _userSelect(_table('beacon'));
      expect(
        permission['computed_fields'] as List<dynamic>,
        contains('viewer_can_forward'),
      );
    });

    test('role user may select the Post columns', () {
      final permission = _userSelect(_table('beacon'));
      expect(
        permission['columns'] as List<dynamic>,
        containsAll([
          'kind',
          'forward_policy',
          'last_activity_at',
          'post_root_message_id',
        ]),
      );
    });
  });

  group('beacon_pinned table', () {
    test('role user may select pinned_at', () {
      final permission = _userSelect(_table('beacon_pinned'));
      expect(permission['columns'] as List<dynamic>, contains('pinned_at'));
    });
  });
}
