import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_store_case.dart'
    show kLazyWriteAckTimeout;
import 'package:tentura/features/graph/data/repository/graph_source_repository.dart';
import 'package:tentura/features/graph/domain/entity/edge_directed.dart';
import 'package:tentura/features/graph/domain/entity/graph_edge_colors.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/graph/ui/bloc/graph_cubit.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/features/graph/ui/screen/graph_screen.dart';
import 'package:tentura/features/like/domain/exception.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../support/graph_trust_write_fixture.dart';
import '../../ui/effect/fake_ui_effect_port.dart';

// The mini-profile trust toggle of the graph screen flips at once, shows no
// progress state, and flips back with a Retry snackbar when the write fails.
// A write that is not acknowledged in time shows the overdue notice.

const _me = Profile(id: 'Ume', displayName: 'Me');
const _bob = Profile(id: 'Ub', displayName: 'Bob');
const _alice = Profile(id: 'Ua', displayName: 'Alice');

const _edgeColors = GraphEdgeColors(
  negative: Colors.red,
  ego: Colors.orange,
  neutral: Colors.blue,
  target: Colors.green,
);

final class _Source implements GraphSourceRepository {
  @override
  Future<Set<EdgeDirected>> fetch({
    bool positiveOnly = true,
    String context = '',
    String? focus,
    int offset = 0,
    int limit = 5,
    String? viewerUserId,
    Set<String> excludeNeighborIds = const {},
  }) async => focus == null
      ? {
          (
            src: 'Ume',
            dst: 'Ub',
            weight: 1.0,
            node: const UserNode(user: _bob),
            branch: null,
            srcTotalNeighborCount: null,
            dstTotalNeighborCount: null,
          ),
          (
            src: 'Ume',
            dst: 'Ua',
            weight: 1.0,
            node: const UserNode(user: _alice),
            branch: null,
            srcTotalNeighborCount: null,
            dstTotalNeighborCount: null,
          ),
        }
      : const {};

  @override
  Future<Set<EdgeDirected>> fetchEdgesBetween({
    required Set<String> nodeIds,
    bool positiveOnly = true,
  }) async => const {};
}

final class _BeaconRepository implements BeaconRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

final class _StubRouter extends Mock implements StackRouter {
  @override
  bool canPop({
    bool ignoreChildRoutes = false,
    bool ignoreParentRoutes = false,
    bool ignorePagelessRoutes = false,
  }) => false;
}

final class _ProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState();

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

Future<void> _pumpFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

Future<GraphTrustWriteFixture> _openBobPanel(WidgetTester tester) async {
  const size = Size(900, 600);
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final fixture = GraphTrustWriteFixture();
  fixture.profiles.byId.addAll({'Ub': _bob, 'Ua': _alice});
  final graphCubit = GraphCubit(
    me: _me,
    graphSourceRepository: _Source(),
    edgeColors: _edgeColors,
    beaconRepository: _BeaconRepository(),
    profileRepository: fixture.profiles,
    effects: FakeUiEffectPort(),
  );
  graphCubit.emit(graphCubit.state.copyWith(isAnimated: false));
  final contextCubit = fixture.createCubit(
    viewerId: _me.id,
    onProfilePatched: graphCubit.patchLoadedProfile,
  );
  addTearDown(graphCubit.close);
  addTearDown(fixture.dispose);

  await tester.pumpWidget(
    StackRouterScope(
      controller: _StubRouter(),
      stateHash: 0,
      child: MaterialApp(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: MediaQuery(
          data: const MediaQueryData(size: size),
          child: TenturaResponsiveScope(
            child: MultiBlocProvider(
              providers: [
                BlocProvider<GraphCubit>.value(value: graphCubit),
                BlocProvider<GraphPersonContextCubit>.value(
                  value: contextCubit,
                ),
                BlocProvider<ScreenCubit>(create: (_) => ScreenCubit.local()),
                BlocProvider<ProfileCubit>.value(value: _ProfileCubit()),
              ],
              child: const GraphScreen(),
            ),
          ),
        ),
      ),
    ),
  );
  await _pumpFrames(tester);
  fixture.account.add('Ume');
  await tester.tap(find.byKey(TestIds.key(TestIds.graphNode('Ub'))));
  await _pumpFrames(tester);
  return fixture;
}

final _toggle = find.byKey(TestIds.key(TestIds.graphPersonContextTrust));

bool _isOn(WidgetTester tester) => tester.widget<Switch>(_toggle).value;

void main() {
  late Map<String, dynamic> en;

  setUpAll(() {
    en =
        jsonDecode(File('l10n/app_en.arb').readAsStringSync())
            as Map<String, dynamic>;
  });

  testWidgets('the toggle flips at once and stays enabled with no spinner', (
    tester,
  ) async {
    final fixture = await _openBobPanel(tester);
    expect(_isOn(tester), isFalse);

    await tester.tap(_toggle);
    await tester.pump();

    expect(_isOn(tester), isTrue);
    expect(tester.widget<Switch>(_toggle).onChanged, isNotNull);
    expect(
      find.descendant(
        of: find.byKey(TestIds.key(TestIds.graphPersonContextPanel)),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsNothing,
    );
    expect(fixture.likes.amounts, [1]);
  });

  testWidgets('a rejected change flips back and Retry re-issues the value', (
    tester,
  ) async {
    final fixture = await _openBobPanel(tester);
    await tester.tap(_toggle);
    await tester.pump();

    fixture.likes.fail(0, const LikeSetException());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(_isOn(tester), isFalse);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text(en['graphTrustNotSaved'] as String), findsOneWidget);

    await tester.tap(
      find.widgetWithText(SnackBarAction, en['graphTrustRetry'] as String),
    );
    await tester.pump();

    expect(_isOn(tester), isTrue);
    expect(fixture.likes.amounts, [1, 1]);
  });

  testWidgets('exhausted transport retries revert trust and offer Retry', (
    tester,
  ) async {
    final fixture = await _openBobPanel(tester);
    await tester.tap(_toggle);
    await tester.pump();
    for (var attempt = 0; attempt < 3; attempt++) {
      expect(fixture.likes.calls, hasLength(attempt + 1));
      final schedulesBeforeFailure = fixture.wakeUp.calls.length;
      fixture.likes.fail(attempt, TimeoutException('no acknowledgement'));
      await tester.pump();
      if (attempt < 2) {
        final delay = expectR4RetryScheduled(
          fixture.wakeUp,
          schedulesBeforeFailure,
          attempt: attempt + 1,
        );
        fixture.wakeUp.elapse(delay - const Duration(milliseconds: 1));
        await tester.pump();
        expect(fixture.likes.calls, hasLength(attempt + 1));
        fixture.wakeUp.elapse(const Duration(milliseconds: 1));
        await tester.pump();
      }
    }
    await tester.pump(const Duration(milliseconds: 300));
    expect(_isOn(tester), isFalse);
    expect(
      find.widgetWithText(SnackBar, 'Trust change not saved'),
      findsOneWidget,
    );
    expect(find.widgetWithText(SnackBarAction, 'Retry'), findsOneWidget);
    await tester.tap(find.widgetWithText(SnackBarAction, 'Retry'));
    await tester.pump();
    expect(fixture.likes.amounts, [1, 1, 1, 1]);
    expect(_isOn(tester), isTrue);
  });

  testWidgets('rejection after switching peers retries the original intent', (
    tester,
  ) async {
    final fixture = await _openBobPanel(tester);
    await tester.tap(_toggle);
    await tester.pump();
    fixture.contextCubit.selectProfile(_alice, intentional: true);
    await _pumpFrames(tester);
    final selected = fixture.contextCubit.state.selectedProfile;
    fixture.likes.fail(0, const LikeSetException());
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(fixture.contextCubit.state.selectedProfile, selected);
    expect(_isOn(tester), isFalse);
    expect(find.text('Trust change not saved'), findsOneWidget);
    await tester.tap(find.widgetWithText(SnackBarAction, 'Retry'));
    await tester.pump();
    expect(fixture.likes.calls.map((call) => call.id), ['Ub', 'Ub']);
    expect(fixture.likes.amounts, [1, 1]);
    expect(fixture.contextCubit.state.selectedProfile, selected);
    expect(_isOn(tester), isFalse);
  });

  testWidgets('an unacknowledged change shows the overdue notice', (
    tester,
  ) async {
    final fixture = await _openBobPanel(tester);
    await tester.tap(_toggle);
    await tester.pump();
    expect(find.byType(SnackBar), findsNothing);

    fixture.wakeUp.elapse(
      kLazyWriteAckTimeout - const Duration(milliseconds: 1),
    );
    await tester.pump(kLazyWriteAckTimeout - const Duration(milliseconds: 1));
    expect(find.byType(SnackBar), findsNothing);
    fixture.wakeUp.elapse(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(en['lazyWriteAckOverdue'] as String), findsOneWidget);
    expect(_isOn(tester), isTrue);
  });
  testWidgets(
    'an acknowledgement before fifteen seconds raises no timeout notice',
    (tester) async {
      final fixture = await _openBobPanel(tester);
      await tester.tap(_toggle);
      await tester.pump();
      fixture.wakeUp.elapse(const Duration(seconds: 10));
      await tester.pump(const Duration(seconds: 10));
      fixture.likes.ack(0);
      await tester.pump();
      fixture.wakeUp.elapse(const Duration(seconds: 30));
      await tester.pump(const Duration(seconds: 30));
      expect(find.byType(SnackBar), findsNothing);
      expect(_isOn(tester), isTrue);
    },
  );

  testWidgets(
    'a transport retry does not restart the fifteen second notice deadline',
    (tester) async {
      final fixture = await _openBobPanel(tester);
      await tester.tap(_toggle);
      await tester.pump();
      fixture.wakeUp.elapse(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 5));
      final schedulesBeforeFailure = fixture.wakeUp.calls.length;
      fixture.likes.fail(0, TimeoutException('no acknowledgement'));
      await tester.pump();
      final delay = expectR4RetryScheduled(
        fixture.wakeUp,
        schedulesBeforeFailure,
        attempt: 1,
      );
      fixture.wakeUp.elapse(delay);
      await tester.pump(delay);
      expect(fixture.likes.amounts, [1, 1]);
      expect(find.byType(SnackBar), findsNothing);
      fixture.wakeUp.elapse(
        kLazyWriteAckTimeout - const Duration(seconds: 5) - delay,
      );
      await tester.pump(
        kLazyWriteAckTimeout - const Duration(seconds: 5) - delay,
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(en['lazyWriteAckOverdue'] as String), findsOneWidget);
    },
  );

  testWidgets(
    'overdue writes in the same burst show only one timeout snackbar',
    (tester) async {
      final fixture = await _openBobPanel(tester);
      await tester.tap(_toggle);
      await tester.pump();
      // Focusing Bob hides Alice's node, so select her as a node tap would.
      fixture.contextCubit.selectProfile(_alice, intentional: true);
      await _pumpFrames(tester);
      fixture.wakeUp.elapse(const Duration(milliseconds: 450));
      expect(_isOn(tester), isFalse);
      await tester.tap(_toggle);
      await tester.pump();
      expect(fixture.likes.calls, hasLength(2));
      fixture.wakeUp.elapse(kLazyWriteAckTimeout);
      await tester.pump(kLazyWriteAckTimeout);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(en['lazyWriteAckOverdue'] as String), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.text(en['lazyWriteAckOverdue'] as String),
        findsNothing,
        reason: 'another overdue write must not enqueue a second snackbar',
      );
    },
  );

  testWidgets('logout cancels the overdue notice for a pending trust write', (
    tester,
  ) async {
    final fixture = await _openBobPanel(tester);
    await tester.tap(_toggle);
    await tester.pump();
    fixture.account.add('');
    await tester.pump();
    expect(_isOn(tester), isFalse);
    expect(_isOn(tester), isFalse);
    fixture.wakeUp.elapse(kLazyWriteAckTimeout * 2);
    await tester.pump(kLazyWriteAckTimeout * 2);
    expect(find.byType(SnackBar), findsNothing);
    fixture.likes.fail(0, TimeoutException('late old-account failure'));
    await tester.pump();
    fixture.wakeUp.elapse(const Duration(minutes: 1));
    await tester.pump();
    expect(fixture.likes.amounts, [1]);
    expect(_isOn(tester), isFalse);
  });
  testWidgets(
    'an old acknowledgement after logout cannot dispatch a queued trust change',
    (tester) async {
      final fixture = await _openBobPanel(tester);
      await tester.tap(_toggle);
      await tester.pump();
      unawaited(fixture.contextCubit.untrustSelected());
      await tester.pump();
      expect(fixture.likes.amounts, [1]);
      fixture.account.add('');
      await tester.pump();
      expect(_isOn(tester), isFalse);
      fixture.likes.ack(0);
      await tester.pump();
      fixture.wakeUp.elapse(const Duration(minutes: 1));
      await tester.pump();
      expect(fixture.likes.amounts, [1]);
      expect(_isOn(tester), isFalse);
      expect(find.byType(SnackBar), findsNothing);
    },
  );
}
