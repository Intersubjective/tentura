import 'dart:async';

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
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/features/beacon/domain/beacon_hierarchy_exception.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/beacon_hierarchy_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/beacon_hierarchy_state.dart';

import '../../domain/use_case/fake_beacon_hierarchy_ports.dart';
import '../../support/test_realtime_sync.dart';

class _NoopBeaconWritePort implements BeaconWritePort {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoopImageRepo implements ImageRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

BeaconHierarchyCubit _cubit(
  FakeBeaconHierarchyRepositoryPort port,
  TestRealtimeSyncPort realtime,
) {
  final cubit = BeaconHierarchyCubit(
    beaconId: 'parent-1',
    hierarchyCase: buildBeaconHierarchyCaseForTest(
      port,
      createCase: BeaconCreateCase(_NoopBeaconWritePort(), _NoopImageRepo()),
      beacons: _NoopBeaconWritePort(),
      commandStore: InMemoryBeaconChildCommandStore(),
      realtimeSyncCase: RealtimeSyncCase(realtime),
    ),
  );
  return cubit;
}

BeaconHierarchySummary _summary({
  String id = 'child-1',
  String title = 'Child title',
  BeaconStatus status = BeaconStatus.open,
  bool tombstone = false,
}) => BeaconHierarchySummary(
  beaconId: id,
  title: title,
  status: status,
  publishedAt: DateTime.utc(2026),
  isTombstone: tombstone,
  owner: const BeaconHierarchyOwnerSummary(
    id: 'owner-1',
    displayName: 'Owner',
  ),
);

class _RefreshableHierarchyPort extends FakeBeaconHierarchyRepositoryPort {
  _RefreshableHierarchyPort()
    : super(
        parentReference: const BeaconParentReference(
          state: BeaconParentReferenceState.available,
          beaconId: 'ancestor-1',
          title: 'Ancestor',
        ),
        childrenByGroup: {
          for (final group in BeaconHierarchyChildGroup.values)
            group: BeaconHierarchyPage(
              summaries: [_summary(id: 'child-${group.name}')],
              nextCursor: 'next-${group.name}',
            ),
        },
      );

  bool accessDenied = false;
  Exception? parentReferenceError;
  int parentReferenceCalls = 0;

  @override
  Future<BeaconHierarchyCapabilities> fetchCapabilities({
    required String beaconId,
  }) async {
    return accessDenied
        ? const BeaconHierarchyCapabilities(
            canListChildren: false,
            canCreateChild: false,
          )
        : capabilities;
  }

  @override
  Future<BeaconParentReference> fetchParentReference({
    required String beaconId,
  }) async {
    parentReferenceCalls++;
    final error = parentReferenceError;
    if (error != null) throw error;
    return parentReference;
  }
}

void main() {
  group('Loaded hierarchy survives recoverable silent refresh failures', () {
    for (final failureSite in ['child list', 'parent reference']) {
      testWidgets(
        '$failureSite failure preserves capabilities and children while access loss evicts them',
        (tester) async {
          final realtime = TestRealtimeSyncPort();
          final port = _RefreshableHierarchyPort();
          final cubit = _cubit(port, realtime);
          addTearDown(() async {
            await cubit.close();
            await realtime.dispose();
          });

          await cubit.load();
          await cubit.loadParentReference();
          expect(cubit.state.canListChildren, isTrue);
          for (final group in BeaconHierarchyChildGroup.values) {
            expect(cubit.state.sliceFor(group).items, hasLength(1));
          }

          // A definitive denial must still remove the cached hierarchy.
          port.accessDenied = true;
          realtime.emitCatchUp();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 150));
          expect(cubit.state.canListChildren, isFalse);
          expect(cubit.state.hasCapabilities, isFalse);
          expect(cubit.state.canCreateChild, isFalse);
          expect(cubit.state.parentReference, isNull);
          for (final group in BeaconHierarchyChildGroup.values) {
            expect(cubit.state.sliceFor(group).items, isEmpty);
            expect(cubit.state.sliceFor(group).nextCursor, isNull);
          }

          // Restore access before exercising temporary failures.
          port.accessDenied = false;
          await cubit.load();
          await cubit.loadParentReference();
          cubit.setDeletedExpanded(true);
          final loaded = cubit.state;
          expect(loaded.canListChildren, isTrue);
          expect(loaded.canCreateChild, isTrue);
          expect(loaded.parentReference, port.parentReference);

          // Cover both a plain transport timeout and a recoverable typed
          // hierarchy error. Cursor rejection is not an authorization denial.
          for (final transientFailure in <Exception>[
            TimeoutException('Hierarchy refresh timed out'),
            const BeaconHierarchyCursorInvalidException(),
          ]) {
            final parentReferenceCalls = port.parentReferenceCalls;
            var failedRequests = 0;
            if (failureSite == 'child list') {
              port.fetchChildrenHandler = ({required group, after}) async {
                if (group == BeaconHierarchyChildGroup.active) {
                  failedRequests++;
                  throw transientFailure;
                }
                return port.childrenByGroup[group]!;
              };
            } else {
              port.parentReferenceError = transientFailure;
            }

            final emitted = <BeaconHierarchyState>[];
            final subscription = cubit.stream.listen(emitted.add);
            addTearDown(subscription.cancel);
            realtime.emitCatchUp();
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 150));

            if (failureSite == 'child list') {
              expect(failedRequests, 1);
            } else {
              expect(port.parentReferenceCalls, parentReferenceCalls + 1);
            }
            expect(cubit.state.capabilities, loaded.capabilities);
            expect(cubit.state.canListChildren, isTrue);
            expect(cubit.state.canCreateChild, isTrue);
            expect(cubit.state.active, loaded.active);
            expect(cubit.state.finished, loaded.finished);
            expect(cubit.state.deleted, loaded.deleted);
            expect(cubit.state.parentReference, loaded.parentReference);
            for (final state in emitted) {
              expect(state.capabilities, loaded.capabilities);
              expect(state.active.items, loaded.active.items);
              expect(state.finished.items, loaded.finished.items);
              expect(state.deleted.items, loaded.deleted.items);
              expect(state.parentReference, loaded.parentReference);
            }

            // Verify the configured failure is temporary: another catch-up
            // succeeds with the same permissions and restores the same snapshot.
            port
              ..fetchChildrenHandler = null
              ..parentReferenceError = null;
            realtime.emitCatchUp();
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 150));
            expect(cubit.state, loaded);
          }
        },
      );
    }
  });
}
