import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_state.dart';

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
    );
    expect(s.visibleBeaconsForSection(MyWorkSection.active).length, 1);
    expect(s.countForSection(MyWorkSection.active), 1);
  });

  test('visibleBeaconsForSection Authored ignores committed list', () {
    final s = MyWorkState(
      authoredActive: [_beacon('a', BeaconLifecycle.open)],
      committedActive: [_beacon('b', BeaconLifecycle.open)],
      filter: MyWorkFilter.authored,
    );
    expect(s.visibleBeaconsForSection(MyWorkSection.active).length, 1);
    expect(s.countForSection(MyWorkSection.active), 1);
  });

  test('closed count uses id hints with dedupe until closedDataFetched', () {
    const s = MyWorkState(
      authoredClosedIdHints: ['a', 'b'],
      committedClosedIdHints: ['b', 'c'],
    );
    expect(s.countForSection(MyWorkSection.closed), 3);
  });

  test('closed count hints respect Authored and Committed filters', () {
    const base = MyWorkState(
      authoredClosedIdHints: ['a', 'b'],
      committedClosedIdHints: ['b', 'c'],
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
    );
    expect(s.countForSection(MyWorkSection.closed), 1);
  });

  test(
      'visibleBeacons on Drafts tab merges All even when filter is Committed',
      () {
    final authored = _beacon('a', BeaconLifecycle.draft);
    final committedOnly = _beacon('b', BeaconLifecycle.draft);
    final s = MyWorkState(
      section: MyWorkSection.drafts,
      filter: MyWorkFilter.committed,
      authoredDrafts: [authored],
      committedDrafts: [committedOnly],
    );
    expect(s.visibleBeacons.map((e) => e.id).toList(), ['a', 'b']);
  });

  test(
      'countForSection drafts respects filter when not on Drafts; '
      'uses All when on Drafts tab',
      () {
    final authored = _beacon('a', BeaconLifecycle.draft);
    final committedOnly = _beacon('b', BeaconLifecycle.draft);
    final onActive = MyWorkState(
      filter: MyWorkFilter.committed,
      authoredDrafts: [authored],
      committedDrafts: [committedOnly],
    );
    expect(onActive.countForSection(MyWorkSection.drafts), 1);

    final onDrafts = onActive.copyWith(section: MyWorkSection.drafts);
    expect(onDrafts.countForSection(MyWorkSection.drafts), 2);
  });

  test('tileIsMine on Drafts is false for committed-only draft', () {
    final committedOnly = _beacon('b', BeaconLifecycle.draft);
    final s = MyWorkState(
      section: MyWorkSection.drafts,
      committedDrafts: [committedOnly],
    );
    expect(s.tileIsMine(committedOnly), isFalse);
  });
}
