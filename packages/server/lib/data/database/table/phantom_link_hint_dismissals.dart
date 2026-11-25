import 'package:drift/drift.dart';

import 'phantoms.dart';
import 'users.dart';

class PhantomLinkHintDismissals extends Table {
  late final phantomId = text().references(
    Phantoms,
    #id,
    onDelete: KeyAction.cascade,
  )();

  late final userId = text().references(
    Users,
    #id,
    onDelete: KeyAction.cascade,
  )();

  @override
  Set<Column<Object>> get primaryKey => {phantomId, userId};

  @override
  String get tableName => 'phantom_link_hint_dismissal';
}
