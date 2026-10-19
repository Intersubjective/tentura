import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/my_work/domain/port/my_work_sort_preference_port.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_cubit.dart';

import 'my_work_test_support.dart';

/// In-memory stand-in for the per-device sort preference (#431).
class _FakeSortPreference implements MyWorkSortPreferencePort {
  _FakeSortPreference({this.stored, this.pendingRead});

  MyWorkSort? stored;

  final Completer<MyWorkSort?>? pendingRead;

  final writes = <MyWorkSort>[];

  int reads = 0;

  @override
  Future<MyWorkSort?> getSort() {
    reads++;
    return pendingRead?.future ?? Future.value(stored);
  }

  @override
  Future<void> setSort(MyWorkSort sort) async {
    writes.add(sort);
    stored = sort;
  }
}

void main() {
  group('My Work sort order persists per device (#431)', () {
    test('a new cubit starts on the order saved on this device', () async {
      final prefs = _FakeSortPreference(stored: MyWorkSort.oldest);
      final cubit = MyWorkCubit(
        userId: 'user-1',
        myWorkCase: buildTestMyWorkCase(),
        sortPreference: prefs,
      );
      await cubit.stream.firstWhere((s) => s.isSuccess);
      await pumpEventQueue();

      expect(prefs.reads, 1);
      expect(cubit.state.sort, MyWorkSort.oldest);
      // Restoring is a read, not a choice: nothing is written back.
      expect(prefs.writes, isEmpty);

      await cubit.close();
    });

    test('nothing saved keeps the default newest-first order', () async {
      final prefs = _FakeSortPreference();
      final cubit = MyWorkCubit(
        userId: 'user-1',
        myWorkCase: buildTestMyWorkCase(),
        sortPreference: prefs,
      );
      await cubit.stream.firstWhere((s) => s.isSuccess);
      await pumpEventQueue();

      expect(cubit.state.sort, MyWorkSort.recent);
      expect(prefs.writes, isEmpty);

      await cubit.close();
    });

    test('choosing an order saves it, and a reload comes back to it', () async {
      final prefs = _FakeSortPreference();
      final first = MyWorkCubit(
        userId: 'user-1',
        myWorkCase: buildTestMyWorkCase(),
        sortPreference: prefs,
      );
      await first.stream.firstWhere((s) => s.isSuccess);
      await pumpEventQueue();

      first.setSort(MyWorkSort.alphabetical);
      await pumpEventQueue();
      expect(prefs.writes, [MyWorkSort.alphabetical]);

      // Choosing the order already shown is not a new choice.
      first.setSort(MyWorkSort.alphabetical);
      await pumpEventQueue();
      expect(prefs.writes, [MyWorkSort.alphabetical]);
      await first.close();

      // Same device, next session (a page reload builds a new cubit).
      final second = MyWorkCubit(
        userId: 'user-1',
        myWorkCase: buildTestMyWorkCase(),
        sortPreference: prefs,
      );
      await second.stream.firstWhere((s) => s.isSuccess);
      await pumpEventQueue();
      expect(second.state.sort, MyWorkSort.alphabetical);

      await second.close();
    });

    test(
      'going back to newest first is saved too (tab reselect), '
      'so a reload shows newest first',
      () async {
        final prefs = _FakeSortPreference();
        final first = MyWorkCubit(
          userId: 'user-1',
          myWorkCase: buildTestMyWorkCase(),
          sortPreference: prefs,
        );
        await first.stream.firstWhere((s) => s.isSuccess);
        await pumpEventQueue();

        first.setSort(MyWorkSort.oldest);
        await pumpEventQueue();
        // Reselecting the My Work tab resets the order to the default
        // (my_work_screen.dart: `..setSort(MyWorkSort.recent)`).
        first.setSort(MyWorkSort.recent);
        await pumpEventQueue();

        // The reset to the default is a choice like any other: it is saved,
        // not skipped as "already the default".
        expect(prefs.writes, [MyWorkSort.oldest, MyWorkSort.recent]);
        await first.close();

        final second = MyWorkCubit(
          userId: 'user-1',
          myWorkCase: buildTestMyWorkCase(),
          sortPreference: prefs,
        );
        await second.stream.firstWhere((s) => s.isSuccess);
        await pumpEventQueue();
        expect(second.state.sort, MyWorkSort.recent);

        await second.close();
      },
    );

    test(
      'a choice made before the saved order is read is not overwritten',
      () async {
        final read = Completer<MyWorkSort?>();
        final prefs = _FakeSortPreference(pendingRead: read);
        final cubit = MyWorkCubit(
          userId: 'user-1',
          myWorkCase: buildTestMyWorkCase(),
          sortPreference: prefs,
        );
        await cubit.stream.firstWhere((s) => s.isSuccess);

        cubit.setSort(MyWorkSort.alphabetical);
        read.complete(MyWorkSort.oldest);
        await pumpEventQueue();

        expect(cubit.state.sort, MyWorkSort.alphabetical);
        expect(prefs.writes.last, MyWorkSort.alphabetical);

        await cubit.close();
      },
    );

    test('a saved order that arrives after close does not emit', () async {
      final read = Completer<MyWorkSort?>();
      final prefs = _FakeSortPreference(pendingRead: read);
      final cubit = MyWorkCubit(
        userId: 'user-1',
        myWorkCase: buildTestMyWorkCase(),
        sortPreference: prefs,
      );
      await cubit.stream.firstWhere((s) => s.isSuccess);
      await cubit.close();

      read.complete(MyWorkSort.oldest);
      // An emit after close throws a StateError, which fails this test.
      await pumpEventQueue();
      expect(cubit.isClosed, isTrue);
    });
  });
}
