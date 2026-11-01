import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_child_group.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_page.dart';

import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/port/beacon_write_port.dart';
import 'package:tentura/domain/use_case/beacon_create_case.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/beacon_hierarchy_cubit.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_child_requests_section.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_now_surface.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/first_load_gate.dart';

import '../../domain/use_case/fake_beacon_hierarchy_ports.dart';
import 'beacon_view_screen_harness.dart';

class _UnusedBeaconWritePort implements BeaconWritePort {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedImageRepository implements ImageRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// The gate keeps screen content mounted under Visibility. Count only its
// overlay spinner, excluding any indicators belonging to that content.
int _gateSpinners() => find
    .descendant(
      of: find.byType(TenturaFirstLoadGate),
      matching: find.byType(CircularProgressIndicator),
    )
    .evaluate()
    .where((element) {
      var insideContent = false;
      element.visitAncestorElements((ancestor) {
        if (ancestor.widget is TenturaFirstLoadGate) return false;
        if (ancestor.widget is Visibility) insideContent = true;
        return true;
      });
      return !insideContent;
    })
    .length;

int _childSpinners() => find
    .descendant(
      of: find.byType(BeaconChildRequestsSection),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is CircularProgressIndicator ||
            widget is CupertinoActivityIndicator,
      ),
    )
    .evaluate()
    .length;

void main() {
  testWidgets(
    'Request waits for empty child results before revealing content and stays visible during a child refresh',
    (tester) async {
      final initialResponse = Completer<BeaconHierarchyPage>();
      final refreshResponse = Completer<BeaconHierarchyPage>();
      final requestedGroups = <BeaconHierarchyChildGroup>[];
      var refreshing = false;
      final port = FakeBeaconHierarchyRepositoryPort(
        fetchChildrenHandler: ({required group, after}) {
          requestedGroups.add(group);
          return refreshing ? refreshResponse.future : initialResponse.future;
        },
      );
      final hierarchy = (await tester.runAsync(
        () async => BeaconHierarchyCubit(
          beaconId: kBeaconViewHarnessBeaconId,
          hierarchyCase: buildBeaconHierarchyCaseForTest(
            port,
            createCase: BeaconCreateCase(
              _UnusedBeaconWritePort(),
              _UnusedImageRepository(),
            ),
            beacons: _UnusedBeaconWritePort(),
            commandStore: InMemoryBeaconChildCommandStore(),
          ),
        ),
      ))!;
      final host = beaconViewHarnessHost();
      await registerBeaconViewHarnessGetIt();
      addTearDown(unregisterBeaconViewHarnessGetIt);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      Future<void> dispose() async {
        if (!initialResponse.isCompleted) {
          initialResponse.complete(const BeaconHierarchyPage(summaries: []));
        }
        if (!refreshResponse.isCompleted) {
          refreshResponse.complete(const BeaconHierarchyPage(summaries: []));
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(hierarchy.close);
        final hostClosed = host.close();
        await tester.pump();
        await hostClosed;
      }

      try {
        await tester.binding.setSurfaceSize(kBeaconViewHarnessExpanded);
        // The route scope starts this load in the app; the harness supplies
        // ready Request/discussion data while the real hierarchy load is held.
        final initialLoad = hierarchy.load();
        await tester.pumpWidget(
          StackRouterScope(
            controller: BeaconViewHarnessRouter(),
            stateHash: 0,
            child: MaterialApp(
              theme: TenturaTheme.light(),
              localizationsDelegates: L10n.localizationsDelegates,
              supportedLocales: L10n.supportedLocales,
              locale: const Locale('en'),
              home: BeaconViewResizableMediaQuery(
                size: kBeaconViewHarnessExpanded,
                child: buildBeaconViewHarnessWidget(
                  beaconState: beaconViewHarnessAuthorState(),
                  threadsState: beaconViewHarnessThreadsState(),
                  hierarchyCubit: hierarchy,
                  host: host,
                  viewTab: 'now',
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(requestedGroups, contains(BeaconHierarchyChildGroup.active));
        expect(initialResponse.isCompleted, isFalse);
        // Check the held response before advancing to the reveal phase.
        expect(
          (
            gateSpinners: _gateSpinners(),
            bodies: find.byType(BeaconNowSurface).evaluate().length,
            emptyLabels: find.text('No child requests yet').evaluate().length,
            childSpinners: _childSpinners(),
          ),
          (gateSpinners: 1, bodies: 0, emptyLabels: 0, childSpinners: 0),
          reason:
              'The Request must stay hidden while its child results are pending',
        );

        initialResponse.complete(const BeaconHierarchyPage(summaries: []));
        // Do not await initialLoad or settle animations before inspecting the
        // reveal: either could skip a frame with unfinished child content.
        var revealed = false;
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          final frame = (
            gateSpinners: _gateSpinners(),
            bodies: find.byType(BeaconNowSurface).evaluate().length,
            emptyLabels: find.text('No child requests yet').evaluate().length,
            childSpinners: _childSpinners(),
          );
          if (frame.bodies > 0) {
            // This is the first revealed frame, captured without another pump.
            expect(
              frame,
              (gateSpinners: 0, bodies: 1, emptyLabels: 1, childSpinners: 0),
              reason:
                  'The first revealed frame must already show the child empty state without a section spinner',
            );
            revealed = true;
            break;
          }
        }
        expect(revealed, isTrue, reason: 'Empty results must release the gate');
        await initialLoad;

        refreshing = true;
        final readsBeforeRefresh = requestedGroups.length;
        final refresh = hierarchy.refreshGroup(
          BeaconHierarchyChildGroup.active,
        );
        await tester.pump();
        expect(requestedGroups.length, greaterThan(readsBeforeRefresh));
        expect(refreshResponse.isCompleted, isFalse);
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.byType(BeaconNowSurface), findsOneWidget);
        expect(
          _gateSpinners(),
          0,
          reason: 'Child refresh must keep the body visible',
        );
        refreshResponse.complete(const BeaconHierarchyPage(summaries: []));
        await refresh;
        await tester.pump();
        expect(find.text('No child requests yet'), findsOneWidget);
        expect(_childSpinners(), 0);
        expect(_gateSpinners(), 0);
      } finally {
        await dispose();
      }
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
