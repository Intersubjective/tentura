import 'dart:async';
import 'dart:convert';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/beacon_plan/domain/use_case/beacon_plan_case.dart';
import 'package:tentura/features/beacon_plan/ui/bloc/plan_cubit.dart';
import 'package:tentura/features/beacon_plan/ui/bloc/plan_edit_cubit.dart';
import 'package:tentura/features/beacon_plan/ui/screen/plan_edit_screen.dart';
import 'package:tentura/features/beacon_threads/domain/coordination_item_room_sync.dart';
import 'package:tentura/features/beacon_threads/domain/room_host.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_state.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/basic_chat_body.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_threads/room_cubit_fakes.dart';
import '../beacon_view/beacon_view_screen_harness.dart';
import 'beacon_plan_test_support.dart';

/// #448: the «Plan saved» confirmation was a full-width bar at the bottom of
/// the Request screen, drawn over the chat composer beside the plan pane.
/// It must stay a confirmation of the plan pane: shown inside that pane (or
/// inline in it), never over the composer.

const _planSaved = 'Plan saved';
const _editedTitle = 'Bring boards, edited';

/// The QA viewport of the issue (desktop web).
const _desktop = Size(1280, 800);

/// An editable plan of the harness Request.
BeaconPlan _plan() {
  final json = jsonDecode(planJson()) as Map<String, Object?>;
  json['beaconId'] = kBeaconViewHarnessBeaconId;
  return BeaconPlan.decode(jsonEncode(json));
}

/// Root router stand-in that reports where the Request screen navigates, so
/// the host can rebuild the screen from the new URL as the app router does.
class _PlanRouter extends BeaconViewHarnessRouter {
  /// Set once the editor is open: earlier URL syncs of the mount are not
  /// followed.
  void Function(String path)? onNavigate;

  @override
  Future<void> navigatePath(
    String path, {
    bool includePrefixMatches = false,
    OnNavigationFailure? onFailure,
  }) async {
    await super.navigatePath(
      path,
      includePrefixMatches: includePrefixMatches,
      onFailure: onFailure,
    );
    onNavigate?.call(path);
  }
}

class _Threads extends Cubit<ThreadsState> implements ThreadsCubit {
  _Threads(super.initialState);

  void emitState(ThreadsState value) => emit(value);

  @override
  Future<void> fetch({bool silent = false}) async {}
}

/// The Request route: rebuilds the screen with the plan page of the URL.
class _RequestHost extends StatefulWidget {
  const _RequestHost({
    required this.planCubit,
    required this.threadsCubit,
    required this.host,
    super.key,
  });

  final PlanCubit planCubit;
  final ThreadsCubit threadsCubit;
  final ThreadHostCubit host;

  @override
  State<_RequestHost> createState() => _RequestHostState();
}

class _RequestHostState extends State<_RequestHost> {
  String? _planPage = kPlanPageEdit;

  void showUrl(String path) {
    final page = Uri.parse(path).queryParameters[kQueryPlanPage];
    if (page == _planPage) return;
    setState(() => _planPage = page);
  }

  @override
  Widget build(BuildContext context) => buildBeaconViewHarnessWidget(
    beaconState: beaconViewHarnessAuthorState(),
    threadsState: beaconViewHarnessThreadsState(),
    viewTab: kBeaconViewTabPlan,
    planPage: _planPage,
    planCubit: widget.planCubit,
    threadsCubit: widget.threadsCubit,
    host: widget.host,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeBeaconPlanRepository planRepo;
  late PlanCubit planCubit;
  late FakeBeaconThreadsRepository roomRepo;
  late List<RoomCubit> roomCubits;

  setUp(() async {
    roomRepo = FakeBeaconThreadsRepository(userId: kBeaconViewHarnessAuthorId);
    roomCubits = [];
    registerRoomCubitProfileCubit(kBeaconViewHarnessAuthorId);
    await registerBeaconViewHarnessGetIt(roomRepo: roomRepo);

    planRepo = FakeBeaconPlanRepository(_plan());
    final getIt = GetIt.I;
    if (getIt.isRegistered<BeaconPlanCase>()) {
      await getIt.unregister<BeaconPlanCase>();
    }
    getIt.registerSingleton<BeaconPlanCase>(planCaseFor(planRepo));
    planCubit = PlanCubit(
      beaconId: kBeaconViewHarnessBeaconId,
      viewerId: kBeaconViewHarnessAuthorId,
      planCase: planCaseFor(planRepo),
    );
    // Loaded before the editor opens, as when the Plan tab was shown first.
    await planCubit.load();
  });

  tearDown(() async {
    for (final cubit in roomCubits) {
      await cubit.close();
    }
    await planCubit.close();
    await unregisterBeaconViewHarnessGetIt();
  });

  ThreadHostCubit roomHost() => ThreadHostCubit(
    beaconId: kBeaconViewHarnessBeaconId,
    roomCubitFactory:
        ({
          required beaconId,
          threadItemId,
          initialUnreadAnchorAt,
          capabilities = const RoomCapabilities.request(),
        }) {
          final cubit = RoomCubit(
            beaconId: beaconId,
            threadItemId: threadItemId,
            initialUnreadAnchorAt: initialUnreadAnchorAt,
            beaconRoomCase: roomCubitMakeCase(roomRepo),
            coordinationItemRoomSync: CoordinationItemRoomSync(),
            presenceRepository: roomCubitFakePresenceRepository(),
            effects: FakeUiEffectPort(),
          );
          roomCubits.add(cubit);
          unawaited(cubit.load());
          return cubit;
        },
  );

  /// The Request with the plan editor open, on a window of [size]; from now
  /// on the screen follows the URL it navigates to.
  Future<void> pumpEditor(
    WidgetTester tester, {
    required Size size,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final router = _PlanRouter();
    final hostKey = GlobalKey<_RequestHostState>();
    final threads = _Threads(
      beaconViewHarnessThreadsState().copyWith(status: const StateIsLoading()),
    );
    addTearDown(threads.close);

    await tester.pumpWidget(
      StackRouterScope(
        controller: router,
        stateHash: 0,
        child: MaterialApp(
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('en'),
          home: BeaconViewResizableMediaQuery(
            size: size,
            child: _RequestHost(
              key: hostKey,
              planCubit: planCubit,
              threadsCubit: threads,
              host: roomHost(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    threads.emitState(beaconViewHarnessThreadsState());
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(
      find.byType(PlanEditScreen),
      findsOneWidget,
      reason: 'the plan editor must be open',
    );
    router.onNavigate = (path) => hostKey.currentState?.showUrl(path);
  }

  /// Edits a step and saves, then lets the page close and the notice
  /// animate in (well inside its display time).
  Future<void> saveAnEdit(WidgetTester tester) async {
    final editor = tester
        .element(find.byType(PlanEditScreen))
        .read<PlanEditCubit>();
    editor.putStep(editor.state.steps.first.copyWith(title: _editedTitle));
    await tester.pump();
    expect(editor.state.isDirty, isTrue, reason: 'the edit reached the draft');

    unawaited(editor.save());
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(planRepo.saveCalls, hasLength(1), reason: 'the plan was saved');
  }

  /// The surface the «Plan saved» notice is drawn on: the visible bar of a
  /// snack bar, or the text itself when it is shown inline.
  List<Rect> noticeSurfaces(WidgetTester tester) {
    final texts = find.text(_planSaved, findRichText: true);
    expect(
      texts,
      findsWidgets,
      reason: 'the «Plan saved» confirmation must still be shown',
    );
    return [
      for (final element in texts.evaluate())
        _surfaceOf(tester, find.byElementPredicate((e) => e == element)),
    ];
  }

  testWidgets(
    'wide window: the Plan saved notice stays inside the plan pane and the '
    'chat composer beside it stays visible and tappable',
    (tester) => _ignoringOverflow(() async {
      await pumpEditor(tester, size: _desktop);

      final composer = find.byType(BeaconRoomComposer);
      expect(
        composer,
        findsOneWidget,
        reason: 'the chat (with its composer) sits beside the plan pane',
      );
      final composerField = find.descendant(
        of: composer,
        matching: find.byType(TextField),
      );
      expect(composerField, findsOneWidget);

      await saveAnEdit(tester);

      final screen = Offset.zero & _desktop;
      final paneLeft = tester
          .getRect(find.byType(TenturaVerticalResizeHandle))
          .right;
      final composerRect = tester.getRect(composer);
      expect(
        composerRect.bottom <= screen.bottom + 0.5 &&
            composerRect.right <= paneLeft + 0.5,
        isTrue,
        reason:
            'the composer is on screen, left of the plan pane: '
            '$composerRect, pane from $paneLeft',
      );

      for (final notice in noticeSurfaces(tester)) {
        expect(notice.height, greaterThan(0));
        expect(
          notice.overlaps(composerRect),
          isFalse,
          reason:
              'the notice $notice is drawn over the composer '
              '$composerRect',
        );
        expect(
          notice.left,
          greaterThanOrEqualTo(paneLeft - 0.5),
          reason:
              'the notice $notice must stay in the plan pane '
              '(from x=$paneLeft), not span the chat',
        );
        expect(
          notice.right <= screen.right + 0.5 &&
              notice.top >= screen.top - 0.5 &&
              notice.bottom <= screen.bottom + 0.5,
          isTrue,
          reason: 'the notice $notice must be fully on screen $screen',
        );
      }

      final fieldCenter = tester.getRect(composerField).center;
      final hit = tester.hitTestOnBinding(fieldCenter);
      final fieldBox = tester.renderObject(composerField);
      expect(
        hit.path.any((entry) => identical(entry.target, fieldBox)),
        isTrue,
        reason: 'a tap on the composer must reach it, not the notice',
      );

      await _expectNoticeDismissed(tester);
    }),
  );

  testWidgets(
    'phone: the Plan saved notice is still shown after the editor closes',
    (tester) => _ignoringOverflow(() async {
      await pumpEditor(tester, size: kBeaconViewHarnessCompact);

      await saveAnEdit(tester);

      expect(
        find.byType(PlanEditScreen),
        findsNothing,
        reason: 'saving leaves the editor',
      );
      final screen = Offset.zero & kBeaconViewHarnessCompact;
      for (final notice in noticeSurfaces(tester)) {
        expect(notice.height, greaterThan(0));
        expect(
          notice.left >= screen.left - 0.5 &&
              notice.right <= screen.right + 0.5 &&
              notice.top >= screen.top - 0.5 &&
              notice.bottom <= screen.bottom + 0.5,
          isTrue,
          reason: 'the notice $notice must be fully on screen $screen',
        );
      }

      await _expectNoticeDismissed(tester);
    }),
  );
}

/// Runs [body] ignoring only RenderFlex overflow reports: the test font (Ahem,
/// every glyph a full em wide) overflows the Plan header Row
/// (beacon_plan_surface.dart) once the editor closes. Every other error still
/// reaches the test binding. Restored in the body, not in a tear-down, since
/// testWidgets checks the handler before tear-downs run.
Future<void> _ignoringOverflow(Future<void> Function() body) async {
  final original = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains('overflowed')) return;
    original?.call(details);
  };
  try {
    await body();
  } finally {
    FlutterError.onError = original;
  }
}

/// Lets the notice's display time run out, then checks it is gone.
Future<void> _expectNoticeDismissed(WidgetTester tester) async {
  const step = Duration(milliseconds: 100);
  const total = Duration(seconds: kSnackBarDuration + 1);
  for (var t = Duration.zero; t < total; t += step) {
    await tester.pump(step);
  }
  expect(
    find.text(_planSaved, findRichText: true),
    findsNothing,
    reason: 'the «Plan saved» confirmation must dismiss itself',
  );
}

/// The visible bar of the snack bar holding [text], or [text]'s own box.
Rect _surfaceOf(WidgetTester tester, Finder text) {
  final bar = find.ancestor(of: text, matching: find.byType(SnackBar));
  if (bar.evaluate().isEmpty) return tester.getRect(text);
  return tester.getRect(
    find.descendant(of: bar, matching: find.byType(Material)).first,
  );
}
