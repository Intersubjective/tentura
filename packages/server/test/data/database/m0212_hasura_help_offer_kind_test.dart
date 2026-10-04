import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// Shape of the m0212 Hasura change: the `beacon_help_offer` insert and update
/// checks for role `user` require the beacon to be a Request (`kind = 0`). The
/// shape alone proves nothing about validity; see
/// `test/api/help_offer_post_hasura_pg_test.dart` for the behaviour through a
/// real Hasura.
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

Map<String, dynamic> _userPermission(
  Map<String, dynamic> table,
  String operation,
) {
  final permissions = table['${operation}_permissions'] as List<dynamic>;
  final entry = permissions.cast<Map<String, dynamic>>().singleWhere(
    (p) => p['role'] == 'user',
  );
  return entry['permission'] as Map<String, dynamic>;
}

/// The conditions a `check` imposes on the `beacon` relationship, flattening
/// nested `_and` groups: `{"beacon": {"_and": [...]}}` and
/// `{"_and": [{"beacon": {...}}, ...]}` both count.
List<Map<String, dynamic>> _beaconConditions(Object? check) {
  final conditions = <Map<String, dynamic>>[];
  void walkBeacon(Object? node) {
    if (node is! Map<String, dynamic>) return;
    final and = node['_and'];
    if (and is List<dynamic>) {
      and.forEach(walkBeacon);
      return;
    }
    conditions.add(node);
  }

  void walk(Object? node) {
    if (node is! Map<String, dynamic>) return;
    final and = node['_and'];
    if (and is List<dynamic>) {
      and.forEach(walk);
      return;
    }
    walkBeacon(node['beacon']);
  }

  walk(check);
  return conditions;
}

void main() {
  final table = _table('beacon_help_offer');

  group('beacon_help_offer table', () {
    test('role user may only insert help offers on a Request', () {
      final check = _userPermission(table, 'insert')['check'];
      expect(
        _beaconConditions(check),
        contains(
          equals({
            'kind': {'_eq': 0},
          }),
        ),
      );
    });

    test('role user keeps the insert status and readability checks', () {
      final check = _userPermission(table, 'insert')['check'];
      final conditions = _beaconConditions(check);
      expect(
        conditions,
        containsAll([
          equals({
            'status': {
              '_in': [0, 7, 8],
            },
          }),
          equals({
            'can_read_content': {'_eq': true},
          }),
        ]),
      );
    });

    test('role user may only update help offers on a Request', () {
      final check = _userPermission(table, 'update')['check'];
      expect(
        _beaconConditions(check),
        contains(
          equals({
            'kind': {'_eq': 0},
          }),
        ),
      );
    });

    test('role user keeps the update status check', () {
      final check = _userPermission(table, 'update')['check'];
      expect(
        _beaconConditions(check),
        contains(
          equals({
            'status': {
              '_in': [0, 7, 8],
            },
          }),
        ),
      );
    });
  });
}
