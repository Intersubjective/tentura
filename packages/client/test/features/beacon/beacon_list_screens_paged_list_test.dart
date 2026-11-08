// 5839aa013 (#1173 split): BeaconScreen and InvolvedBeaconScreen render
// their body through the shared BeaconPagedList. Neither screen had a
// widget test; this pins the four body states for both (first-load
// spinner, error with Retry, pull-to-refresh empty state with each screen's
// own empty copy, and the beacon list), plus what Retry and the initial
// load ask of the cubit.

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon/domain/enum.dart';
import 'package:tentura/features/beacon/ui/bloc/beacon_cubit.dart';
import 'package:tentura/features/beacon/ui/bloc/involved_beacon_cubit.dart';
import 'package:tentura/features/beacon/ui/screen/beacon_screen.dart';
import 'package:tentura/features/beacon/ui/screen/involved_beacon_screen.dart';
import 'package:tentura/features/beacon/ui/widget/beacon_paged_list.dart';
import 'package:tentura/features/beacon/ui/widget/beacon_tile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/l10n/l10n.dart';

class _MockProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState();

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

class _Router extends Mock implements StackRouter {
  @override
  PagelessRoutesObserver get pagelessRoutesObserver => PagelessRoutesObserver();

  @override
  bool canPop({
    bool ignoreChildRoutes = false,
    bool ignoreParentRoutes = false,
    bool ignorePagelessRoutes = false,
  }) => false;
}

/// Records each `fetch` call's `reset` flag.
mixin _RecordsFetch {
  final fetchResets = <bool>[];

  Future<void> fetch({bool reset = false}) async => fetchResets.add(reset);
}

class _BeaconCubit extends Cubit<BeaconState>
    with _RecordsFetch
    implements BeaconCubit {
  _BeaconCubit(super.initialState);

  @override
  void setFilter(BeaconFilter? filter) {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _InvolvedBeaconCubit extends Cubit<InvolvedBeaconState>
    with _RecordsFetch
    implements InvolvedBeaconCubit {
  _InvolvedBeaconCubit(super.initialState);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// The parts of a list-screen body state the shared list reads.
typedef _Body = ({List<Beacon> beacons, StateStatus status, Object? error});

const _author = Profile(id: 'Uauthor00001', displayName: 'Author');

List<Beacon> _beacons(int n) => [
  for (var i = 0; i < n; i++)
    Beacon.empty.copyWith(
      id: 'Bpaged0000$i',
      title: 'Request $i',
      author: _author,
    ),
];

/// One screen under test: how to pump it with a body state, its own empty
/// copy, and the fetch calls its cubit saw.
typedef _ScreenCase = ({
  String name,
  Future<_RecordsFetch> Function(WidgetTester tester, _Body body) pump,
  String Function(L10n l10n) emptyCopy,
  bool showAuthor,
});

Future<void> _pumpHost(WidgetTester tester, Widget screen) async {
  tester.view
    ..physicalSize = const Size(400, 900)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = _Router();
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: TenturaTheme.light(),
      home: RouterScope(
        controller: router,
        stateHash: 0,
        inheritableObserversBuilder: () => const [],
        child: StackRouterScope(
          controller: router,
          stateHash: 0,
          child: BlocProvider<ProfileCubit>.value(
            value: _MockProfileCubit(),
            child: screen,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

final List<_ScreenCase> _screens = [
  (
    name: 'BeaconScreen',
    pump: (tester, body) async {
      final cubit = _BeaconCubit(
        BeaconState(
          profileId: 'Uauthor00001',
          beacons: body.beacons,
          status: body.status,
          loadError: body.error,
        ),
      );
      addTearDown(cubit.close);
      await _pumpHost(
        tester,
        BlocProvider<BeaconCubit>.value(
          value: cubit,
          child: const BeaconScreen(id: 'Uauthor00001'),
        ),
      );
      return cubit;
    },
    emptyCopy: (l10n) => l10n.noBeaconsMessage,
    showAuthor: false,
  ),
  (
    name: 'InvolvedBeaconScreen',
    pump: (tester, body) async {
      final cubit = _InvolvedBeaconCubit(
        InvolvedBeaconState(
          authorId: 'Uauthor00001',
          beacons: body.beacons,
          status: body.status,
          loadError: body.error,
        ),
      );
      addTearDown(cubit.close);
      await _pumpHost(
        tester,
        BlocProvider<InvolvedBeaconCubit>.value(
          value: cubit,
          child: const InvolvedBeaconScreen(id: 'Uauthor00001'),
        ),
      );
      return cubit;
    },
    emptyCopy: (l10n) => l10n.noInvolvedBeaconsMessage,
    showAuthor: true,
  ),
];

void main() {
  final l10n = lookupL10n(const Locale('en'));

  for (final screen in _screens) {
    group('${screen.name} body through BeaconPagedList', () {
      testWidgets('first load: spinner only, and the screen asks for the '
          'first page', (tester) async {
        final cubit = await screen.pump(tester, (
          beacons: const [],
          status: const StateIsLoading(),
          error: null,
        ));

        expect(find.byType(BeaconPagedList), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(BeaconPagedList),
            matching: find.byType(TenturaCircularProgress),
          ),
          findsOneWidget,
        );
        expect(find.byType(BeaconTile), findsNothing);
        expect(cubit.fetchResets, [false]);
      });

      testWidgets('error with nothing loaded: error icon and Retry, which '
          'reloads from the first page', (tester) async {
        final cubit = await screen.pump(tester, (
          beacons: const [],
          status: const StateIsSuccess(),
          error: Exception('down'),
        ));

        expect(find.byIcon(Icons.error_outline), findsOneWidget);
        final retry = find.widgetWithText(FilledButton, l10n.myWorkRetry);
        expect(retry, findsOneWidget);
        expect(find.text(screen.emptyCopy(l10n)), findsNothing);

        await tester.tap(retry);
        await tester.pump();
        expect(cubit.fetchResets, [false, true]);
      });

      testWidgets("empty: the screen's own empty copy inside a "
          'pull-to-refresh list', (tester) async {
        await screen.pump(tester, (
          beacons: const [],
          status: const StateIsSuccess(),
          error: null,
        ));

        expect(find.text(screen.emptyCopy(l10n)), findsOneWidget);
        expect(
          find.ancestor(
            of: find.text(screen.emptyCopy(l10n)),
            matching: find.byType(RefreshIndicator),
          ),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.error_outline), findsNothing);
        expect(find.byType(BeaconTile), findsNothing);
      });

      testWidgets('list: one tile per beacon, author shown as the screen '
          'did before', (tester) async {
        await screen.pump(tester, (
          beacons: _beacons(2),
          status: const StateIsSuccess(),
          error: null,
        ));

        final tiles = tester
            .widgetList<BeaconTile>(find.byType(BeaconTile))
            .toList();
        expect(
          [for (final t in tiles) t.beacon.id],
          [
            'Bpaged00000',
            'Bpaged00001',
          ],
        );
        expect(tiles.every((t) => t.showAuthor == screen.showAuthor), isTrue);
        expect(find.text(screen.emptyCopy(l10n)), findsNothing);
      });

      testWidgets('an error with beacons already loaded keeps the list', (
        tester,
      ) async {
        await screen.pump(tester, (
          beacons: _beacons(1),
          status: const StateIsSuccess(),
          error: Exception('down'),
        ));

        expect(find.byType(BeaconTile), findsOneWidget);
        expect(find.byIcon(Icons.error_outline), findsNothing);
      });
    });
  }
}
