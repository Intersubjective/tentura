// `ConstellationComposerCubit.fullFormHandoff()`: a Request needs its server
// draft to already exist and hands off the same draft id, recipients and
// per-recipient notes; a Post has no draft continuity and hands off
// immediately with just the current recipient selection. Anchoring the
// result at the drop point is a separate, manual step afterward (drag the
// new node, same as any other beacon on the field) — see
// constellation_cubit.dart's anchorTargetForNode.

import 'dart:ui' show Offset;

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_composer_cubit.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';

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
    test('carries the draft id, recipients and notes', () async {
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

    test(
      'opens BeaconCreateRoute with the same draft id, recipients and notes',
      () async {
        composer.start(BeaconKind.request, Offset.zero);
        await composer.contentChanged();
        await settle();
        composer.forwardCubit!.setRecipientNote('Ua', 'ты же хотел');

        final route = composer.fullFormHandoff()!.toRoute();

        expect(route, isA<BeaconCreateRoute>());
        final args = route.args! as BeaconCreateRouteArgs;
        expect(args.draftId, 'server-beacon');
        expect(args.initialRecipientIds, {'Ua', 'Ub', 'Uc'});
        expect(args.initialNotes, {'Ua': 'ты же хотел'});
      },
    );

    test('is unavailable before the server draft exists', () {
      composer.start(BeaconKind.request, Offset.zero);

      expect(composer.fullFormHandoff(), isNull);
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

    test('opens PostCreateRoute with the current recipient selection', () {
      composer.start(BeaconKind.post, Offset.zero);

      final route = composer.fullFormHandoff()!.toRoute();

      expect(route, isA<PostCreateRoute>());
      final args = route.args! as PostCreateRouteArgs;
      expect(args.initialRecipientIds, {'Ua', 'Ub', 'Uc'});
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
