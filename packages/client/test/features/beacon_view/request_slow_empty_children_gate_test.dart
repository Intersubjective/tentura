import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_child_group.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_page.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_summary.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_owner_summary.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/port/beacon_write_port.dart';
import 'package:tentura/domain/use_case/beacon_create_case.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/beacon_hierarchy_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_child_requests_section.dart';
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
  for (final hasChildren in [false, true]) {
    for (final slowGroup in BeaconHierarchyChildGroup.values) {
      testWidgets(
        'Request reveals the final ${hasChildren ? 'child list' : 'empty state'} only after a slow ${slowGroup.name} child read',
        (tester) async {
          final responses = {
            for (final group in BeaconHierarchyChildGroup.values)
              group: Completer<BeaconHierarchyPage>(),
          };
          final completedGroups = <BeaconHierarchyChildGroup>{};
          final requestedGroups = <BeaconHierarchyChildGroup>[];
          final hierarchy = (await tester.runAsync(
            () async => BeaconHierarchyCubit(
              beaconId: kBeaconViewHarnessBeaconId,
              hierarchyCase: buildBeaconHierarchyCaseForTest(
                FakeBeaconHierarchyRepositoryPort(
                  fetchChildrenHandler: ({required group, after}) {
                    requestedGroups.add(group);
                    return responses[group]!.future;
                  },
                ),
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

          final unfinishedFrames = <String>[];
          ({
            int gate,
            int bodies,
            int headers,
            int empty,
            int childTitles,
            int innerSpinners,
            int completed,
          })?
          firstRevealedFrame;
          var revealed = false;
          void inspectFrame() {
            final frame = (
              gate: _gateSpinners(),
              bodies: find.byType(BeaconNowSurface).evaluate().length,
              headers: find.text('Child requests').evaluate().length,
              empty: find.text('No child requests yet').evaluate().length,
              childTitles: find.text('Bring folding chairs').evaluate().length,
              innerSpinners: _childSpinners(),
              completed: completedGroups.length,
            );
            final pending = completedGroups.length != responses.length;
            // Check section indicators and bare headers directly, even if the
            // Request body is absent or the section moves outside that body.
            if (frame.innerSpinners > 0 ||
                (frame.headers > 0 &&
                    frame.empty == 0 &&
                    frame.childTitles == 0)) {
              unfinishedFrames.add('Unfinished child section: $frame');
            }
            if (frame.bodies > 0) {
              firstRevealedFrame ??= frame;
              revealed = true;
              if (pending ||
                  frame.gate != 0 ||
                  frame.bodies != 1 ||
                  frame.headers != 1 ||
                  frame.empty != (hasChildren ? 0 : 1) ||
                  frame.childTitles != (hasChildren ? 1 : 0) ||
                  frame.innerSpinners != 0) {
                unfinishedFrames.add('$frame');
              }
            } else if (revealed ||
                frame.gate != 1 ||
                frame.headers != 0 ||
                frame.empty != 0 ||
                frame.childTitles != 0 ||
                frame.innerSpinners != 0) {
              unfinishedFrames.add('$frame');
            }
            // A closed gate after the final response is valid while load() drains.
          }

          try {
            await tester.binding.setSurfaceSize(kBeaconViewHarnessExpanded);
            final load = hierarchy.load();
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
            // All other screen slices are ready. Each real hierarchy read has
            // its own response, so a later group cannot reuse the active result.
            await tester.pump(const Duration(milliseconds: 160));
            inspectFrame();
            for (final group in BeaconHierarchyChildGroup.values) {
              for (
                var frame = 0;
                frame < 30 && !requestedGroups.contains(group);
                frame++
              ) {
                await tester.pump();
                inspectFrame();
              }
              expect(
                requestedGroups,
                contains(group),
                reason: 'The screen must request the ${group.name} child group',
              );
              expect(responses[group]!.isCompleted, isFalse);
              // Exercise each group as the slow read, including finished/deleted
              // after the earlier groups have completed.
              final holdFrames = group == slowGroup ? 250 : 4;
              for (var frame = 0; frame < holdFrames; frame++) {
                await tester.pump(const Duration(milliseconds: 16));
                inspectFrame();
              }
              completedGroups.add(group);
              responses[group]!.complete(
                BeaconHierarchyPage(
                  summaries: [
                    if (hasChildren &&
                        group == BeaconHierarchyChildGroup.active)
                      BeaconHierarchySummary(
                        beaconId: 'child-chairs',
                        isTombstone: false,
                        title: 'Bring folding chairs',
                        status: BeaconStatus.open,
                        publishedAt: DateTime.utc(2026),
                        owner: const BeaconHierarchyOwnerSummary(
                          id: kBeaconViewHarnessAuthorId,
                          displayName: 'Author',
                        ),
                      ),
                  ],
                ),
              );
              // Flush response microtasks and inspect the very next rendered frame
              // without settling animations or awaiting the complete load.
              await tester.pump();
              inspectFrame();
            }
            for (var frame = 0; frame < 30; frame++) {
              await tester.pump();
              inspectFrame();
            }
            await load;
            expect(
              requestedGroups.toSet(),
              BeaconHierarchyChildGroup.values.toSet(),
            );
            expect(
              firstRevealedFrame,
              (
                gate: 0,
                bodies: 1,
                headers: 1,
                empty: hasChildren ? 0 : 1,
                childTitles: hasChildren ? 1 : 0,
                innerSpinners: 0,
                completed: BeaconHierarchyChildGroup.values.length,
              ),
              reason:
                  'The first revealed frame must contain the final child '
                  'state after every child-group read has completed',
            );
            expect(
              find.text('No child requests yet'),
              hasChildren ? findsNothing : findsOneWidget,
            );
            expect(
              find.text('Bring folding chairs'),
              hasChildren ? findsOneWidget : findsNothing,
            );
            expect(_gateSpinners(), 0);
            expect(_childSpinners(), 0);
            expect(
              unfinishedFrames,
              isEmpty,
              reason:
                  'Until all child responses arrive, only the gate spinner '
                  'may be visible. Every revealed frame must already contain '
                  'the final list or empty text, without an inner spinner or bare header.',
            );
          } finally {
            for (final response in responses.values) {
              if (!response.isCompleted) {
                response.complete(const BeaconHierarchyPage(summaries: []));
              }
            }
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.runAsync(hierarchy.close);
            final hostClosed = host.close();
            await tester.pump();
            await hostClosed;
          }
        },
        timeout: const Timeout(Duration(seconds: 30)),
      );
    }
  }
}
