import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_cubit.dart';

import 'my_work_test_support.dart';

void main() {
  test(
    'fetch emits success with init cards and active default filter',
    () async {
      final cubit = MyWorkCubit(
        userId: 'user-1',
        myWorkCase: buildTestMyWorkCase(),
      );

      await cubit.stream.firstWhere((s) => s.isSuccess);
      expect(cubit.state.nonArchivedCards, isEmpty);
      expect(cubit.state.status, isA<StateIsSuccess>());
      expect(cubit.state.filter, MyWorkFilter.active);

      await cubit.close();
    },
  );

  test('archived filter triggers lazy closed load', () async {
    final cubit = MyWorkCubit(
      userId: 'user-1',
      myWorkCase: buildTestMyWorkCase(),
    );
    await cubit.stream.firstWhere((s) => s.isSuccess);

    cubit.setFilter(MyWorkFilter.archived);
    await cubit.stream.firstWhere(
      (s) => s.archivedDataFetched && s.isSuccess,
    );
    expect(cubit.state.filter, MyWorkFilter.archived);

    await cubit.close();
  });

    test('fetch error sets loadError', () async {
    final repo = FakeMyWorkRepository()..fetchInitError = Exception('boom');
    final cubit = MyWorkCubit(
      userId: 'user-1',
      myWorkCase: buildTestMyWorkCase(repo: repo),
    );

    await cubit.stream.firstWhere((s) => s.hasError);
    expect(cubit.state.loadError, isNotNull);

    await cubit.close();
  });

  test('background fetch failure keeps visible cards', () async {
    final repo = FakeMyWorkRepository()
      ..initResult = (
        authoredNonArchived: [
          Beacon.empty.copyWith(id: 'b1'),
        ],
        helpOfferedNonArchived: const [],
        obligationBeacons: const [],
        archivedCountHint: 0,
      );
    final cubit = MyWorkCubit(
      userId: 'user-1',
      myWorkCase: buildTestMyWorkCase(repo: repo),
    );
    await cubit.stream.firstWhere((s) => s.isSuccess);
    expect(cubit.state.nonArchivedCards, isNotEmpty);

    repo.fetchInitError = Exception('refresh failed');
    await cubit.fetch(showLoading: false);

    expect(cubit.state.hasError, isFalse);
    expect(cubit.state.isSuccess, isTrue);
    expect(cubit.state.nonArchivedCards, isNotEmpty);

    await cubit.close();
  });

  test('tab reselect resets to active filter and recent sort', () async {
    final cubit = MyWorkCubit(
      userId: 'user-1',
      myWorkCase: buildTestMyWorkCase(),
    );
    await cubit.stream.firstWhere((s) => s.isSuccess);

    cubit
      ..setFilter(MyWorkFilter.all)
      ..setSort(MyWorkSort.alphabetical);
    expect(cubit.state.filter, MyWorkFilter.all);
    expect(cubit.state.sort, MyWorkSort.alphabetical);

    cubit
      ..setFilter(MyWorkFilter.active)
      ..setSort(MyWorkSort.recent);
    expect(cubit.state.filter, MyWorkFilter.active);
    expect(cubit.state.sort, MyWorkSort.recent);

    await cubit.close();
  });

}
