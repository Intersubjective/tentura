import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// Shape of the Hasura room permissions: every permission of role `user`
/// whose filter admits a room participant (`room_access = 3`) must also carry
/// the Post-only block predicate — `kind = 0 OR can_read_content = true` on
/// the beacon, so a Request is unaffected. The predicate is recognised by its
/// meaning (any key order, extra `_and` nesting, `_or` placed above or below
/// the `beacon` relationship), not by one serialisation. The shape alone
/// proves nothing about validity; see
/// `test/api/post_room_block_hasura_pg_test.dart` for the behaviour through a
/// real Hasura.
const _admittedAccess = 3;

/// The two disjuncts of the Post-only predicate.
const _guardAtoms = {'kind=0', 'can_read_content'};

typedef _Json = Map<String, dynamic>;

/// Splits a filter into its implicit conjunction: one single-key map per key,
/// with `_and` lists flattened.
List<_Json> _conjuncts(Object? node) {
  if (node is! _Json) return const [];
  return [
    for (final entry in node.entries)
      if (entry.key == '_and' && entry.value is List<dynamic>)
        for (final child in entry.value as List<dynamic>) ..._conjuncts(child)
      else
        {entry.key: entry.value},
  ];
}

/// The disjuncts a node reduces to when it is nothing but an `_or` of
/// `kind = 0` / `can_read_content = true` conditions, possibly wrapped in the
/// `beacon` relationship or a single-child `_and`; `null` otherwise.
Set<String>? _atoms(Object? node) {
  final conjuncts = _conjuncts(node);
  if (conjuncts.length != 1) return null;
  final MapEntry(:key, :value) = conjuncts.single.entries.single;
  switch (key) {
    case 'beacon':
      return _atoms(value);
    case '_or':
      if (value is! List<dynamic>) return null;
      final result = <String>{};
      for (final child in value) {
        final atoms = _atoms(child);
        if (atoms == null) return null;
        result.addAll(atoms);
      }
      return result;
    case 'kind':
      return value is _Json && value.length == 1 && value['_eq'] == 0
          ? {'kind=0'}
          : null;
    case 'can_read_content':
      return value is _Json && value.length == 1 && value['_eq'] == true
          ? {'can_read_content'}
          : null;
  }
  return null;
}

bool _isGuard(Object? node) {
  final atoms = _atoms(node);
  return atoms != null &&
      atoms.length == _guardAtoms.length &&
      atoms.containsAll(_guardAtoms);
}

/// Whether [node] can only hold when the Post-only predicate holds.
bool _impliesGuard(Object? node) {
  if (_isGuard(node)) return true;
  return _conjuncts(node).any((conjunct) {
    final MapEntry(:key, :value) = conjunct.entries.single;
    return switch (key) {
      'beacon' => _impliesGuard(value),
      '_or' =>
        value is List<dynamic> &&
            value.isNotEmpty &&
            value.every(_impliesGuard),
      _ => false,
    };
  });
}

bool _admitsAccess(Object? condition) {
  if (condition is! _Json) return true;
  return condition.entries.every((op) {
    final v = op.value;
    return switch (op.key) {
      '_eq' => v == _admittedAccess,
      '_neq' => v != _admittedAccess,
      '_in' => v is List<dynamic> && v.contains(_admittedAccess),
      '_nin' => v is List<dynamic> && !v.contains(_admittedAccess),
      '_gt' => v is num && _admittedAccess > v,
      '_gte' => v is num && _admittedAccess >= v,
      '_lt' => v is num && _admittedAccess < v,
      '_lte' => v is num && _admittedAccess <= v,
      _ => true,
    };
  });
}

bool _admitsRoomAccess(Object? node) {
  if (node is _Json) {
    if (node.containsKey('room_access') && _admitsAccess(node['room_access'])) {
      return true;
    }
    return node.values.any(_admitsRoomAccess);
  }
  if (node is List<dynamic>) return node.any(_admitsRoomAccess);
  return false;
}

/// True when every alternative of [node] that admits a room participant is
/// guarded.
bool _roomAdmissionIsGuarded(Object? node) {
  if (!_admitsRoomAccess(node)) return true;
  final conjuncts = _conjuncts(node);
  if (conjuncts.any(_impliesGuard)) return true;
  final admitting = conjuncts.where(_admitsRoomAccess);
  return admitting.isNotEmpty &&
      admitting.every((conjunct) {
        final MapEntry(:key, :value) = conjunct.entries.single;
        return key == '_or' &&
            value is List<dynamic> &&
            value.every(_roomAdmissionIsGuarded);
      });
}

List<_Json> _tables() {
  final metadata =
      jsonDecode(File('../../hasura/metadata.json').readAsStringSync())
          as _Json;
  final sources = (metadata['metadata'] as _Json)['sources'] as List<dynamic>;
  return [
    for (final source in sources)
      for (final table in (source as _Json)['tables'] as List<dynamic>)
        table as _Json,
  ];
}

/// `table.operation` -> the `filter` / `check` of every permission of role
/// `user` that admits a room participant.
Map<String, Object?> _admittingPermissions() {
  final result = <String, Object?>{};
  for (final table in _tables()) {
    final name = (table['table'] as _Json)['name']! as String;
    for (final MapEntry(:key, :value) in table.entries) {
      if (!key.endsWith('_permissions')) continue;
      for (final entry in (value as List<dynamic>).cast<_Json>()) {
        if (entry['role'] != 'user') continue;
        final permission = entry['permission'] as _Json;
        for (final field in ['filter', 'check']) {
          if (_admitsRoomAccess(permission[field])) {
            result['$name.$key.$field'] = permission[field];
          }
        }
      }
    }
  }
  return result;
}

void main() {
  group('Post-only predicate recognition', () {
    const kindIsRequest = {
      'kind': {'_eq': 0},
    };
    const readable = {
      'can_read_content': {'_eq': true},
    };
    const admitted = {
      'beacon': {
        'beacon_participants': {
          'user_id': {'_eq': 'X-Hasura-User-Id'},
          'room_access': {'_eq': 3},
        },
      },
    };

    test('accepts the predicate above or below the beacon relationship', () {
      expect(
        _roomAdmissionIsGuarded({
          '_and': [
            admitted,
            {
              '_or': [
                {'beacon': kindIsRequest},
                {'beacon': readable},
              ],
            },
          ],
        }),
        isTrue,
      );
      expect(
        _roomAdmissionIsGuarded({
          '_and': [
            admitted,
            {
              'beacon': {
                '_or': [readable, kindIsRequest],
              },
            },
          ],
        }),
        isTrue,
      );
    });

    test('accepts reordered keys and harmless nesting', () {
      expect(
        _roomAdmissionIsGuarded({
          '_and': [
            {
              '_and': [
                {
                  '_or': [
                    {
                      '_and': [
                        {'beacon': readable},
                      ],
                    },
                    {'beacon': kindIsRequest},
                  ],
                },
              ],
            },
            admitted,
          ],
        }),
        isTrue,
      );
    });

    test('accepts the guard in the same map as the admission', () {
      expect(
        _roomAdmissionIsGuarded({
          ...admitted,
          '_or': [
            {'beacon': kindIsRequest},
            {'beacon': readable},
          ],
        }),
        isTrue,
      );
    });

    test('rejects an admission without the predicate', () {
      expect(_roomAdmissionIsGuarded(admitted), isFalse);
    });

    test('rejects a predicate that is missing one disjunct', () {
      expect(
        _roomAdmissionIsGuarded({
          '_and': [
            admitted,
            {'beacon': readable},
          ],
        }),
        isFalse,
      );
      expect(
        _roomAdmissionIsGuarded({
          '_and': [
            admitted,
            {'beacon': kindIsRequest},
          ],
        }),
        isFalse,
      );
    });

    test('rejects a guard on one alternative of an unguarded admission', () {
      expect(
        _roomAdmissionIsGuarded({
          '_or': [
            {
              '_and': [
                admitted,
                {
                  'beacon': {
                    '_or': [kindIsRequest, readable],
                  },
                },
              ],
            },
            admitted,
          ],
        }),
        isFalse,
      );
    });

    test('treats an admission written as _in or a range as admitting', () {
      expect(
        _roomAdmissionIsGuarded({
          'room_access': {
            '_in': [3, 5],
          },
        }),
        isFalse,
      );
      expect(
        _roomAdmissionIsGuarded({
          'room_access': {'_gte': 3},
        }),
        isFalse,
      );
      expect(
        _roomAdmissionIsGuarded({
          'room_access': {'_eq': 5},
        }),
        isTrue,
      );
    });
  });

  group('room permissions of role user in hasura/metadata.json', () {
    final admitting = _admittingPermissions();

    test('beacon_participant select admits room participants', () {
      expect(
        admitting.keys,
        contains('beacon_participant.select_permissions.filter'),
      );
    });

    test('every permission admitting room participants is scoped to Posts', () {
      for (final MapEntry(key: where, value: node) in admitting.entries) {
        expect(
          _roomAdmissionIsGuarded(node),
          isTrue,
          reason:
              '$where admits room_access = $_admittedAccess without the '
              'kind = 0 OR can_read_content = true predicate: '
              '${jsonEncode(node)}',
        );
      }
    });
  });
}
