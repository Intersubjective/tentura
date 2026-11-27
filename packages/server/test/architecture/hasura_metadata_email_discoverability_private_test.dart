@Tags(['repo-files'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('Hasura keeps the account email discoverability preference private', () {
    final document = _readObject(
      jsonDecode(File('../../hasura/metadata.json').readAsStringSync()),
    );
    final metadata = _readObject(document['metadata']);
    final sources = _readObjects(metadata['sources']);
    final tables = [
      for (final source in sources)
        ..._readObjects(source['tables'] ?? const []),
    ];
    expect(
      tables.map((entry) => _readObject(entry['table'])['name']),
      isNot(contains('user_privacy_setting')),
    );

    // Inspect targets as well as names. An arbitrary relationship alias
    // still exposes the preference if its target is the private table.
    expect(
      jsonEncode(sources),
      isNot(matches(RegExp(r'\buser_privacy_setting\b', caseSensitive: false))),
      reason: 'No database source may reference the preference table',
    );

    final users = tables.where((entry) {
      final table = _readObject(entry['table']);
      return table['schema'] == 'public' && table['name'] == 'user';
    });
    expect(users, isNotEmpty);

    // Check the known preference identifiers in metadata keys and values,
    // including column grants, column aliases, and relationship definitions.
    // Unrelated columns, grants, and relationships may be added freely.
    final preferenceIdentifier = RegExp(
      '(email_?discoverability|discoverable_?by_?email|'
      'can_?be_?found_?by_?email|people_?who_?have_?my_?email)',
      caseSensitive: false,
    );
    for (final user in users) {
      expect(
        jsonEncode(user),
        isNot(matches(preferenceIdentifier)),
        reason:
            'public.user must not expose the preference as a field or relationship',
      );
    }
  });
}

List<Map<String, Object?>> _readObjects(Object? value) {
  if (value case final List<Object?> entries) {
    return entries.map(_readObject).toList();
  }
  fail('Expected a list of metadata objects: $value');
}

Map<String, Object?> _readObject(Object? value) {
  if (value case final Map<String, Object?> object) {
    return object;
  }
  fail('Expected a metadata object: $value');
}
