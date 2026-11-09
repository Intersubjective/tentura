// #1105: Request detail must guard unsent room composer text on every in-app
// Back path (app bar, phone tab-back, PopScope) and leave to Requests via
// AppNavigator.leaveRequestDetail.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:tentura/features/beacon_threads/data/service/beacon_room_composer_draft_store.dart';
import 'package:tentura/ui/navigation/app_navigator.dart';

import '../../support/fake_app_navigator.dart';
import '../../support/phone_surface.dart';
import 'beacon_view_screen_harness.dart';

const _requestId = 'B1105reqback01';
const _draftEn =
    'Unsent chat draft in the Request room composer before leaving the screen.';
const _draftRu =
    'Черновик сообщения в чате запроса перед выходом с экрана детали.';

const _wideSurface = Size(1280, 800);

class _CanPopHarnessRouter extends BeaconViewHarnessRouter {
  @override
  bool canPop({
    bool ignoreChildRoutes = false,
    bool ignoreParentRoutes = false,
    bool ignorePagelessRoutes = false,
  }) => true;
}

class _NavigatorThatPops extends FakeAppNavigator {
  _NavigatorThatPops(this.router);

  final BeaconViewHarnessRouter router;

  @override
  Future<void> leaveRequestDetail({bool retargetOwnerHomeTab = false}) async {
    await super.leaveRequestDetail(
      retargetOwnerHomeTab: retargetOwnerHomeTab,
    );
    if (router.canPop()) {
      await router.maybePop();
    }
  }
}

Future<void> _registerLeaveNavigator(BeaconViewHarnessRouter router) async {
  final getIt = GetIt.I;
  if (getIt.isRegistered<AppNavigator>()) {
    await getIt.unregister<AppNavigator>();
  }
  getIt.registerSingleton<AppNavigator>(_NavigatorThatPops(router));
}

Future<void> _tapAppBarBack(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.arrow_back));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(resetBeaconRoomComposerDraftStoreForTest);

  tearDown(() async {
    await unregisterBeaconViewHarnessGetIt();
  });

  group('#1105 request back with unsent composer', () {
    testWidgets('375×667 EN: chat tab back to overview then leave confirms', (
      tester,
    ) async {
      await usePhoneSurface(tester);
      final router = BeaconViewHarnessRouter();

      await pumpBeaconViewHarness(
        tester,
        size: kPhoneSurface,
        beaconState: beaconViewHarnessAuthorState(beaconId: _requestId),
        threadsState: beaconViewHarnessThreadsState(),
        router: router,
        plan: kBeaconViewHarnessOneStepPlan,
        afterGetItRegistered: () => _registerLeaveNavigator(router),
      );

      writeBeaconRoomComposerDraft(beaconId: _requestId, body: _draftEn);
      await tapBeaconChatTabAndWaitForRoom(tester);

      final handledChat = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(handledChat, isTrue);
      expect(find.text('Leave without saving?'), findsNothing);

      final handledOverview = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(handledOverview, isTrue);
      expect(find.text('Leave without saving?'), findsOneWidget);
    });

    testWidgets('375×667 RU: confirm copy fits without overflow', (
      tester,
    ) async {
      await usePhoneSurface(tester);
      final router = BeaconViewHarnessRouter();

      await pumpBeaconViewHarness(
        tester,
        size: kPhoneSurface,
        beaconState: beaconViewHarnessAuthorState(beaconId: _requestId),
        threadsState: beaconViewHarnessThreadsState(),
        router: router,
        locale: const Locale('ru'),
        afterGetItRegistered: () => _registerLeaveNavigator(router),
      );
      writeBeaconRoomComposerDraft(beaconId: _requestId, body: _draftRu);

      await _tapAppBarBack(tester);
      expect(find.text('Выйти без сохранения?'), findsOneWidget);
      expect(find.text('Введенные данные будут потеряны.'), findsOneWidget);
      expect(find.text('Выйти и сбросить'), findsOneWidget);
      expect(find.text('Вернуться к заполнению'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      '1280×800 RU: Stay keeps draft; Leave clears store and leaves',
      (tester) async {
        await usePhoneSurface(tester);
        final router = _CanPopHarnessRouter();

        final harness = await pumpBeaconViewHarness(
          tester,
          size: kPhoneSurface,
          beaconState: beaconViewHarnessAuthorState(beaconId: _requestId),
          threadsState: beaconViewHarnessThreadsState(),
          router: router,
          locale: const Locale('ru'),
          afterGetItRegistered: () => _registerLeaveNavigator(router),
        );
        writeBeaconRoomComposerDraft(beaconId: _requestId, body: _draftRu);
        await resizeBeaconViewHarness(tester, harness, _wideSurface);
        tester.takeException();

        await _tapAppBarBack(tester);
        expect(find.text('Выйти без сохранения?'), findsOneWidget);

        await tester.tap(find.text('Вернуться к заполнению'));
        await tester.pumpAndSettle();
        expect(readBeaconRoomComposerDraft(_requestId), _draftRu);
        expect(router.maybePopCalls, 0);

        await _tapAppBarBack(tester);
        await tester.tap(find.text('Выйти и сбросить'));
        await tester.pumpAndSettle();

        expect(readBeaconRoomComposerDraft(_requestId), isNull);
        expect(router.maybePopCalls, greaterThan(0));
      },
    );

    testWidgets('empty Request composer Back leaves with no dialog', (
      tester,
    ) async {
      final router = BeaconViewHarnessRouter();

      await pumpBeaconViewHarness(
        tester,
        size: kBeaconViewHarnessCompact,
        beaconState: beaconViewHarnessAuthorState(beaconId: _requestId),
        threadsState: beaconViewHarnessThreadsState(),
        router: router,
        locale: const Locale('ru'),
        afterGetItRegistered: () => _registerLeaveNavigator(router),
      );

      await _tapAppBarBack(tester);
      expect(find.text('Выйти без сохранения?'), findsNothing);
      final navigator = GetIt.I<AppNavigator>() as FakeAppNavigator;
      expect(navigator.named('leaveRequestDetail'), isNotEmpty);
    });
  });
}
