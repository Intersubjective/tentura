// Baton together: the «Create a plan step with {taker}?» sheet that follows a
// pick names the co-taker too when the author picked a pair (EN + RU), and
// stays as it was for a solo pick. The offer comes from a real RoomCubit pick.

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_responsive_scope.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_baton_plan_step_sheet.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'package:tentura/domain/entity/room_baton_data.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_plan/domain/entity/beacon_plan.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_plan/beacon_plan_test_support.dart';
import 'room_cubit_fakes.dart';

const _batonId = 'baton-1';
const _stepId = 'PS0000000000aa';

const _collecting = RoomBatonAuthorData(
  id: _batonId,
  status: RoomBatonStatus.collecting,
  candidates: [
    RoomBatonCandidate(
      userId: 'u-boris',
      title: 'Boris Driver',
      tier: 1,
      response: RoomBatonResponse.canHelp,
    ),
  ],
  allAnswered: true,
  eligibleCount: 1,
);

const _takenPair = RoomBatonAuthorData(
  id: _batonId,
  status: RoomBatonStatus.taken,
  candidates: [],
  allAnswered: true,
  eligibleCount: 1,
  taker: RoomBatonTaker(id: 'u-boris', title: 'Boris Driver'),
  coTaker: RoomBatonTaker(id: 'u-xenia', title: 'Xenia Partner'),
  selectionMode: RoomBatonSelectionMode.manual,
);

const _takenSolo = RoomBatonAuthorData(
  id: _batonId,
  status: RoomBatonStatus.taken,
  candidates: [],
  allAnswered: true,
  eligibleCount: 1,
  taker: RoomBatonTaker(id: 'u-boris', title: 'Boris Driver'),
  selectionMode: RoomBatonSelectionMode.manual,
);

class _Repository extends FakeBeaconThreadsRepository {
  _Repository({required super.userId});

  Exception? error;

  /// What the server answers; [_takenPair] by default.
  RoomBatonData? answer = _takenPair;

  @override
  Future<RoomBatonData?> batonSelect({
    required String batonId,
    String? userId,
  }) async {
    final failure = error;
    if (failure != null) throw failure;
    messages = [
      for (final m in messages)
        RoomMessage(
          id: m.id,
          beaconId: m.beaconId,
          authorId: m.authorId,
          body: m.body,
          createdAt: m.createdAt,
          baton: answer,
        ),
    ];
    return answer;
  }
}

Widget _app(Widget child, Locale locale) => MaterialApp(
  theme: TenturaTheme.light(),
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  locale: locale,
  home: MediaQuery(
    data: const MediaQueryData(size: Size(400, 900)),
    child: TenturaResponsiveScope(child: Scaffold(body: child)),
  ),
);

void main() {
  late _Repository repo;

  Future<BatonPlanStepOffer> pickOffer(
    WidgetTester tester,
    RoomBatonData answer,
  ) async {
    registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
    repo = _Repository(userId: kRoomCubitFakeMyUserId)
      ..answer = answer
      ..messages = [
        RoomMessage(
          id: 'msg-1',
          beaconId: kRoomCubitFakeBeaconId,
          authorId: kRoomCubitFakeMyUserId,
          body: 'Bring straps',
          createdAt: DateTime.utc(2026, 10, 3),
          baton: _collecting,
        ),
      ];
    final planRepo = FakeBeaconPlanRepository(
      BeaconPlan.decode(planJson()),
    );
    late BatonPlanStepOffer offer;
    await tester.runAsync(() async {
      final cubit = roomCubitForTest(
        repo,
        effects: FakeUiEffectPort(),
        planCase: planCaseFor(planRepo),
        newPlanStepId: () => _stepId,
      );
      addTearDown(cubit.close);
      await awaitRoomCubitLoad(cubit);
      final result = await cubit.batonSelect(
        batonId: _batonId,
        userId: 'u-boris',
      );
      offer = (result as BatonSelected).planStepOffer!;
    });
    return offer;
  }

  Future<void> openSheet(
    WidgetTester tester,
    BatonPlanStepOffer offer,
    Locale locale,
  ) async {
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => RoomBatonPlanStepSheet.show(
              context,
              offer: offer,
              onCreate: (_) async => true,
            ),
            child: const Text('open'),
          ),
        ),
        locale,
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  group('RoomBatonPlanStepSheet after a pair pick', () {
    testWidgets('names the co-taker next to the taker (EN)', (tester) async {
      final offer = await pickOffer(tester, _takenPair);
      await openSheet(tester, offer, const Locale('en'));

      expect(
        find.text('Create a plan step with Boris Driver?'),
        findsOneWidget,
      );
      expect(
        find.text('Xenia Partner takes it on together with them.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('assigned to Boris Driver'),
        findsNothing,
        reason: 'the pair sentence replaces the solo body',
      );
    });

    testWidgets('names the co-taker next to the taker (RU)', (tester) async {
      final offer = await pickOffer(tester, _takenPair);
      await openSheet(tester, offer, const Locale('ru'));

      expect(
        find.text('Создать шаг плана с исполнителем Boris Driver?'),
        findsOneWidget,
      );
      expect(
        find.text('Вместе с исполнителем: Xenia Partner.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('исполнитель — Boris Driver'),
        findsNothing,
        reason: 'the pair sentence replaces the solo body',
      );
    });

    testWidgets('a solo pick shows no pair sentence and the usual copy', (
      tester,
    ) async {
      final offer = await pickOffer(tester, _takenSolo);
      await openSheet(tester, offer, const Locale('en'));

      expect(
        find.text('Create a plan step with Boris Driver?'),
        findsOneWidget,
      );
      expect(
        find.text(
          "The step goes into this Request's plan, assigned to Boris Driver. "
          'You can change it in the plan later.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('together with them'), findsNothing);
      expect(find.textContaining('Xenia'), findsNothing);
    });
  });
}
