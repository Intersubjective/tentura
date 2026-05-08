import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart' show PgTypes;
import 'package:postgres/postgres.dart' as pg;

/// Postgres `text[]` for `beacon_room_message.mentions`.
///
/// The `postgres` driver may decode arrays that contain SQL NULL elements as
/// `List<String?>`. The stock `text[]` mapping reads with `fromSql as List<String>`,
/// which throws at runtime (see migration `0060` comment).
final class MentionsTextArrayType implements CustomSqlType<List<String>> {
  const MentionsTextArrayType();

  @override
  List<String> read(Object fromSql) {
    if (fromSql is List<String>) {
      return fromSql;
    }
    if (fromSql is! List) {
      return const [];
    }
    final out = <String>[];
    for (final e in fromSql) {
      if (e is String) {
        out.add(e);
      }
    }
    return out;
  }

  @override
  Object mapToSqlParameter(List<String> dartValue) =>
      pg.TypedValue(pg.Type.textArray, dartValue);

  @override
  String mapToSqlLiteral(List<String> dartValue) =>
      PgTypes.textArray.mapToSqlLiteral(dartValue);

  @override
  String sqlTypeName(GenerationContext context) => 'text[]';
}

/// Drift-generated `tentura_db.g.dart` references this; it must be in scope for
/// `package:tentura_server/data/database/tentura_db.dart` (import there), not
/// only under `table/`.
const kMentionsTextArrayType = MentionsTextArrayType();
