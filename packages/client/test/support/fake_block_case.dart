import 'dart:async';

import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/features/block/domain/entity/user_block.dart';
import 'package:tentura/features/block/domain/use_case/block_case.dart';

/// In-memory [BlockCase] for cubit and use-case tests.
class FakeBlockCase implements BlockCase {
  List<BlockIntent> fetchMyBlocksResult = const [];
  Object? fetchMyBlocksError;
  final unblockCalls = <String>[];
  final _changes = StreamController<RepositoryEvent<BlockIntent>>.broadcast();

  @override
  Stream<RepositoryEvent<BlockIntent>> get changes => _changes.stream;

  /// Simulates `BlockRepository` announcing a block or unblock.
  void emitChange(RepositoryEvent<BlockIntent> event) => _changes.add(event);

  @override
  Future<List<BlockIntent>> fetchMyBlocks() {
    final error = fetchMyBlocksError;
    if (error != null) {
      return Future.error(error);
    }
    return Future.value(fetchMyBlocksResult);
  }

  @override
  Future<void> unblock({required String objectId}) async {
    unblockCalls.add(objectId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
