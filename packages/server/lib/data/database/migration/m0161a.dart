part of '_migrations.dart';

/// Install the cache before 0162 on fresh databases without changing old stamps.
/// Keep 0163a registered for databases already past this prerequisite version.
final m0161a = Migration('0161a', m0163a.statements);
