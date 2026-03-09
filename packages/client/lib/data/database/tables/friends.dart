import 'package:drift/drift.dart';

class Friends extends Table {
  TextColumn get subjectId => text()();

  TextColumn get objectId => text()();

  TextColumn get title => text().withDefault(const Constant(''))();

  TextColumn get imageId => text().withDefault(const Constant(''))(); // v2

  TextColumn get blurHash => text().withDefault(const Constant(''))(); // v2

  IntColumn get height => integer().withDefault(const Constant(0))(); // v2

  IntColumn get width => integer().withDefault(const Constant(0))(); // v2

  @override
  bool get withoutRowId => true;

  @override
  Set<Column> get primaryKey => {subjectId, objectId};
}
