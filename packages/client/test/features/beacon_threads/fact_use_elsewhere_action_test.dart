// «Use in another Request» in the fact actions sheet (plan §6.1): shown to
// every reader — not gated by edit rights — whenever the host passes
// `onUseElsewhere`, and one tap hands the fact to it once.
//
// `onUseElsewhere` is the parameter the plan names; like the sheet's other
// per-fact actions (onQuoteInChat, onEditHistory) it receives the fact. Both
// hosts — the room's showFactActionsSheet and the Request detail's
// showBeaconFactActions — take the same callback from their caller (the
// destination picker that consumes it is a later change) and the tile hands
// the fact to it exactly once. Until these parameters exist this file does
// not compile.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_threads/ui/widget/fact_actions_sheet.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_fact_actions.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_view/beacon_view_case_test_support.dart';
import '../beacon_view/beacon_view_initial_load_test.dart' show pumpUntil;
import 'fact_origin_test_support.dart';
import 'room_cubit_fakes.dart';

void main() {
  group('«Use in another Request» tile', () {
    for (final canMutate in [false, true]) {
      testWidgets('is shown with canMutate=$canMutate and one tap calls '
          'onUseElsewhere once with the fact', (tester) async {
        registerFactRepository(FakeOriginFactCardRepository());
        final calls = <BeaconFactCard>[];
        final fact = copiedFact(originBeaconKind: null);
        await pumpOpener(
          tester,
          open: (ctx) => unawaited(
            showFactActionsHostSheet(
              ctx,
              fact: fact,
              canMutate: canMutate,
              onCorrect:
                  ({
                    required factCardId,
                    required newText,
                    attachmentsJson,
                  }) async {},
              onRemove: ({required factCardId}) async {},
              onSetVisibility:
                  ({required factCardId, required visibility}) async {},
              onUseElsewhere: calls.add,
            ),
          ),
        );

        expect(find.text(kUseInAnotherRequest), findsOneWidget);
        await tester.tap(find.text(kUseInAnotherRequest));
        await tester.pumpAndSettle();

        expect(calls, hasLength(1));
        expect(calls.single.id, fact.id);
      });
    }
  });

  group('both hosts hand «Use in another Request» to their caller once', () {
    Future<void> tapTileOnce(WidgetTester tester) async {
      expect(find.text(kUseInAnotherRequest), findsOneWidget);
      await tester.tap(find.text(kUseInAnotherRequest));
      await tester.pumpAndSettle();
    }

    testWidgets('the room actions sheet (showFactActionsSheet)', (
      tester,
    ) async {
      registerFactRepository(FakeOriginFactCardRepository());
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      final fakeRoom = FakeBeaconThreadsRepository(
        userId: kRoomCubitFakeMyUserId,
      );
      addTearDown(fakeRoom.dispose);
      final cubit = roomCubitForTest(fakeRoom);
      addTearDown(cubit.close);
      await awaitRoomCubitLoad(cubit);
      final fact = copiedFact(
        originBeaconKind: null,
        beaconId: kRoomCubitFakeBeaconId,
      );
      final calls = <BeaconFactCard>[];

      await pumpOpener(
        tester,
        open: (ctx) => unawaited(
          showFactActionsSheet(
            ctx,
            cubit: cubit,
            fact: fact,
            onUseElsewhere: calls.add,
          ),
        ),
      );
      await tapTileOnce(tester);

      expect(calls.map((f) => f.id), [fact.id]);
    });

    testWidgets('the Request detail facts actions (showBeaconFactActions)', (
      tester,
    ) async {
      registerFactRepository(FakeOriginFactCardRepository());
      const beaconId = 'Buse-elsewhere-view';
      final fact = copiedFact(originBeaconKind: null, beaconId: beaconId);
      final beacon = Beacon(
        id: beaconId,
        title: 'Facts beacon',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        author: const Profile(id: 'Uauthor', displayName: 'Author'),
      );
      final cubit = (await tester.runAsync(() async {
        final c = BeaconViewCubit(
          id: beaconId,
          myProfile: const Profile(id: 'Uviewer', displayName: 'Viewer'),
          beaconViewCase: buildTestBeaconViewCase(
            beaconRepo: TrackingBeaconRepository()
              ..fetchByIdHandler = (_) async => beacon,
            factCardsRepo: FakeBeaconViewFactCardRepository(cards: [fact]),
          ),
          effects: FakeUiEffectPort(),
        );
        await pumpUntil(c.stream, () => c.state.beaconContextLoaded);
        return c;
      }))!;
      addTearDown(cubit.close);
      final calls = <BeaconFactCard>[];

      await pumpOpener(
        tester,
        open: (ctx) => unawaited(
          showBeaconFactActions(
            ctx,
            cubit: cubit,
            fact: fact,
            onUseElsewhere: calls.add,
          ),
        ),
      );
      await tapTileOnce(tester);

      expect(calls.map((f) => f.id), [fact.id]);
    });
  });
}
