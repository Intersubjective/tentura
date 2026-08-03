import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/block/domain/entity/user_block.dart';
import 'package:tentura/features/block/domain/use_case/block_case.dart';
import 'package:tentura/features/block/ui/bloc/blocked_users_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';

import '../../../../ui/effect/fake_ui_effect_port.dart';

void main() {
  group('BlockedUsersCubit.fetch', () {
    test('emits loading then success', () async {
      final blocks = [BlockIntent(blocked: Profile(id: 'user-blocked'))];
      final case_ = FakeBlockCase()..fetchMyBlocksResult = blocks;
      final effects = FakeUiEffectPort();
      final cubit = BlockedUsersCubit.test(case_: case_, effects: effects);

      final statuses = <StateStatus>[];
      final sub = cubit.stream.listen((state) => statuses.add(state.status));

      final fetchFuture = cubit.fetch();
      expect(cubit.state.status, isA<StateIsLoading>());
      await fetchFuture;

      expect(statuses.first, isA<StateIsLoading>());
      expect(cubit.state.status, isA<StateIsSuccess>());
      expect(cubit.state.blocks, blocks);
      await sub.cancel();
      await cubit.close();
    });

    test('error path emits the error effect', () async {
      final case_ = FakeBlockCase()
        ..fetchMyBlocksError = Exception('fetch failed');
      final effects = FakeUiEffectPort();
      final cubit = BlockedUsersCubit.test(case_: case_, effects: effects);

      await cubit.fetch();

      expect(cubit.state.status, isA<StateIsSuccess>());
      expect(effects.emitted.whereType<ShowError>(), isNotEmpty);
      await cubit.close();
    });
  });
}

class FakeBlockCase implements BlockCase {
  List<BlockIntent> fetchMyBlocksResult = const [];
  Object? fetchMyBlocksError;
  final unblockCalls = <String>[];

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
