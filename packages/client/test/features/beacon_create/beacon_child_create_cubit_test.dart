import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_child_command_outcome.dart';
import 'package:tentura_root/domain/entity/beacon_creation_context.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/use_case/beacon_create_case.dart';
import 'package:tentura/domain/use_case/beacon_hierarchy_case.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/beacon/domain/beacon_hierarchy_exception.dart';
import 'package:tentura/features/beacon/domain/port/beacon_hierarchy_repository_port.dart';
import 'package:tentura/ui/effect/ui_effect.dart';

import '../../domain/use_case/fake_beacon_hierarchy_ports.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import 'fake_beacon_ports.dart';

const _parentId = 'parent-1';
const _childContext = BeaconCreationContextChild(parentBeaconId: _parentId);

BeaconCreateCubit _childCubit({
  required FakeBeaconWritePort write,
  required FakeBeaconHierarchyRepositoryPort hierarchy,
  InMemoryBeaconChildCommandStore? store,
  FakeUiEffectPort? effects,
}) {
  final commandStore = store ?? InMemoryBeaconChildCommandStore();
  return BeaconCreateCubit(
    beaconCreateCase: BeaconCreateCase(write, FakeBeaconImagePort()),
    hierarchyCase: buildBeaconHierarchyCaseForTest(
      hierarchy,
      createCase: BeaconCreateCase(write, FakeBeaconImagePort()),
      beacons: write,
      commandStore: commandStore,
    ),
    childCreationContext: _childContext,
    effects: effects ?? FakeUiEffectPort(),
  );
}

BeaconCreateCubit _standaloneCubit({
  required FakeBeaconWritePort write,
  FakeUiEffectPort? effects,
}) => BeaconCreateCubit(
  beaconCreateCase: BeaconCreateCase(write, FakeBeaconImagePort()),
  hierarchyCase: buildBeaconHierarchyCaseForTest(
    FakeBeaconHierarchyRepositoryPort(),
    createCase: BeaconCreateCase(write, FakeBeaconImagePort()),
    beacons: write,
    commandStore: InMemoryBeaconChildCommandStore(),
  ),
  effects: effects ?? FakeUiEffectPort(),
);

void _fillRequired(BeaconCreateCubit cubit) {
  cubit
    ..setTitle('Need help moving')
    ..setDescription('Two flights of stairs.');
}

void main() {
  group('child creation cubit', () {
    test('init seeds clientCommandId for a new child composer', () async {
      final cubit = _childCubit(
        write: FakeBeaconWritePort(),
        hierarchy: FakeBeaconHierarchyRepositoryPort(),
      );
      addTearDown(cubit.close);

      await cubit.stream.firstWhere((s) => s.clientCommandId != null);

      expect(cubit.state.clientCommandId, isNotEmpty);
      expect(cubit.state.isChildMode, isTrue);
    });

    test('ensureDraft delegates to hierarchy create and surfaces draft id', () async {
      final write = FakeBeaconWritePort();
      final hierarchy = FakeBeaconHierarchyRepositoryPort();
      final cubit = _childCubit(write: write, hierarchy: hierarchy);
      addTearDown(cubit.close);
      await cubit.stream.firstWhere((s) => s.clientCommandId != null);
      _fillRequired(cubit);

      final id = await cubit.ensureDraft(context: 'ctx', showMessage: false);

      expect(id, isNotEmpty);
      expect(cubit.state.draftId, id);
      expect(cubit.state.clientCommandId, isNull);
      expect(hierarchy.createCalls, isNotEmpty);
    });

    test('promotion conflict surfaces dedicated state without going live', () async {
      final hierarchy = FakeBeaconHierarchyRepositoryPort()
        ..createOutcomeOverride = const BeaconChildCreateOutcome(
          outcome: BeaconChildCommandOutcome.alreadyPromoted,
          beaconId: 'winner-child',
        );
      final effects = FakeUiEffectPort();
      final cubit = _childCubit(
        write: FakeBeaconWritePort(),
        hierarchy: hierarchy,
        effects: effects,
      );
      addTearDown(cubit.close);
      await cubit.stream.firstWhere((s) => s.clientCommandId != null);
      _fillRequired(cubit);

      await cubit.ensureDraft(context: 'ctx', showMessage: false);

      expect(cubit.state.childPromotionConflict, isTrue);
      expect(cubit.state.existingPromotedChildBeaconId, 'winner-child');
      expect(cubit.state.isLive, isFalse);
      expect(effects.emitted.whereType<ShowError>(), isNotEmpty);
    });

    test('denied publication retains draft and surfaces publish failure', () async {
      final write = FakeBeaconWritePort(
        beacon: Beacon.empty.copyWith(id: 'child-draft', status: BeaconStatus.draft),
      )..publishError = const BeaconParentNotCoordinatableException();
      final hierarchy = FakeBeaconHierarchyRepositoryPort()
        ..createOutcomeOverride = const BeaconChildCreateOutcome(
          outcome: BeaconChildCommandOutcome.created,
          beaconId: 'child-draft',
        );
      final effects = FakeUiEffectPort();
      final cubit = _childCubit(
        write: write,
        hierarchy: hierarchy,
        effects: effects,
      );
      addTearDown(cubit.close);
      await cubit.stream.firstWhere((s) => s.clientCommandId != null);
      _fillRequired(cubit);

      await cubit.makeLive(context: 'ctx');

      expect(cubit.state.isLive, isFalse);
      expect(cubit.state.draftId, 'child-draft');
      expect(write.deletedIds, isEmpty);
      expect(effects.emitted.whereType<ShowError>(), isNotEmpty);
    });

    test('restored draft load keeps canonical id without minting command id', () async {
      final write = FakeBeaconWritePort(
        beacon: Beacon.empty.copyWith(
          id: 'restored-draft',
          status: BeaconStatus.draft,
          title: 'Draft',
          description: 'Existing body',
        ),
      );
      final cubit = BeaconCreateCubit(
        beaconCreateCase: BeaconCreateCase(write, FakeBeaconImagePort()),
        hierarchyCase: buildBeaconHierarchyCaseForTest(
          FakeBeaconHierarchyRepositoryPort(),
          createCase: BeaconCreateCase(write, FakeBeaconImagePort()),
          beacons: write,
          commandStore: InMemoryBeaconChildCommandStore(),
        ),
        childCreationContext: _childContext,
        draftBeaconIdToLoad: 'restored-draft',
        effects: FakeUiEffectPort(),
      );
      addTearDown(cubit.close);

      await cubit.stream.firstWhere((s) => s.draftId == 'restored-draft');

      expect(cubit.state.clientCommandId, isNull);
      expect(cubit.state.draftId, 'restored-draft');
    });
  });

  group('normal standalone regression', () {
    test('standalone ensureDraft still uses BeaconCreateCase create path', () async {
      final write = FakeBeaconWritePort(
        beacon: Beacon.empty.copyWith(id: 'standalone-draft', status: BeaconStatus.draft),
      );
      final cubit = _standaloneCubit(write: write);
      addTearDown(cubit.close);
      _fillRequired(cubit);

      final id = await cubit.ensureDraft(context: 'ctx', showMessage: false);

      expect(id, 'standalone-draft');
      expect(write.createdFields, hasLength(1));
      expect(cubit.state.creationContext, isNull);
      expect(cubit.state.clientCommandId, isNull);
    });

    test('standalone makeLive publishes through ordinary publishDraft', () async {
      final write = FakeBeaconWritePort(
        beacon: Beacon.empty.copyWith(id: 'B1', status: BeaconStatus.draft),
      );
      final cubit = _standaloneCubit(write: write);
      addTearDown(cubit.close);
      _fillRequired(cubit);

      await cubit.makeLive(context: 'ctx');

      expect(cubit.state.isLive, isTrue);
      expect(write.publishedIds, ['B1']);
    });
  });
}
