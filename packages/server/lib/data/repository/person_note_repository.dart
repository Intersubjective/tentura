import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/person_note.dart';
import 'package:tentura_server/domain/port/owner_graph_transaction_port.dart';
import 'package:tentura_server/domain/port/person_note_repository_port.dart';

import '../database/tentura_db.dart';
import 'owner_graph_unit_of_work.dart';

@LazySingleton(as: PersonNoteRepositoryPort)
final class PersonNoteRepository implements PersonNoteRepositoryPort {
  const PersonNoteRepository(this._database);

  final TenturaDb _database;

  @override
  Future<List<PersonNoteSection>> read(
    String ownerId,
    PersonNoteSubject subject,
  ) async {
    final rows = await _database.customSelect(
      r'''
SELECT n.body, p.id AS phantom_id, p.display_name AS phantom_name
FROM public.person_note n
LEFT JOIN public.phantom p ON p.id = n.subject_phantom_id AND p.owner_id = n.owner_id
LEFT JOIN public.phantom_merge m ON m.id = p.current_merge_id
  AND m.phantom_id = p.id AND m.owner_id = p.owner_id
  AND m.user_id = p.merged_user_id AND m.undone_at IS NULL
WHERE n.owner_id = $1 AND (
  n.subject_user_id = $2 OR p.id = $3 OR m.user_id = $2
)
ORDER BY m.created_at NULLS FIRST, m.id
''',
      variables: _subjectVariables(ownerId, subject),
    ).get();
    return [
      for (final row in rows)
        (
          body: row.read<String>('body'),
          phantom: switch (row.readNullable<String>('phantom_id')) {
            final String id => (id: id, name: row.read<String>('phantom_name')),
            null => null,
          },
        ),
    ];
  }

  @override
  Future<List<PersonNoteSubject>> search(String ownerId, String query) =>
      _database.withTransaction(() async {
        await _suppressNoteTextLogging();
        final escaped = query
            .replaceAll('!', '!!')
            .replaceAll('%', '!%')
            .replaceAll('_', '!_');
        final rows = await _database
            .customSelect(
              r'''
SELECT subject_user_id, subject_phantom_id
FROM public.person_note
WHERE owner_id = $1 AND body ILIKE $2 ESCAPE '!'
LIMIT 50
''',
              variables: [
                Variable.withString(ownerId),
                Variable.withString('%$escaped%'),
              ],
            )
            .get();
        return [
          for (final row in rows)
            switch (row.readNullable<String>('subject_user_id')) {
              final String id => PersonNoteSubject.user(id),
              null => PersonNoteSubject.phantom(
                row.read<String>('subject_phantom_id'),
              ),
            },
        ];
      });

  @override
  Future<bool> upsert(
    OwnerGraphScope scope,
    String ownerId,
    PersonNoteSubject subject,
    String body,
  ) async {
    requireOwnerGraphScope(_database, scope, ownerId);
    await _suppressNoteTextLogging();
    // Lock the referenced rows through the write, including when an account
    // is being erased outside the owner scope.
    final count = await _database.customUpdate(
      r'''
INSERT INTO public.person_note AS n (owner_id, subject_user_id, subject_phantom_id, body)
SELECT author.id, $2, $3, $4 FROM public."user" author
WHERE author.id = $1 AND (
  EXISTS (SELECT 1 FROM public."user" u WHERE u.id = $2 FOR KEY SHARE)
  OR EXISTS (
    SELECT 1 FROM public.phantom p WHERE p.id = $3 AND p.owner_id = author.id
    FOR KEY SHARE
  )
)
FOR KEY SHARE OF author
ON CONFLICT (owner_id, subject_user_id, subject_phantom_id) DO UPDATE
SET body = EXCLUDED.body, revision = n.revision + 1, updated_at = now()
''',
      variables: [
        ..._subjectVariables(ownerId, subject),
        Variable.withString(body),
      ],
    );
    return count != 0;
  }

  // Apply only within a transaction, so pooled connections retain their
  // defaults after a save or a search that can contain private note text.
  Future<void> _suppressNoteTextLogging() => _database.customStatement('''
SELECT set_config('log_parameter_max_length', '0', true),
       set_config('log_parameter_max_length_on_error', '0', true),
       set_config('log_error_verbosity', 'terse', true),
       set_config('auto_explain.log_min_duration', '-1', true)
''');

  @override
  Future<bool> delete(
    OwnerGraphScope scope,
    String ownerId,
    PersonNoteSubject subject,
  ) async {
    requireOwnerGraphScope(_database, scope, ownerId);
    final count = await _database.customUpdate(
      r'''
DELETE FROM public.person_note n
WHERE n.owner_id = $1 AND (
  n.subject_user_id = $2 OR (
    n.subject_phantom_id = $3 AND EXISTS (
      SELECT 1 FROM public.phantom p WHERE p.id = $3 AND p.owner_id = $1
    )
  )
)
''',
      variables: _subjectVariables(ownerId, subject),
    );
    return count != 0;
  }

  static List<Variable<String>> _subjectVariables(
    String ownerId,
    PersonNoteSubject subject,
  ) => [
    Variable.withString(ownerId),
    Variable(subject.kind == PersonNoteSubjectKind.user ? subject.id : null),
    Variable(subject.kind == PersonNoteSubjectKind.phantom ? subject.id : null),
  ];
}
