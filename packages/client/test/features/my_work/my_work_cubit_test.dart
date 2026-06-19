import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/my_work/domain/entity/my_work_filter.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_cubit.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import 'my_work_test_support.dart';

void main() {
  test('fetch emits success with init cards and active default filter', () async {
    final cubit = MyWorkCubit(
      userId: 'user-1',
      myWorkCase: buildTestMyWorkCase(),
    );

    await cubit.stream.firstWhere((s) => s.isSuccess);
    expect(cubit.state.nonArchivedCards, isEmpty);
    expect(cubit.state.status, isA<StateIsSuccess>());
    expect(cubit.state.filter, MyWorkFilter.active);

    await cubit.close();
  });

  test('archived filter triggers lazy closed load', () async {
    final cubit = MyWorkCubit(
      userId: 'user-1',
      myWorkCase: buildTestMyWorkCase(),
    );
    await cubit.stream.firstWhere((s) => s.isSuccess);

    cubit.setFilter(MyWorkFilter.archived);
    await cubit.stream.firstWhere(
      (s) => s.closedDataFetched && s.isSuccess,
    );
    expect(cubit.state.filter, MyWorkFilter.archived);

    await cubit.close();
  });

  test('fetch error emits StateHasError', () async {
    final repo = FakeMyWorkRepository()..fetchInitError = Exception('boom');
    final cubit = MyWorkCubit(
      userId: 'user-1',
      myWorkCase: buildTestMyWorkCase(repo),
    );

    await cubit.stream.firstWhere((s) => s.hasError);
    expect(cubit.state.status, isA<StateHasError>());

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
