import 'dart:convert';
import 'dart:io';

/// The SQL value of the `resume_on` clause in the `user` role's
/// `user_availability` select filter in `hasura/metadata.json` (today
/// `now()`), so tests evaluate what Hasura evaluates instead of restating it.
///
/// Hasura accepts only a bare no-argument SQL function there; anything else is
/// refused so it can be spliced into a query safely.
String hasuraUserAvailabilityResumeOnExpression() {
  final metadataFile = File(
    '${Directory.current.path}/../../hasura/metadata.json',
  );
  final metadata =
      jsonDecode(metadataFile.readAsStringSync()) as Map<String, dynamic>;
  final sources =
      (metadata['metadata'] as Map<String, dynamic>)['sources']
          as List<dynamic>;
  final tables =
      (sources.first as Map<String, dynamic>)['tables'] as List<dynamic>;
  final availability = tables.cast<Map<String, dynamic>>().firstWhere(
    (entry) =>
        (entry['table'] as Map<String, dynamic>)['name'] == 'user_availability',
  );
  final permission =
      (availability['select_permissions'] as List<dynamic>).single
          as Map<String, dynamic>;
  final filter =
      (permission['permission'] as Map<String, dynamic>)['filter']
          as Map<String, dynamic>;
  final or =
      (filter['_and'] as List<dynamic>).cast<Map<String, dynamic>>().firstWhere(
            (clause) => clause.containsKey('_or'),
          )['_or']
          as List<dynamic>;
  final expression =
      or
              .cast<Map<String, dynamic>>()
              .map((clause) => clause['resume_on'])
              .whereType<Map<String, dynamic>>()
              .single['_gt']
          as String;
  if (!RegExp(r'^[a-z_][a-z0-9_]*\(\)$').hasMatch(expression)) {
    throw StateError(
      'user_availability resume_on filter is not a bare SQL function: '
      '$expression',
    );
  }
  return expression;
}
