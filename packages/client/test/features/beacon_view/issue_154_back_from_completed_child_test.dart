import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/ui/navigation/app_navigator.dart';
import 'package:tentura/ui/navigation/home_tab.dart';

import '../../support/fake_app_navigator.dart';
import 'beacon_view_screen_harness.dart';

const _kParentRequestId = 'B154parent';
const _kChildRequestId = 'B154child';

/// Root stack used by [_leaveBeaconView] when the browse stack cannot pop.
class _Issue154RootRouter extends Mock implements RootStackRouter {
  _Issue154RootRouter(this.replacedPaths);

  final List<String> replacedPaths;

  @override
  Future<T?> replacePath<T extends Object?>(
    String path, {
    bool includePrefixMatches = true,
    OnNavigationFailure? onFailure,
  }) async {
    replacedPaths.add(path);
    return null;
  }
}

/// Simulates a completed child detail where the parent frame is no longer
/// poppable on the root browse stack (post-close / history drift).
class _Issue154StackRouter extends BeaconViewHarnessRouter {
  _Issue154StackRouter() {
    rootRouter = _Issue154RootRouter(rootReplacedPaths);
  }

  final List<String> rootReplacedPaths = [];
  late final RootStackRouter rootRouter;

  @override
  RootStackRouter get root => rootRouter;
}

BeaconViewState _closedChildWithLineageParentState() {
  final base = beaconViewHarnessAuthorState(
    beaconId: _kChildRequestId,
  );
  return base.copyWith(
    beacon: base.beacon.copyWith(
      id: _kChildRequestId,
      title: 'Completed child request',
      status: BeaconStatus.closed,
      lineageParentBeaconId: _kParentRequestId,
    ),
  );
}

Future<void> _tapAppBarBack(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.arrow_back));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// GitHub #154 — Back from a completed child request must return to the parent
/// request opened from the nested card, not the My Work / Activity root list.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await registerBeaconViewHarnessGetIt();
  });

  tearDown(() async {
    await unregisterBeaconViewHarnessGetIt();
  });

  group('issue #154 back from completed child request', () {
    testWidgets(
      'back returns to lineage parent instead of My Work list',
      (tester) async {
        final router = _Issue154StackRouter();
        await pumpBeaconViewHarness(
          tester,
          size: kBeaconViewHarnessCompact,
          beaconState: _closedChildWithLineageParentState(),
          threadsState: beaconViewHarnessThreadsState(),
          router: router,
        );

        expect(router.canPop(), isFalse);

        await _tapAppBarBack(tester);

        expect(
          router.rootReplacedPaths,
          isNot(contains(kPathMyWork)),
          reason:
              'Back must not replacePath to the global My Work list when '
              'lineageParentBeaconId is set',
        );
        expect(
          router.rootReplacedPaths.any(
            (path) => path.contains(_kParentRequestId),
          ),
          isTrue,
          reason: 'Back should navigate to the parent request detail',
        );
      },
    );

    // Without a lineage parent the screen asks AppNavigator which Home tab
    // is active: Inbox (HomeTab.updates is the Inbox tab) and Network go to
    // their roots; every other tab, and an unknown one, goes to My Work.
    for (final (tab, path) in [
      (HomeTab.inbox, kPathInbox),
      (HomeTab.network, kPathNetwork),
      (HomeTab.constellation, kPathMyWork),
      (null, kPathMyWork),
    ]) {
      testWidgets('back without a lineage parent from the '
          '${tab?.name ?? 'unknown'} tab replaces the path with $path', (
        tester,
      ) async {
        final router = _Issue154StackRouter();
        final base = _closedChildWithLineageParentState();
        await pumpBeaconViewHarness(
          tester,
          size: kBeaconViewHarnessCompact,
          beaconState: base.copyWith(
            beacon: base.beacon.copyWith(lineageParentBeaconId: ''),
          ),
          threadsState: beaconViewHarnessThreadsState(),
          router: router,
        );
        final navigator = GetIt.I<AppNavigator>() as FakeAppNavigator
          ..homeTabIndex = tab == null ? null : HomeTabSpec.forTab(tab).index;

        await _tapAppBarBack(tester);

        expect(router.rootReplacedPaths, [path]);
        expect(navigator.intents, isEmpty);
      });
    }
  });
}
