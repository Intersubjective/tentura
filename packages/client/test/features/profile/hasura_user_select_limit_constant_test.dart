@Tags(['repo-files'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'package:tentura/consts.dart';

Map<String, dynamic> _roleUserSelect(Map<String, dynamic> root) {
  final sources =
      ((root['metadata'] as Map<String, dynamic>)['sources'] as List)
          .cast<Map<String, dynamic>>();
  for (final s in sources) {
    for (final t in (s['tables'] as List).cast<Map<String, dynamic>>()) {
      final table = t['table'] as Map<String, dynamic>;
      if (table['name'] != 'user') continue;
      for (final p
          in ((t['select_permissions'] as List?) ?? const [])
              .cast<Map<String, dynamic>>()) {
        if (p['role'] == 'user') {
          return (p['permission'] as Map).cast<String, dynamic>();
        }
      }
    }
  }
  fail('no role-user select permission on table user');
}

void main() {
  test('kHasuraUserSelectLimit equals the role-user select limit on table '
      'user in hasura/metadata.json', () {
    final root =
        jsonDecode(File('../../hasura/metadata.json').readAsStringSync())
            as Map<String, dynamic>;
    final limit = _roleUserSelect(root)['limit'];
    expect(limit, isA<int>());
    expect(kHasuraUserSelectLimit, limit);
  });
}
