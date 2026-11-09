// `ConstellationComposerCubit.fullFormHandoff()`: Post and Request both hand
// off immediately with the current recipient selection — no composer draft
// continuity. Anchoring the result at the drop point is a separate, manual
// step afterward (drag the new node, same as any other beacon on the field)
// — see constellation_cubit.dart's anchorTargetForNode.

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_composer_cubit.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';

import '../../support/fake_app_navigator.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_create/fake_beacon_ports.dart';

const _positions = <String, Offset>{
  'Ua': Offset(10, 0),
  'Ub': Offset(20, 0),
  'Uc': Offset(30, 0),
};

void main() {
  late FakeBeaconWritePort write;
  late FakeUiEffectPort effects;
  late ConstellationComposerCubit composer;
  late List<ForwardCubit> forwards;

  setUp(() {
    write = FakeBeaconWritePort();
    effects = FakeUiEffectPort();
    forwards = [];
    composer = ConstellationComposerCubit(
      positions: _positions,
      eligible: _positions.keys.toSet(),
      createCubitFactory: (kind) => BeaconCreateCubit(
        kind: kind,
        beaconCreateCase: fakeBeaconCreateCase(write: write),
        effects: effects,
      ),
      forwardCubitFactory: (beaconId) {
        final cubit = ForwardCubit(
          beaconId: beaconId,
          embedded: true,
          effects: effects,
          debugSkipInitialLoad: true,
        );
        forwards.add(cubit);
        return cubit;
      },
    );
  });

  tearDown(() async {
    await composer.close();
    for (final f in forwards) {
      await f.close();
    }
  });

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  group('Request hand-off to the full form', () {
    test('is available immediately, before any draft exists', () {
      composer.start(BeaconKind.request, Offset.zero);

      final handoff = composer.fullFormHandoff();

      expect(handoff, isNotNull);
      expect(handoff!.kind, BeaconKind.request);
      expect(handoff.draftId, isNull);
      expect(handoff.recipientIds, {'Ua', 'Ub', 'Uc'});
      expect(handoff.notes, isEmpty);
    });

    test(
      'opens the Request create screen with empty draft id and current '
      'recipients',
      () async {
        composer.start(BeaconKind.request, Offset.zero);
        final navigator = FakeAppNavigator();

        await composer.fullFormHandoff()!.open(navigator);

        // No draftId and no initialNotes: both are empty.
        expect(navigator.intents, [
          const NavIntent('createBeacon', {
            'initialRecipientIds': {'Ua', 'Ub', 'Uc'},
          }),
        ]);
      },
    );

    test('reflects recipient changes made before hand-off', () async {
      composer.start(BeaconKind.request, Offset.zero);
      await composer.toggle('Ub');
      await settle();

      final handoff = composer.fullFormHandoff();

      expect(handoff!.recipientIds, {'Ua', 'Uc'});
    });

    test('carries notes from an existing ForwardCubit when present', () async {
      composer.start(BeaconKind.request, Offset.zero);
      await composer.contentChanged();
      await settle();
      composer.forwardCubit!.setRecipientNote('Ua', 'ты же хотел');

      final handoff = composer.fullFormHandoff();

      expect(handoff, isNotNull);
      expect(handoff!.draftId, 'server-beacon');
      expect(handoff.recipientIds, {'Ua', 'Ub', 'Uc'});
      expect(handoff.notes, {'Ua': 'ты же хотел'});
    });
  });

  group('Post hand-off to the full screen', () {
    test('is available immediately, before any draft exists', () {
      composer.start(BeaconKind.post, Offset.zero);

      final handoff = composer.fullFormHandoff();

      expect(handoff, isNotNull);
      expect(handoff!.draftId, isNull);
      expect(handoff.recipientIds, {'Ua', 'Ub', 'Uc'});
    });

    test('reflects recipient changes made before hand-off', () async {
      composer.start(BeaconKind.post, Offset.zero);
      await composer.toggle('Ub');
      await settle();

      final handoff = composer.fullFormHandoff();

      expect(handoff!.recipientIds, {'Ua', 'Uc'});
    });

    test('opens the Post create screen with the current recipient '
        'selection', () async {
      composer.start(BeaconKind.post, Offset.zero);
      final navigator = FakeAppNavigator();

      await composer.fullFormHandoff()!.open(navigator);

      expect(navigator.intents, [
        const NavIntent('createPost', {
          'initialRecipientIds': {'Ua', 'Ub', 'Uc'},
        }),
      ]);
    });
  });

  group('ForwardCubit initial notes', () {
    test('seeds per-recipient notes for the initially selected ids', () async {
      final forward = ForwardCubit(
        beaconId: 'b',
        embedded: true,
        effects: effects,
        debugSkipInitialLoad: true,
        initialSelectedIds: const {'Ua'},
        initialNotes: const {'Ua': 'ты же хотел'},
      );
      addTearDown(forward.close);

      expect(forward.state.perRecipientNotes, {'Ua': 'ты же хотел'});
    });
  });
}
