part of '_migrations.dart';

/// Query observability on prod (#228): the library is preloaded by
/// compose.prod.yaml; this makes the `pg_stat_statements` view available.
final m0234 = Migration('0234', [
  'CREATE EXTENSION IF NOT EXISTS pg_stat_statements',
]);
