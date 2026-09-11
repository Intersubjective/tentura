import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/read_snapshot_port.dart';

import '../database/tentura_db.dart';

@Singleton(as: ReadSnapshotPort)
class ReadSnapshotUnitOfWork implements ReadSnapshotPort {
  const ReadSnapshotUnitOfWork(this._database);

  final TenturaDb _database;

  @override
  Future<T> withReadSnapshot<T>(Future<T> Function() action) =>
      _database.withReadSnapshot(action);
}
