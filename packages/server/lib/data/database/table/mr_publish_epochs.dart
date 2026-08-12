import 'package:drift/drift.dart';

class MrPublishEpochs extends Table {
  late final id = boolean().withDefault(const Constant(true))();

  late final epoch = int64().withDefault(Constant(BigInt.zero))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  String get tableName => 'mr_publish_epoch';

  @override
  bool get withoutRowId => true;
}
