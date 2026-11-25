@Tags(['pg', 'repo-files'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../support/disposable_pg_target.dart';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_HASURA_PRIVATE_NOTES_TEST_DB',
    defaultNamePrefix: 'tentura_test_hasura_private_notes',
  );
  final skip = await pgSkipReason(target);

  late DisposablePgWriterSession session;
  setUpAll(() async {
    session = await setUpDisposablePgWriter(target: target);
    addTearDown(() => tearDownDisposablePgWriter(session: session));
  });

  test('Hasura grants no access to the private notes table', () async {
    final document =
        jsonDecode(File('../../hasura/metadata.json').readAsStringSync())
            as Map<String, Object?>;
    final metadata = document['metadata']! as Map<String, Object?>;
    final sources = (metadata['sources']! as List<Object?>)
        .cast<Map<String, Object?>>();
    final tables = [
      for (final source in sources)
        ...(source['tables'] as List<Object?>? ?? const [])
            .cast<Map<String, Object?>>(),
    ];

    expect(
      tables,
      contains(
        containsPair('table', {
          'schema': 'public',
          'name': 'user',
        }),
      ),
    );
    expect(
      [
        for (final entry in tables)
          if (entry['table'] case {'name': 'person_note'}) entry,
      ],
      isEmpty,
      reason: 'An untracked table has no Hasura CRUD permissions for any role.',
    );

    final table = await session.writer.execute(
      "SELECT to_regclass('public.person_note') IS NOT NULL",
    );
    expect(
      table.single.single,
      isTrue,
      reason: 'The migrated schema must store notes outside Hasura.',
    );
  }, skip: skip);
}
