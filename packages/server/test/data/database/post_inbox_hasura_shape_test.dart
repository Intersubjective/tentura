import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// Shape of the Hasura `inbox_item` update permission of role `user`: a Post
/// is left through `postLeave`, which also declines the contact edge and sets
/// room access, so the direct inbox update must be limited to Requests
/// (`beacon.kind = 0`) while still being scoped to the viewer's own rows. The
/// shape alone proves nothing about validity; see
/// `test/api/post_inbox_hasura_pg_test.dart` for the behaviour through a real
/// Hasura.
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

/// Whether [node] requires `beacon.kind = 0`, with the relationship and the
/// comparison possibly nested in `_and` in any order.
bool _requiresRequestKind(Object? node) => _conjuncts(node).any((conjunct) {
  final MapEntry(:key, :value) = conjunct.entries.single;
  if (key != 'beacon') return false;
  return _conjuncts(value).any((inner) {
    final MapEntry(key: field, value: condition) = inner.entries.single;
    return field == 'kind' &&
        condition is _Json &&
        condition.length == 1 &&
        condition['_eq'] == 0;
  });
});

bool _scopedToViewer(Object? node) => _conjuncts(node).any((conjunct) {
  final MapEntry(:key, :value) = conjunct.entries.single;
  return key == 'user_id' &&
      value is _Json &&
      value.length == 1 &&
      value['_eq'] == 'X-Hasura-User-Id';
});

_Json _inboxItemUpdatePermission() {
  final metadata =
      jsonDecode(File('../../hasura/metadata.json').readAsStringSync())
          as _Json;
  final sources = (metadata['metadata'] as _Json)['sources'] as List<dynamic>;
  for (final source in sources) {
    for (final table in (source as _Json)['tables'] as List<dynamic>) {
      final tableJson = table as _Json;
      if ((tableJson['table'] as _Json)['name'] != 'inbox_item') continue;
      final permissions = (tableJson['update_permissions'] as List<dynamic>)
          .cast<_Json>()
          .where((entry) => entry['role'] == 'user');
      return permissions.single['permission'] as _Json;
    }
  }
  throw StateError('inbox_item is not tracked in hasura/metadata.json');
}

void main() {
  group('Post-only recognition of the inbox update filter', () {
    const mine = {
      'user_id': {'_eq': 'X-Hasura-User-Id'},
    };
    const requestKind = {
      'beacon': {
        'kind': {'_eq': 0},
      },
    };

    test('accepts the kind predicate beside the viewer scope', () {
      expect(
        _requiresRequestKind({
          '_and': [mine, requestKind],
        }),
        isTrue,
      );
      expect(_requiresRequestKind({...mine, ...requestKind}), isTrue);
    });

    test('accepts the kind predicate nested inside the relationship', () {
      expect(
        _requiresRequestKind({
          'beacon': {
            '_and': [
              {
                'kind': {'_eq': 0},
              },
            ],
          },
        }),
        isTrue,
      );
    });

    test('rejects a filter without the predicate', () {
      expect(_requiresRequestKind(mine), isFalse);
    });

    test('rejects the wrong kind or comparison', () {
      for (final kind in [
        {'_eq': 1},
        {'_neq': 1},
        {
          '_in': [0, 1],
        },
      ]) {
        expect(
          _requiresRequestKind({
            'beacon': {'kind': kind},
          }),
          isFalse,
          reason: jsonEncode(kind),
        );
      }
    });

    test('rejects the predicate under an _or', () {
      expect(
        _requiresRequestKind({
          '_or': [requestKind, mine],
        }),
        isFalse,
      );
    });
  });

  group(
    'inbox_item update permission of role user in hasura/metadata.json',
    () {
      final permission = _inboxItemUpdatePermission();

      test('is limited to Requests', () {
        expect(
          _requiresRequestKind(permission['filter']),
          isTrue,
          reason:
              'the filter must require beacon.kind = 0, so a Post is only left '
              'through postLeave: ${jsonEncode(permission['filter'])}',
        );
      });

      test("stays scoped to the viewer's own inbox rows", () {
        expect(_scopedToViewer(permission['filter']), isTrue);
      });

      test('allows inbox decisions, private notes, and tombstone dismissal', () {
        expect(
          permission['columns'],
          unorderedEquals([
            'status',
            'rejection_message',
            'private_note',
            'tombstone_dismissed_at',
          ]),
        );
      });
    },
  );
}
