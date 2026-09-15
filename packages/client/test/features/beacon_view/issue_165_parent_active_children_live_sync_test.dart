import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_creation_context.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_capabilities.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_child_group.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_owner_summary.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_page.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_summary.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/use_case/beacon_create_case.dart';
import 'package:tentura/domain/use_case/beacon_hierarchy_case.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/beacon_hierarchy_cubit.dart';

import '../../domain/use_case/fake_beacon_hierarchy_ports.dart';
import '../../features/beacon_create/fake_beacon_ports.dart';
import '../../support/test_realtime_sync.dart';

class _MutableChildrenPort extends FakeBeaconHierarchyRepositoryPort {
  _MutableChildrenPort()
    : super(
        capabilities: const BeaconHierarchyCapabilities(
          canListChildren: true,
          canCreateChild: true,
        ),
        childrenByGroup: {
          BeaconHierarchyChildGroup.active: const BeaconHierarchyPage(
            summaries: [],
          ),
        },
      );

  void setActiveChildren(List<BeaconHierarchySummary> summaries) {
    childrenByGroup[BeaconHierarchyChildGroup.active] = BeaconHierarchyPage(
      summaries: summaries,
    );
  }
}

/// GitHub #165 — parent NOW Active child list must include a newly published
/// child without manual reload (F5).
void main() {
  const parentBeaconId = 'B165parent';
  const creationContext = BeaconCreationContextChild(
    parentBeaconId: parentBeaconId,
  );

  late TestRealtimeSyncPort realtimePort;
  late RealtimeSyncCase realtimeCase;

  setUp(() {
    final harness = buildTestRealtimeSync();
    realtimePort = harness.port;
    realtimeCase = harness.case_;
  });

  tearDown(() async {
    await realtimePort.dispose();
  });

  BeaconHierarchySummary publishedChild({
    required String beaconId,
    String title = 'New child request',
  }) =>
      BeaconHierarchySummary(
        beaconId: beaconId,
        title: title,
        status: BeaconStatus.open,
        publishedAt: DateTime.utc(2026, 9, 15),
        isTombstone: false,
        owner: const BeaconHierarchyOwnerSummary(
          id: 'Uauthor',
          displayName: 'Author',
        ),
      );

  BeaconHierarchyCase buildHierarchyCase(_MutableChildrenPort port) =>
      buildBeaconHierarchyCaseForTest(
        port,
        createCase: BeaconCreateCase(
          FakeBeaconWritePort(),
          FakeBeaconImagePort(),
        ),
        beacons: FakeBeaconWritePort(),
        commandStore: InMemoryBeaconChildCommandStore(),
        realtimeSyncCase: realtimeCase,
      );

  BeaconHierarchyCubit buildParentCubit(BeaconHierarchyCase hierarchyCase) =>
      BeaconHierarchyCubit(
        beaconId: parentBeaconId,
        hierarchyCase: hierarchyCase,
      );

  BeaconChildSaveCommand childCommand({
    required String clientCommandId,
    required String beaconId,
  }) =>
      BeaconChildSaveCommand(
        creationContext: creationContext,
        clientCommandId: clientCommandId,
        saveCommand: BeaconSaveCommand(
          fields: Beacon.empty.copyWith(id: beaconId, title: 'New child request'),
          images: const [],
          coverKey: null,
          coverThumb: null,
          draft: true,
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

  group('Issue #165 parent Active children live sync', () {
    test(
      'matching beacon_hierarchy hint refreshes Active children (regression)',
      () async {
        final port = _MutableChildrenPort();
        final hierarchyCase = buildHierarchyCase(port);
        final cubit = buildParentCubit(hierarchyCase);
        addTearDown(cubit.close);

        await cubit.load();
        expect(cubit.state.active.items, isEmpty);

        port.setActiveChildren([
          publishedChild(beaconId: 'child-regression'),
        ]);
        realtimePort.emitChange(
          const RealtimeEntityChange(
            kind: RealtimeEntityKind.beaconHierarchy,
            aggregateId: parentBeaconId,
            operation: RealtimeOperation.update,
            source: RealtimeChangeSource.serverInvalidation,
          ),
        );
        await waitFor(
          () => cubit.state.active.items.any(
            (row) => row.beaconId == 'child-regression',
          ),
        );
      },
    );

    test(
      'publishChildDraft on parent leaves Active list stale without reload',
      () async {
        final write = FakeBeaconWritePort();
        final port = _MutableChildrenPort();
        final hierarchyCase = buildBeaconHierarchyCaseForTest(
          port,
          createCase: BeaconCreateCase(write, FakeBeaconImagePort()),
          beacons: write,
          commandStore: InMemoryBeaconChildCommandStore(),
          realtimeSyncCase: realtimeCase,
        );
        final cubit = buildParentCubit(hierarchyCase);
        addTearDown(cubit.close);

        await cubit.load();
        expect(cubit.state.active.items, isEmpty);

        final session = await hierarchyCase.openComposer(
          creationContext: creationContext,
        );
        final clientCommandId = session.clientCommandId!;
        final saveResult = await hierarchyCase.saveChildDraft(
          childCommand(
            clientCommandId: clientCommandId,
            beaconId: '',
          ),
        );
        final childId = saveResult.beacon.id;
        expect(childId, isNotEmpty);

        await hierarchyCase.publishChildDraft(
          beaconId: childId,
          command: childCommand(
            clientCommandId: clientCommandId,
            beaconId: childId,
          ),
          images: const [],
          coverKey: null,
          coverThumb: null,
        );

        port.setActiveChildren([
          publishedChild(beaconId: childId, title: 'New child request'),
        ]);

        await Future<void>.delayed(const Duration(milliseconds: 200));

        expect(
          cubit.state.active.items.map((row) => row.beaconId),
          contains(childId),
          reason:
              'Parent NOW Active list should show the published child without F5 '
              '(local publish or server invalidation must refresh BeaconHierarchyCubit)',
        );
      },
    );
  });
}
