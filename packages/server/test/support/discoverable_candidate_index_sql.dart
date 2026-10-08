// DDL discovery locates the migration to exercise; the upgrade test uses
// PostgreSQL's catalog, not this parser, to verify the actual index behavior.
// Accept quoted identifiers, optional index names, explicit ordering, ONLY,
// CONCURRENTLY, comments and clauses between the key list and WHERE.
final _candidateIndexDdl = RegExp(
  r'CREATE\s+(?:UNIQUE\s+)?INDEX\s+(?:CONCURRENTLY\s+)?'
  r'(?:IF\s+NOT\s+EXISTS\s+)?'
  r'(?:("(?:[^"]|"")*"|[^\s(]+)\s+)?ON\s+(?:ONLY\s+)?'
  r'(?:(?:"public"|public)\s*\.\s*)?(?:"beacon"|beacon)\s*'
  r'(?:USING\s+(?:"btree"|btree)\s*)?'
  r'\(\s*(?:"user_id"|user_id)(?![A-Za-z0-9_$])[^,();]*,\s*'
  r'(?:"id"|id)(?![A-Za-z0-9_$])[^,();]*\)'
  r'[^;]*?\bWHERE\b',
  caseSensitive: false,
);

Iterable<String?> discoverableCandidateIndexNames(String statement) sync* {
  final sql = statement.replaceAllMapped(
    RegExp(r'"(?:[^"]|"")*"|/\*[\s\S]*?\*/|--[^\n]*'),
    (match) => match.group(0)!.startsWith('"') ? match.group(0)! : ' ',
  );
  for (final match in _candidateIndexDdl.allMatches(sql)) {
    final name = match.group(1);
    yield name == null
        ? null
        : name.startsWith('"')
        ? name.substring(1, name.length - 1).replaceAll('""', '"')
        : name.toLowerCase();
  }
}
