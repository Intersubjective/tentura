@Tags(['repo-files'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('Hasura exposes the linked person id only on the issuer’s invites', () {
    final document =
        jsonDecode(File('../../hasura/metadata.json').readAsStringSync())
            as Map<String, dynamic>;
    final metadata = document['metadata'] as Map<String, dynamic>;
    final sources = (metadata['sources'] as List).cast<Map<String, dynamic>>();
    final tables = sources.expand(
      (source) => (source['tables'] as List).cast<Map<String, dynamic>>(),
    );
    final invitation = tables.singleWhere((table) {
      final ref = table['table'] as Map<String, dynamic>;
      return ref['schema'] == 'public' && ref['name'] == 'invitation';
    });
    final permissions = (invitation['select_permissions'] as List)
        .cast<Map<String, dynamic>>();
    final user = permissions.singleWhere((entry) => entry['role'] == 'user');
    final permission = user['permission'] as Map<String, dynamic>;

    expect(permission['filter'], {
      'user_id': {'_eq': 'X-Hasura-User-Id'},
    });
    expect(permission['columns'], contains('phantom_id'));
  });
}
