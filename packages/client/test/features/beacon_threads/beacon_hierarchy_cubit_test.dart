import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_capabilities.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_child_group.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_owner_summary.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_page.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_summary.dart';
import 'package:tentura_root/domain/entity/beacon_parent_reference.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/domain/port/beacon_write_port.dart';
import 'package:tentura/domain/use_case/beacon_create_case.dart';
import 'package:tentura/domain/use_case/beacon_hierarchy_case.dart';
import 'package:tentura/features/beacon/domain/beacon_hierarchy_exception.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/beacon_hierarchy_cubit.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import '../../domain/use_case/fake_beacon_hierarchy_ports.dart';

class _NoopBeaconWritePort implements BeaconWritePort {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoopImageRepo implements ImageRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

BeaconHierarchyCubit _cubit(FakeBeaconHierarchyRepositoryPort port) {
  final cubit = BeaconHierarchyCubit(
    beaconId: 'parent-1',
    hierarchyCase: buildBeaconHierarchyCaseForTest(
      port,
      createCase: BeaconCreateCase(_NoopBeaconWritePort(), _NoopImageRepo()),
      beacons: _NoopBeaconWritePort(),
      commandStore: InMemoryBeaconChildCommandStore(),
    ),
  );
  return cubit;
}

BeaconHierarchySummary _summary({
  String id = 'child-1',
  String title = 'Child title',
  BeaconStatus status = BeaconStatus.open,
  bool tombstone = false,
}) =>
    BeaconHierarchySummary(
      beaconId: id,
      title: title,
      status: status,
      publishedAt: DateTime.utc(2026, 1, 1),
      isTombstone: tombstone,
      owner: const BeaconHierarchyOwnerSummary(
        id: 'owner-1',
        displayName: 'Owner',
      ),
    );

void main() {
  group('BeaconHierarchyCubit', () {
    test('non-admitted viewer does not load child groups', () async {
      final port = FakeBeaconHierarchyRepositoryPort(
        capabilities: const BeaconHierarchyCapabilities(
          canListChildren: false,
          canCreateChild: false,
        ),
      );
      final cubit = _cubit(port);
      addTearDown(cubit.close);

      await cubit.load();

      expect(cubit.state.canListChildren, isFalse);
      expect(cubit.state.active.items, isEmpty);
      expect(cubit.state.finished.items, isEmpty);
      expect(port.childrenByGroup, isEmpty);
    });

    test('terminal parent can list but not create', () async {
      final port = FakeBeaconHierarchyRepositoryPort(
        capabilities: const BeaconHierarchyCapabilities(
          canListChildren: true,
          canCreateChild: false,
        ),
        childrenByGroup: {
          BeaconHierarchyChildGroup.active: BeaconHierarchyPage(
            summaries: [_summary()],
          ),
        },
      );
      final cubit = _cubit(port);
      addTearDown(cubit.close);

      await cubit.load();

      expect(cubit.state.canCreateChild, isFalse);
      expect(cubit.state.active.items, hasLength(1));
    });

    test('empty eligible parent has no child rows', () async {
      final cubit = _cubit(FakeBeaconHierarchyRepositoryPort());
      addTearDown(cubit.close);

      await cubit.load();

      expect(cubit.state.canCreateChild, isTrue);
      expect(cubit.state.active.items, isEmpty);
      expect(cubit.state.finished.items, isEmpty);
    });

    test('active group error does not clear finished group', () async {
      final port = FakeBeaconHierarchyRepositoryPort(
        fetchChildrenHandler: ({required group, after}) async {
          if (group == BeaconHierarchyChildGroup.active) {
            throw const BeaconHierarchyCursorInvalidException();
          }
          return BeaconHierarchyPage(
            summaries: [_summary(id: 'finished-1', title: 'Done')],
          );
        },
      );
      final cubit = _cubit(port);
      addTearDown(cubit.close);

      await cubit.load();

      expect(cubit.state.active.error, isNotNull);
      expect(cubit.state.finished.items.single.beaconId, 'finished-1');
    });

    test('pagination appends active children', () async {
      final port = FakeBeaconHierarchyRepositoryPort(
        fetchChildrenHandler: ({required group, after}) async {
          if (group != BeaconHierarchyChildGroup.active) {
            return const BeaconHierarchyPage(summaries: []);
          }
          if (after == null) {
            return BeaconHierarchyPage(
              summaries: [_summary(id: 'child-a', title: 'A')],
              nextCursor: 'page-2',
            );
          }
          return BeaconHierarchyPage(
            summaries: [_summary(id: 'child-b', title: 'B')],
          );
        },
      );
      final cubit = _cubit(port);
      addTearDown(cubit.close);

      await cubit.load();
      expect(cubit.state.active.items, hasLength(1));
      expect(cubit.state.active.hasMore, isTrue);

      await cubit.loadMore(BeaconHierarchyChildGroup.active);
      expect(cubit.state.active.items, hasLength(2));
      expect(cubit.state.active.hasMore, isFalse);
    });

    test('deleted tombstones are listed when expanded', () async {
      final port = FakeBeaconHierarchyRepositoryPort(
        childrenByGroup: {
          BeaconHierarchyChildGroup.deleted: BeaconHierarchyPage(
            summaries: [_summary(id: 'gone', tombstone: true)],
          ),
        },
      );
      final cubit = _cubit(port);
      addTearDown(cubit.close);

      await cubit.load();
      expect(cubit.state.deleted.items, isEmpty);

      cubit.setDeletedExpanded(true);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(cubit.state.deleted.expanded, isTrue);
      expect(cubit.state.deleted.items.single.isTombstone, isTrue);
    });

    test('parent reference states', () async {
      for (final reference in [
        const BeaconParentReference(state: BeaconParentReferenceState.none),
        const BeaconParentReference(
          state: BeaconParentReferenceState.available,
          beaconId: 'parent-1',
          title: 'Parent title',
        ),
        const BeaconParentReference(
          state: BeaconParentReferenceState.unavailable,
        ),
      ]) {
        final cubit = _cubit(
          FakeBeaconHierarchyRepositoryPort(parentReference: reference),
        );
        addTearDown(cubit.close);
        await cubit.loadParentReference();
        expect(cubit.state.parentReference, reference);
      }
    });

    test('evictHierarchyAccess resets visible hierarchy state', () async {
      final cubit = _cubit(
        FakeBeaconHierarchyRepositoryPort(
          childrenByGroup: {
            BeaconHierarchyChildGroup.active: BeaconHierarchyPage(
              summaries: [_summary()],
            ),
          },
        ),
      );
      addTearDown(cubit.close);

      await cubit.load();
      expect(cubit.state.active.items, isNotEmpty);

      cubit.evictHierarchyAccess();
      expect(cubit.state.canListChildren, isFalse);
      expect(cubit.state.active.items, isEmpty);
      expect(cubit.state.status, isA<StateIsSuccess>());
    });

    test('capabilities error is surfaced without throwing', () async {
      final cubit = _cubit(
        FakeBeaconHierarchyRepositoryPort(
          capabilitiesError: StateError('offline'),
        ),
      );
      addTearDown(cubit.close);

      await cubit.load();

      expect(cubit.state.capabilitiesError, isNotNull);
      expect(cubit.state.hasCapabilities, isFalse);
    });
  });
}
