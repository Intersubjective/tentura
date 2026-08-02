import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/features/block/data/repository/block_repository.dart';
import 'package:tentura/features/block/domain/entity/user_block.dart';
import 'package:tentura/features/block/domain/use_case/block_case.dart';

void main() {
  group('BlockCase', () {
    late FakeBlockRepository repository;
    late BlockCase case_;

    setUp(() {
      repository = FakeBlockRepository();
      case_ = BlockCase(repository);
    });

    test('block calls repository with cascade mode and triggers invalidation',
        () async {
      final events = <RepositoryEvent<BlockIntent>>[];
      final sub = repository.changes.listen(events.add);

      await case_.block(objectId: 'user-blocked', cascadeMode: 2);

      expect(
        repository.lastBlock,
        (objectId: 'user-blocked', cascadeMode: 2),
      );
      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(1));
      expect(events.single, isA<RepositoryEventCreate<BlockIntent>>());
      expect(events.single.id, 'user-blocked');
      await sub.cancel();
    });
  });
}

class FakeBlockRepository implements BlockRepository {
  ({String objectId, int cascadeMode})? lastBlock;

  final _controller = StreamController<RepositoryEvent<BlockIntent>>.broadcast();

  @override
  Stream<RepositoryEvent<BlockIntent>> get changes => _controller.stream;

  @override
  Future<void> block({
    required String objectId,
    required int cascadeMode,
  }) async {
    lastBlock = (objectId: objectId, cascadeMode: cascadeMode);
    _controller.add(
      RepositoryEventCreate(BlockIntent(blocked: Profile(id: objectId))),
    );
  }

  @override
  Future<void> dispose() => _controller.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
