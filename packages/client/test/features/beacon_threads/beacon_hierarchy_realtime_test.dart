import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_capabilities.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_child_group.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_page.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_owner_summary.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_summary.dart';
import 'package:tentura_root/domain/entity/beacon_parent_reference.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/port/beacon_write_port.dart';
import 'package:tentura/domain/use_case/beacon_create_case.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/beacon_hierarchy_cubit.dart';

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

class _RecordingHierarchyPort extends FakeBeaconHierarchyRepositoryPort {
  _RecordingHierarchyPort({
    required super.capabilities,
    super.childrenByGroup,
    BeaconParentReference parentReference = const BeaconParentReference(
      state: BeaconParentReferenceState.none,
    ),
  }) : _parentReference = parentReference;

  final BeaconParentReference _parentReference;

  int capabilitiesCalls = 0;
  int childrenCalls = 0;
  int parentReferenceCalls = 0;
  BeaconHierarchyCapabilities? nextCapabilities;
  Completer<BeaconHierarchyCapabilities>? pendingCapabilities;

  @override
  Future<BeaconHierarchyCapabilities> fetchCapabilities({
    required String beaconId,
  }) async {
    capabilitiesCalls++;
    if (pendingCapabilities != null) {
      return pendingCapabilities!.future;
    }
    if (nextCapabilities != null) {
      final value = nextCapabilities!;
      nextCapabilities = null;
      return value;
    }
    return super.fetchCapabilities(beaconId: beaconId);
  }

  @override
  Future<BeaconHierarchyPage> fetchChildren({
    required String parentBeaconId,
    required BeaconHierarchyChildGroup group,
    int first = 20,
    String? after,
  }) async {
    childrenCalls++;
    return super.fetchChildren(
      parentBeaconId: parentBeaconId,
      group: group,
      first: first,
      after: after,
    );
  }

  @override
  Future<BeaconParentReference> fetchParentReference({
    required String beaconId,
  }) async {
    parentReferenceCalls++;
    return _parentReference;
  }
}

void main() {
  group('BeaconHierarchyCubit realtime convergence', () {
    late TestRealtimeSyncPort realtimePort;
    late RealtimeSyncCase realtimeCase;
    late _RecordingHierarchyPort port;

    setUp(() {
      final harness = buildTestRealtimeSync();
      realtimePort = harness.port;
      realtimeCase = harness.case_;
      port = _RecordingHierarchyPort(
        capabilities: const BeaconHierarchyCapabilities(
          canListChildren: true,
          canCreateChild: true,
        ),
        childrenByGroup: {
          BeaconHierarchyChildGroup.active: BeaconHierarchyPage(
            summaries: [
              BeaconHierarchySummary(
                beaconId: 'child-1',
                title: 'Child',
                status: BeaconStatus.open,
                publishedAt: DateTime.utc(2026, 1, 1),
                isTombstone: false,
                owner: const BeaconHierarchyOwnerSummary(
                  id: 'owner-1',
                  displayName: 'Owner',
                ),
              ),
            ],
          ),
        },
      );
    });

    tearDown(() async {
      await realtimePort.dispose();
    });

    BeaconHierarchyCubit buildCubit() => BeaconHierarchyCubit(
      beaconId: 'parent-1',
      hierarchyCase: buildBeaconHierarchyCaseForTest(
        port,
        createCase: BeaconCreateCase(_NoopBeaconWritePort(), _NoopImageRepo()),
        beacons: _NoopBeaconWritePort(),
        commandStore: InMemoryBeaconChildCommandStore(),
        realtimeSyncCase: realtimeCase,
      ),
    );

    Future<void> waitFor(bool Function() condition) async {
      final deadline = DateTime.now().add(const Duration(seconds: 2));
      while (DateTime.now().isBefore(deadline)) {
        if (condition()) return;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      fail('Timed out waiting for hierarchy convergence.');
    }

    test('matching hierarchy hint silently refreshes children', () async {
      final cubit = buildCubit();
      addTearDown(cubit.close);
      await cubit.load();
      expect(port.capabilitiesCalls, 1);
      expect(port.childrenCalls, greaterThanOrEqualTo(1));
      final initialChildrenCalls = port.childrenCalls;

      realtimePort.emitChange(
        const RealtimeEntityChange(
          kind: RealtimeEntityKind.beaconHierarchy,
          aggregateId: 'parent-2',
          operation: RealtimeOperation.update,
          source: RealtimeChangeSource.serverInvalidation,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(port.capabilitiesCalls, 1);

      realtimePort.emitChange(
        const RealtimeEntityChange(
          kind: RealtimeEntityKind.beaconHierarchy,
          aggregateId: 'parent-1',
          operation: RealtimeOperation.update,
          source: RealtimeChangeSource.serverInvalidation,
        ),
      );
      await waitFor(() => port.capabilitiesCalls >= 2);
      expect(port.childrenCalls, greaterThan(initialChildrenCalls));
    });

    test('coalesces burst hints into one silent refresh', () async {
      final cubit = buildCubit();
      addTearDown(cubit.close);
      await cubit.load();
      final baseline = port.capabilitiesCalls;

      for (var i = 0; i < 5; i++) {
        realtimePort.emitChange(
          RealtimeEntityChange(
            kind: RealtimeEntityKind.beaconHierarchy,
            aggregateId: 'parent-1',
            operation: RealtimeOperation.update,
            source: RealtimeChangeSource.serverInvalidation,
          ),
        );
      }
      await waitFor(() => port.capabilitiesCalls == baseline + 1);
    });

    test('catch-up refreshes active hierarchy projections', () async {
      final cubit = buildCubit();
      addTearDown(cubit.close);
      await cubit.load();
      final baseline = port.capabilitiesCalls;

      realtimePort.emitCatchUp();
      await waitFor(() => port.capabilitiesCalls == baseline + 1);
    });

    test('one in-flight refresh plus one queued rerun', () async {
      port.pendingCapabilities = Completer<BeaconHierarchyCapabilities>();
      final cubit = buildCubit();
      addTearDown(cubit.close);

      final firstLoad = cubit.load();
      realtimePort.emitChange(
        const RealtimeEntityChange(
          kind: RealtimeEntityKind.beaconHierarchy,
          aggregateId: 'parent-1',
          operation: RealtimeOperation.update,
          source: RealtimeChangeSource.serverInvalidation,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(port.capabilitiesCalls, 1);

      port.pendingCapabilities!.complete(
        const BeaconHierarchyCapabilities(
          canListChildren: true,
          canCreateChild: true,
        ),
      );
      port.pendingCapabilities = null;
      await firstLoad;
      await waitFor(() => port.capabilitiesCalls == 2);
    });

    test('authoritative access loss evicts cached hierarchy state', () async {
      final cubit = buildCubit();
      addTearDown(cubit.close);
      await cubit.load();
      expect(cubit.state.active.items, isNotEmpty);

      port.nextCapabilities = const BeaconHierarchyCapabilities(
        canListChildren: false,
        canCreateChild: false,
      );
      realtimePort.emitChange(
        const RealtimeEntityChange(
          kind: RealtimeEntityKind.beaconHierarchy,
          aggregateId: 'parent-1',
          operation: RealtimeOperation.update,
          source: RealtimeChangeSource.serverInvalidation,
        ),
      );
      await waitFor(() => cubit.state.active.items.isEmpty);
      expect(cubit.state.canListChildren, isFalse);
    });

    test('parent reference refresh follows catch-up when loaded', () async {
      port = _RecordingHierarchyPort(
        capabilities: const BeaconHierarchyCapabilities(
          canListChildren: true,
          canCreateChild: true,
        ),
        parentReference: const BeaconParentReference(
          state: BeaconParentReferenceState.available,
          beaconId: 'parent-0',
          title: 'Parent',
        ),
      );
      final cubit = buildCubit();
      addTearDown(cubit.close);
      await cubit.loadParentReference();
      expect(port.parentReferenceCalls, 1);

      realtimePort.emitCatchUp();
      await waitFor(() => port.parentReferenceCalls >= 2);
    });
  });
}
