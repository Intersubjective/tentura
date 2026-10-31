// Tapping My desk while it is already the open tab brings the first Request
// that needs the viewer into view (`docs/features/request-attention.md` §6:
// a live obligation or a dot), or goes to the top when nothing does. The tap
// reaches the screen as `HomeTabReselectCubit.bump(HomeTab.work)`. Opening My
// desk from another tab is covered through the real Home shell in
// `test/features/home/my_desk_tab_reselect_scroll_wire_test.dart`.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/app/router/home_tab_branches.dart';
import 'package:tentura/data/repository/mock/client_repository_mocks.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/entity/my_work_beacon_attention.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/closure/data/repository/closure_repository.dart';
import 'package:tentura/features/home/domain/entity/home_activation.dart';
import 'package:tentura/features/home/domain/port/home_orientation_preferences_port.dart';
import 'package:tentura/features/home/ui/bloc/home_activation_cubit.dart';
import 'package:tentura/features/home/ui/bloc/home_attention_cubit.dart';
import 'package:tentura/features/home/ui/bloc/home_tab_reselect_cubit.dart';
import 'package:tentura/features/inbox/ui/bloc/inbox_operational_cubit.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_cubit.dart';
import 'package:tentura/features/my_work/ui/screen/my_work_screen.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/features/updates/domain/use_case/invite_accepted_setup_case.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/l10n/l10n_ru.dart';

import '../../support/phone_surface.dart';
import '../../support/test_realtime_sync.dart';
import '../block/support/controllable_block_case.dart';
import '../updates/support/noop_invite_setup_port.dart';
import 'my_work_test_support.dart';

const _accountId = 'user-desk-reselect';

/// Enough Requests that the desk is far taller than a 667 px phone.
const _requestCount = 10;

String _title(int n) => 'Request $n';
String _id(int n) => 'beacon-$n';

final class _Accounts implements AttentionAccountPort {
  final _changes = StreamController<String>.broadcast();

  @override
  Stream<String> get currentAccountChanges => _changes.stream;

  void emit(String accountId) => _changes.add(accountId);

  Future<void> close() => _changes.close();
}

final class _FakeOrientationPrefs implements HomeOrientationPreferencesPort {
  @override
  Future<bool> isActivated({required String userId}) async => true;

  @override
  Future<void> setActivated({required String userId}) async {}

  @override
  Future<bool> isOrientationDismissed({required String userId}) async => true;

  @override
  Future<void> setOrientationDismissed({required String userId}) async {}

  @override
  Future<void> resetFirstRunState({required String userId}) async {}

  @override
  Future<OrientationDebugOverride> getDebugOverride() async =>
      OrientationDebugOverride.auto;

  @override
  Future<void> setDebugOverride(OrientationDebugOverride value) async {}
}

final class _TestProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(
    profile: Profile(id: _accountId, displayName: 'Viewer'),
  );

  @override
  Stream<ProfileState> get stream =>
      Stream<ProfileState>.value(state).asBroadcastStream();
}

AttentionReceipt _receipt(
  String id,
  String beaconId, {
  required bool obligation,
}) => AttentionReceipt(
  id: id,
  category: obligation ? 'asksOfMe' : 'coordination',
  kind: obligation ? 'needsMe' : 'roomMessagePosted',
  priority: 'normal',
  title: 'Update',
  body: 'Something happened',
  actionUrl: '/#/',
  createdAt: DateTime.utc(2026, 9, 10),
  collapsedCount: 1,
  presentationKey: obligation ? null : 'room_message_posted',
  presentationPayloadJson: '{}',
  surface: AttentionSurface.myWork,
  beaconId: beaconId,
  requiresAction: obligation,
);

/// A dot (an uncleared optional event) on Request [n].
MyWorkBeaconAttention _dotOn(int n) => MyWorkBeaconAttention(
  beaconId: _id(n),
  unseenCount: 1,
  latestUnseen: _receipt('dot-$n', _id(n), obligation: false),
);

/// A live obligation on Request [n].
MyWorkBeaconAttention _obligationOn(int n) => MyWorkBeaconAttention(
  beaconId: _id(n),
  unseenCount: 0,
  liveObligations: [_receipt('ob-$n', _id(n), obligation: true)],
);

/// Newest first, so the desk's "recent" order is Request 1, 2, 3 …
Beacon _beacon(int n) => Beacon.empty.copyWith(
  id: _id(n),
  title: _title(n),
  createdAt: DateTime.utc(2026, 9, 28).subtract(Duration(days: n)),
  updatedAt: DateTime.utc(2026, 9, 28).subtract(Duration(days: n)),
  status: BeaconStatus.open,
);

/// 375×667 logical pixels in the view itself, so `MediaQuery` and the window
/// class see a phone (the surface size alone leaves them at 800×600).
Future<void> _usePhone(WidgetTester tester) async {
  await usePhoneSurface(tester);
  tester.view.physicalSize = kPhoneSurface;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

class _Desk {
  _Desk(this.reselect, this.cubit);

  final HomeTabReselectCubit reselect;
  final MyWorkCubit cubit;
}

ScrollController _listController(WidgetTester tester) => tester
    .widget<CustomScrollView>(find.byType(CustomScrollView).first)
    .controller!;

double _offset(WidgetTester tester) => _listController(tester).offset;

Rect _viewport(WidgetTester tester) => tester.getRect(
  find.byType(CustomScrollView).first,
);

/// The card for Request [n] is on screen: its title sits inside the list's
/// viewport rather than above or below it.
bool _inView(WidgetTester tester, int n) {
  final title = find.text(_title(n));
  if (title.evaluate().isEmpty) return false;
  final rect = tester.getRect(title);
  final view = _viewport(tester);
  return rect.top >= view.top && rect.bottom <= view.bottom;
}

/// [finder] matches one Text laid out inside the 375 px screen, with no
/// overflow reported. (The test font is monospaced Ahem, so ellipsis state is
/// not a trustworthy signal here.)
void _expectCopyOnScreen(WidgetTester tester, Finder finder, String what) {
  expect(tester.takeException(), isNull, reason: 'no overflow in ru');
  expect(finder, findsOneWidget, reason: '$what is on screen');
  final rect = tester.getRect(finder);
  expect(rect.left, greaterThanOrEqualTo(0), reason: '$what leaves the screen');
  expect(
    rect.right,
    lessThanOrEqualTo(kPhoneSurface.width),
    reason: '$what leaves the screen',
  );
}

/// The viewer scrolled the desk down to its end by hand.
Future<void> _scrollToEnd(WidgetTester tester) async {
  final controller = _listController(tester);
  controller.jumpTo(controller.position.maxScrollExtent);
  await tester.pumpAndSettle();
  expect(
    _offset(tester),
    greaterThan(0),
    reason:
        'the desk must be taller than the screen for this test to mean '
        'anything',
  );
}

Future<_Desk> _openDesk(
  WidgetTester tester, {
  required List<MyWorkBeaconAttention> attention,
  Locale locale = const Locale('en'),
}) async {
  await _usePhone(tester);

  final attentionRepo = StubAttentionRepository()
    ..myWorkAttentionResult = attention;
  final myWorkRepo = FakeMyWorkRepository()
    ..initResult = (
      authoredNonArchived: [
        for (var n = 1; n <= _requestCount; n++) _beacon(n),
      ],
      helpOfferedNonArchived: const [],
      obligationBeacons: const [],
      archivedCountHint: 0,
    );

  final accounts = _Accounts();
  final sync = buildTestRealtimeSync();
  final attentionCase = AttentionCase(
    attentionRepo,
    accounts,
    sync.case_,
    noopBlockCase(),
    FeedSessionRegistry(),
    Logger('my-desk-reselect-attention'),
  );
  GetIt.I
    ..registerSingleton<AttentionCase>(attentionCase)
    ..registerSingleton<InviteAcceptedSetupPort>(NoopInviteAcceptedSetupPort())
    ..registerSingleton<RealtimeSyncCase>(sync.case_);
  accounts.emit(_accountId);
  for (var i = 0; i < 12; i++) {
    await Future<void>.microtask(() {});
  }

  final homeAttention = HomeAttentionCubit(
    attentionCase,
    accounts,
    Logger('my-desk-reselect'),
  );
  final cubit = MyWorkCubit(
    userId: _accountId,
    myWorkCase: buildTestMyWorkCase(
      repo: myWorkRepo,
      attentionCase: attentionCase,
    ),
  );
  final reselect = HomeTabReselectCubit();
  final homeActivation = HomeActivationCubit(_FakeOrientationPrefs());
  final inboxOperational = InboxOperationalCubit()
    ..report(needsMeCount: 0, loadComplete: true);
  await homeActivation.bindAccount(_accountId);
  homeActivation.reportMyWork(
    accountId: _accountId,
    myWorkCardCount: _requestCount,
    draftCount: 0,
    archivedCountHint: 0,
    myWorkLoaded: true,
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    unawaited(cubit.close());
    unawaited(homeAttention.close());
    unawaited(reselect.close());
    unawaited(accounts.close());
  });

  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: TenturaResponsiveScope(
        child: MultiBlocProvider(
          providers: [
            BlocProvider<MyWorkCubit>.value(value: cubit),
            BlocProvider<HomeActivationCubit>.value(value: homeActivation),
            BlocProvider<HomeAttentionCubit>.value(value: homeAttention),
            BlocProvider<InboxOperationalCubit>.value(value: inboxOperational),
            BlocProvider<ProfileCubit>.value(value: _TestProfileCubit()),
            BlocProvider<HomeTabReselectCubit>.value(value: reselect),
            BlocProvider(create: (_) => ScreenCubit.local()),
          ],
          child: const MyWorkScreen(),
        ),
      ),
    ),
  );
  await tester.pump();
  for (var i = 0; i < 32 && !cubit.state.isSuccess; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  for (var i = 0; i < 16; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return _Desk(reselect, cubit);
}

/// What tapping the open My desk destination does to the screen.
Future<void> _tapMyDeskAgain(WidgetTester tester, _Desk desk) async {
  desk.reselect.bump(HomeTab.work);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    if (!GetIt.I.isRegistered<Logger>()) {
      GetIt.I.registerSingleton<Logger>(Logger('my-desk-reselect'));
    }
    if (!GetIt.I.isRegistered<BeaconRepository>()) {
      GetIt.I.registerSingleton<BeaconRepository>(FakeBeaconRepository());
    }
    if (!GetIt.I.isRegistered<ClosureRepository>()) {
      GetIt.I.registerSingleton<ClosureRepository>(ClosureRepositoryMock());
    }
  });

  tearDown(() async {
    if (GetIt.I.isRegistered<AttentionCase>()) {
      unawaited(GetIt.I<AttentionCase>().dispose());
      GetIt.I.unregister<AttentionCase>();
    }
    if (GetIt.I.isRegistered<InviteAcceptedSetupPort>()) {
      GetIt.I.unregister<InviteAcceptedSetupPort>();
    }
    if (GetIt.I.isRegistered<RealtimeSyncCase>()) {
      GetIt.I.unregister<RealtimeSyncCase>();
    }
    if (GetIt.I.isRegistered<BeaconRepository>()) {
      GetIt.I.unregister<BeaconRepository>();
    }
    if (GetIt.I.isRegistered<ClosureRepository>()) {
      GetIt.I.unregister<ClosureRepository>();
    }
  });

  group('tapping My desk while it is open', () {
    testWidgets(
      'brings the third Request into view when only it carries a dot (ru, 375×667)',
      (tester) async {
        final desk = await _openDesk(
          tester,
          attention: [_dotOn(3)],
          locale: const Locale('ru'),
        );
        expect(
          _inView(tester, 3),
          isTrue,
          reason: 'precondition: Request 3 starts near the top of the desk',
        );
        _expectCopyOnScreen(
          tester,
          find.textContaining(L10nRu().myWorkSectionInProgress.toUpperCase()),
          'section header',
        );
        await _scrollToEnd(tester);
        expect(
          find.text(_title(3)).hitTestable(),
          findsNothing,
          reason: 'precondition: the viewer has scrolled past Request 3',
        );

        await _tapMyDeskAgain(tester, desk);

        expect(tester.takeException(), isNull);
        expect(_inView(tester, 3), isTrue);
        expect(
          _inView(tester, _requestCount),
          isFalse,
          reason: 'it went to the Request needing attention, not the end',
        );
      },
    );

    testWidgets(
      'brings a Request with a live obligation into view, ahead of a dot above it',
      (tester) async {
        // Request 2 only has a dot, Request 7 has an obligation: the desk
        // lists obligations first, so the obligation is the first Request
        // needing the viewer.
        final desk = await _openDesk(
          tester,
          attention: [_dotOn(2), _obligationOn(7)],
        );
        await _scrollToEnd(tester);

        await _tapMyDeskAgain(tester, desk);

        expect(tester.takeException(), isNull);
        expect(_inView(tester, 7), isTrue);
      },
    );

    testWidgets(
      'goes to the top when no Request needs attention (ru, 375×667)',
      (tester) async {
        final desk = await _openDesk(
          tester,
          attention: const [],
          locale: const Locale('ru'),
        );
        _expectCopyOnScreen(
          tester,
          find.text(L10nRu().myWorkCaughtUp),
          'caught-up line',
        );
        await _scrollToEnd(tester);

        await _tapMyDeskAgain(tester, desk);

        expect(tester.takeException(), isNull);
        expect(_offset(tester), 0);
        expect(_inView(tester, 1), isTrue);
        _expectCopyOnScreen(
          tester,
          find.text(L10nRu().myWorkCaughtUp),
          'caught-up line',
        );
      },
    );

    testWidgets(
      'is a no-op for position when already at the Request needing attention',
      (tester) async {
        final desk = await _openDesk(tester, attention: [_dotOn(1)]);
        final before = _offset(tester);

        await _tapMyDeskAgain(tester, desk);

        expect(before, 0);
        expect(_offset(tester), 0);
        expect(_inView(tester, 1), isTrue);
      },
    );
  });
}
