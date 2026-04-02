import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_state.dart';
import 'package:tentura/ui/bloc/state_base.dart';

Beacon _beacon(String id, BeaconLifecycle lifecycle) => Beacon(
      createdAt: DateTime(2024),
      updatedAt: DateTime(2024),
      id: id,
      lifecycle: lifecycle,
    );

void main() {
  test('visibleBeaconsForSection dedupes All filter by beacon id', () {
    final shared = _beacon('same', BeaconLifecycle.open);
    final s = MyWorkState(
      authoredActive: [shared],
      committedActive: [_beacon('same', BeaconLifecycle.open)],
      filter: MyWorkFilter.all,
      status: const StateIsSuccess(),
    );
    expect(s.visibleBeaconsForSection(MyWorkSection.active).length, 1);
    expect(s.countForSection(MyWorkSection.active), 1);
  });

  test('visibleBeaconsForSection Authored ignores committed list', () {
    final s = MyWorkState(
      authoredActive: [_beacon('a', BeaconLifecycle.open)],
      committedActive: [_beacon('b', BeaconLifecycle.open)],
      filter: MyWorkFilter.authored,
      status: const StateIsSuccess(),
    );
    expect(s.visibleBeaconsForSection(MyWorkSection.active).length, 1);
    expect(s.countForSection(MyWorkSection.active), 1);
  });

  test('closed count uses id hints with dedupe until closedDataFetched', () {
    final s = MyWorkState(
      authoredClosedIdHints: const ['a', 'b'],
      committedClosedIdHints: const ['b', 'c'],
      closedDataFetched: false,
      filter: MyWorkFilter.all,
      status: const StateIsSuccess(),
    );
    expect(s.countForSection(MyWorkSection.closed), 3);
  });

  test('closed count hints respect Authored and Committed filters', () {
    final base = MyWorkState(
      authoredClosedIdHints: const ['a', 'b'],
      committedClosedIdHints: const ['b', 'c'],
      closedDataFetched: false,
      status: const StateIsSuccess(),
    );
    expect(
      base.copyWith(filter: MyWorkFilter.authored).countForSection(
            MyWorkSection.closed,
          ),
      2,
    );
    expect(
      base.copyWith(filter: MyWorkFilter.committed).countForSection(
            MyWorkSection.closed,
          ),
      2,
    );
  });

  test('countForSection closed uses lists after closedDataFetched', () {
    final s = MyWorkState(
      authoredClosed: [_beacon('x', BeaconLifecycle.closed)],
      committedClosed: [_beacon('x', BeaconLifecycle.closed)],
      authoredClosedIdHints: const ['x'],
      committedClosedIdHints: const ['x'],
      closedDataFetched: true,
      filter: MyWorkFilter.all,
      status: const StateIsSuccess(),
    );
    expect(s.countForSection(MyWorkSection.closed), 1);
  });
}
