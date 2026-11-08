import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_child_group.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_page.dart';

import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/port/beacon_write_port.dart';
import 'package:tentura/domain/use_case/beacon_create_case.dart';
import 'package:tentura/features/beacon/data/repository/beacon_hierarchy_repository.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/beacon_hierarchy_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_state.dart';
import 'package:tentura/features/beacon_view/ui/screen/beacon_view_screen.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_now_surface.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/first_load_gate.dart';

import '../../domain/use_case/fake_beacon_hierarchy_ports.dart';
import '../../support/people_tags_widget_harness.dart';
import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';
import 'beacon_view_screen_harness.dart';

class _NoopBeaconWritePort implements BeaconWritePort {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoopImageRepository implements ImageRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DelayedThreadsCubit extends Cubit<ThreadsState> implements ThreadsCubit {
  _DelayedThreadsCubit(super.initialState);

  void emitState(ThreadsState value) => emit(value);

  @override
  Future<void> fetch({bool silent = false}) async {}
}

int _gateSpinners() => find
    .descendant(
      of: find.byType(TenturaFirstLoadGate),
      matching: find.byType(TenturaCircularProgress),
    )
    .evaluate()
    .where((element) {
      var inContent = false;
      element.visitAncestorElements((ancestor) {
        if (ancestor.widget is TenturaFirstLoadGate) return false;
        if (ancestor.widget is Visibility) inContent = true;
        return true;
      });
      return !inContent;
    })
    .length;

Future<BeaconHierarchyCubit> _hierarchyWithImmediateChildren(
  WidgetTester tester,
  String beaconId,
) async {
  final port = FakeBeaconHierarchyRepositoryPort(
    childrenByGroup: {
      for (final group in BeaconHierarchyChildGroup.values)
        group: const BeaconHierarchyPage(summaries: []),
    },
  );
  final cubit = BeaconHierarchyCubit(
    beaconId: beaconId,
    hierarchyCase: buildBeaconHierarchyCaseForTest(
      port,
      createCase: BeaconCreateCase(_NoopBeaconWritePort(), _NoopImageRepository()),
      beacons: _NoopBeaconWritePort(),
      commandStore: InMemoryBeaconChildCommandStore(),
    ),
  );
  await tester.runAsync(cubit.load);
  addTearDown(() => tester.runAsync(cubit.close));
  return cubit;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Request reveals on 1280×800 before the gate timeout when hierarchy starts in scope',
    (tester) async {
      final hierarchy =
          await _hierarchyWithImmediateChildren(tester, kBeaconViewHarnessBeaconId);
      await registerBeaconViewHarnessGetIt();
      addTearDown(unregisterBeaconViewHarnessGetIt);

      await pumpBeaconViewHarness(
        tester,
        size: const Size(1280, 800),
        beaconState: beaconViewHarnessAuthorState(),
        threadsState: beaconViewHarnessThreadsState(),
        hierarchyCubit: hierarchy,
        viewTab: 'now',
      );

      var revealed = false;
      for (var ms = 0; ms < 500; ms += 16) {
        await tester.pump(const Duration(milliseconds: 16));
        if (find.byType(BeaconNowSurface).evaluate().isNotEmpty) {
          revealed = true;
          break;
        }
      }
      expect(revealed, isTrue);
      expect(_gateSpinners(), 0);
      expect(find.byKey(beaconSplitChatHeaderKey), findsOneWidget);
    },
  );

  for (final tab in ['plan', 'people']) {
    testWidgets(
      'Request on ?tab=$tab at 1280×800 reveals before timeout once hierarchy loads from scope',
      (tester) async {
        final response = Completer<BeaconHierarchyPage>();
        final port = FakeBeaconHierarchyRepositoryPort(
          fetchChildrenHandler: ({required group, after}) => response.future,
        );
        final hierarchy = BeaconHierarchyCubit(
          beaconId: kBeaconViewHarnessBeaconId,
          hierarchyCase: buildBeaconHierarchyCaseForTest(
            port,
            createCase: BeaconCreateCase(
              _NoopBeaconWritePort(),
              _NoopImageRepository(),
            ),
            beacons: _NoopBeaconWritePort(),
            commandStore: InMemoryBeaconChildCommandStore(),
          ),
        );
        final hierarchyLoad = hierarchy.load();
        addTearDown(() => tester.runAsync(hierarchy.close));
        await pumpBeaconViewHarness(
          tester,
          size: const Size(1280, 800),
          beaconState: beaconViewHarnessAuthorState(),
          threadsState: beaconViewHarnessThreadsState(),
          hierarchyCubit: hierarchy,
          viewTab: tab,
          plan: tab == 'plan' ? kBeaconViewHarnessOneStepPlan : null,
          afterGetItRegistered: tab == 'people' ? registerEmptyPeopleTags : null,
        );

        await tester.pump(const Duration(milliseconds: 100));
        expect(_gateSpinners(), 1);
        response.complete(const BeaconHierarchyPage(summaries: []));
        await tester.runAsync(() => hierarchyLoad);
        var elapsedMs = 0;
        var revealed = false;
        for (elapsedMs = 0; elapsedMs < 500; elapsedMs += 16) {
          await tester.pump(const Duration(milliseconds: 16));
          if (_gateSpinners() == 0) {
            revealed = true;
            break;
          }
        }
        expect(revealed, isTrue);
        expect(elapsedMs, lessThan(500));
      },
    );
  }

  testWidgets(
    'wide Request waits for threads before reveal so split layout is chosen first',
    (tester) async {
      final hierarchy =
          await _hierarchyWithImmediateChildren(tester, kBeaconViewHarnessBeaconId);
      final threads = _DelayedThreadsCubit(
        beaconViewHarnessThreadsState().copyWith(status: const StateIsLoading()),
      );
      await registerBeaconViewHarnessGetIt();
      addTearDown(unregisterBeaconViewHarnessGetIt);

      await tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('en'),
          home: StackRouterScope(
            controller: BeaconViewHarnessRouter(),
            stateHash: 0,
            child: BeaconViewResizableMediaQuery(
              size: const Size(1280, 800),
              child: buildBeaconViewHarnessWidget(
                beaconState: beaconViewHarnessAuthorState(),
                threadsState: beaconViewHarnessThreadsState(),
                threadsCubit: threads,
                hierarchyCubit: hierarchy,
                viewTab: 'now',
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(_gateSpinners(), 1);
      expect(find.byKey(beaconSplitChatHeaderKey), findsNothing);

      threads.emitState(beaconViewHarnessThreadsState());
      var revealedSplit = false;
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (_gateSpinners() == 0 &&
            find.byKey(beaconSplitChatHeaderKey).evaluate().isNotEmpty) {
          revealedSplit = true;
          break;
        }
      }
      expect(revealedSplit, isTrue);
    },
  );

  testWidgets(
    '375×667 RU Request reveals without gate timeout when hierarchy is ready',
    (tester) async {
      await usePhoneSurface(tester);
      final hierarchy =
          await _hierarchyWithImmediateChildren(tester, kBeaconViewHarnessBeaconId);
      await registerBeaconViewHarnessGetIt();
      addTearDown(unregisterBeaconViewHarnessGetIt);

      await pumpBeaconViewHarness(
        tester,
        size: kPhoneSurface,
        locale: const Locale('ru'),
        beaconState: beaconViewHarnessAuthorState(),
        threadsState: beaconViewHarnessThreadsState(),
        hierarchyCubit: hierarchy,
        viewTab: 'now',
      );

      var revealed = false;
      for (var ms = 0; ms < 500; ms += 16) {
        await tester.pump(const Duration(milliseconds: 16));
        if (_gateSpinners() == 0) {
          revealed = true;
          break;
        }
      }
      expect(revealed, isTrue);
    },
  );

  testWidgets(
    'wire harness hierarchy reads release the Request gate before timeout',
    (tester) async {
      const emptyChildren = {
        '__typename': 'query_root',
        'beaconChildren': {
          '__typename': 'v2_BeaconHierarchyPage',
          'nextCursor': null,
          'summaries': <Map<String, dynamic>>[],
        },
      };
      await withRemoteWire(
        {
          'BeaconHierarchyCapabilities': {
            '__typename': 'query_root',
            'beaconHierarchyCapabilities': {
              '__typename': 'v2_BeaconHierarchyCapabilities',
              'canListChildren': true,
              'canCreateChild': true,
              'denialCode': null,
            },
          },
          'BeaconChildren': emptyChildren,
        },
        [],
        (remote) async {
          final hierarchy = BeaconHierarchyCubit(
            beaconId: kBeaconViewHarnessBeaconId,
            hierarchyCase: buildBeaconHierarchyCaseForTest(
              BeaconHierarchyRepository(remote),
              createCase: BeaconCreateCase(
                _NoopBeaconWritePort(),
                _NoopImageRepository(),
              ),
              beacons: _NoopBeaconWritePort(),
              commandStore: InMemoryBeaconChildCommandStore(),
            ),
          );
          await tester.runAsync(hierarchy.load);
          addTearDown(() => tester.runAsync(hierarchy.close));
          await registerBeaconViewHarnessGetIt();
          addTearDown(unregisterBeaconViewHarnessGetIt);

          await pumpBeaconViewHarness(
            tester,
            size: const Size(1280, 800),
            beaconState: beaconViewHarnessAuthorState(),
            threadsState: beaconViewHarnessThreadsState(),
            hierarchyCubit: hierarchy,
            viewTab: 'now',
          );

          var elapsedMs = 0;
          var revealed = false;
          for (elapsedMs = 0; elapsedMs < 2000; elapsedMs += 16) {
            await tester.pump(const Duration(milliseconds: 16));
            if (_gateSpinners() == 0 &&
                find.byKey(beaconSplitChatHeaderKey).evaluate().isNotEmpty) {
              revealed = true;
              break;
            }
          }
          expect(revealed, isTrue);
          expect(elapsedMs, lessThan(2500));
        },
      );
    },
  );
}
