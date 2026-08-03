import 'dart:async';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/features/block/data/repository/block_repository.dart';
import 'package:tentura/features/block/domain/entity/user_block.dart';
import 'package:tentura/features/block/domain/use_case/block_case.dart';

/// Inert [BlockCase] for tests that do not exercise block invalidation.
BlockCase noopBlockCase() => BlockCase(_NoopBlockRepository());

class _NoopBlockRepository implements BlockRepository {
  @override
  Stream<RepositoryEvent<BlockIntent>> get changes => const Stream.empty();

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Test double with a controllable [changes] stream for invalidation tests.
class ControllableBlockCase implements BlockCase {
  final _controller =
      StreamController<RepositoryEvent<BlockIntent>>.broadcast();

  @override
  Stream<RepositoryEvent<BlockIntent>> get changes => _controller.stream;

  void emitBlock({String objectId = 'U-blocked'}) {
    _controller.add(
      RepositoryEventCreate(BlockIntent(blocked: Profile(id: objectId))),
    );
  }

  Future<void> dispose() => _controller.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
