@Tags(['repo-files'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  late Map<String, dynamic> metadata;
  late List<Map<String, dynamic>> tables;

  setUpAll(() {
    final document =
        jsonDecode(File('../../hasura/metadata.json').readAsStringSync())
            as Map<String, dynamic>;
    metadata = document['metadata'] as Map<String, dynamic>;
    tables = [
      for (final source
          in (metadata['sources'] as List).cast<Map<String, dynamic>>())
        ...(source['tables'] as List? ?? const []).cast<Map<String, dynamic>>(),
    ];
    expect(tables, isNotEmpty);
  });

  test('Hasura tracks no tables for people outside Tentura', () {
    final exposed = [
      for (final table in tables)
        if (((table['table'] as Map)['name'] as String).startsWith('phantom'))
          table['table'],
    ];
    expect(exposed, isEmpty);
  });

  test('Hasura metadata never references private avatar storage tables', () {
    expect(
      jsonEncode(metadata),
      isNot(
        matches(
          RegExp(
            r'\b(?:person_private_avatar|private_object_gc)\b',
            caseSensitive: false,
          ),
        ),
      ),
    );
  });

  test('only the issuer can select an invitation’s linked person id', () {
    final invitations = [
      for (final table in tables)
        if (table['table'] case {'schema': 'public', 'name': 'invitation'})
          table,
    ];
    expect(invitations, isNotEmpty);

    for (final invitation in invitations) {
      final grants = [
        for (final entry in invitation.entries)
          if (entry.key.endsWith('_permissions'))
            for (final grant
                in (entry.value as List).cast<Map<String, dynamic>>())
              if (_includesLinkedPerson(grant['permission'] as Map))
                (kind: entry.key, role: grant['role']),
      ];
      expect(grants, [(kind: 'select_permissions', role: 'user')]);

      final selects = (invitation['select_permissions'] as List)
          .cast<Map<String, dynamic>>();
      final user = selects.singleWhere((grant) => grant['role'] == 'user');
      final permission = user['permission'] as Map;
      expect(permission['columns'], contains('phantom_id'));
      expect(permission['filter'], {
        'user_id': {'_eq': 'X-Hasura-User-Id'},
      });
    }
  });
}

bool _includesLinkedPerson(Map<dynamic, dynamic> permission) {
  final columns = permission['columns'];
  final preset = permission['set'] as Map?;
  return columns == '*' ||
      (columns is List &&
          (columns.contains('phantom_id') || columns.contains('*'))) ||
      (preset?.containsKey('phantom_id') ?? false);
}
