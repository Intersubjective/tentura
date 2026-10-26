import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:get_it/get_it.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/lazy_write_notice.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_selection_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/graph/domain/use_case/graph_trust_write_case.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../../support/add_to_tag_sheet_probe.dart';
import '../../support/fake_people_tags_repository.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import 'fixtures/constellation_layout_history_harness.dart';

// The selection bar offers every bulk action at once (#642): «Gather»,
// «Add to tag…», «Tidy up», «Arrange in a sector» and «Unpin». Each one is a
// single user action on the whole selection: one batch to the server, one
// step to undo.

class _StubContextCubit extends Cubit<GraphPersonContextState>
    implements GraphPersonContextCubit {
  _StubContextCubit() : super(const GraphPersonContextState());

  @override
  Stream<LazyWriteNotice> get lazyWriteNotices => const Stream.empty();

  @override
  Future<void> retryTrust([GraphTrustRevert? revert]) async {}

  @override
  final void Function(Profile profile)? onProfilePatched = null;

  @override
  void selectProfile(Profile profile, {required bool intentional}) {}

  @override
  void dismiss() {}

  @override
  Future<void> trustSelected() async {}

  @override
  Future<void> untrustSelected() async {}

  @override
  void clearSelection() {}
}

ConstellationAnchorTarget _person(String id) =>
    ConstellationAnchorTarget.person(id);

Map<String, Offset?> _positions(ConstellationCubit cubit) => {
  for (final id in ['p1', 'p2', 'p3', 'p4'])
    id: cubit.graphController.getPositionOrNullForId('fp:$id'),
};

/// Free people laid on top of each other, so Tidy up has something to do.
class _OverlappingFreePeople implements SceneLayoutAlgorithm {
  _OverlappingFreePeople(this.before);
  final Map<String, Offset?> before;

  @override
  Stream<GraphLayoutFrame> layout(GraphLayoutRequest request) async* {
    final ego = Offset(
      request.canvasSize.width / 2,
      request.canvasSize.height / 2,
    );
    yield GraphLayoutFrame(
      ticket: request.ticket,
      sequence: 0,
      isTerminal: true,
      positions: {
        for (final id in request.nodeIds)
          id: switch (id) {
            'fp:p3' => ScenePoint(x: ego.dx - 10, y: ego.dy - 340),
            'fp:p4' => ScenePoint(x: ego.dx + 10, y: ego.dy - 340),
            _ => ScenePoint(
              x: before[id.replaceFirst('fp:', '')]?.dx ?? ego.dx,
              y: before[id.replaceFirst('fp:', '')]?.dy ?? ego.dy,
            ),
          },
      },
    );
  }
}

Future<ConstellationSelectionCubit> _mount(
  WidgetTester tester,
  ConstellationCubit cubit,
) async {
  final selection = ConstellationSelectionCubit();
  addTearDown(selection.close);
  await tester.binding.setSurfaceSize(const Size(1200, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: TenturaResponsiveScope(
        child: MultiBlocProvider(
          providers: [
            BlocProvider<ConstellationCubit>.value(value: cubit),
            BlocProvider<ConstellationSelectionCubit>.value(value: selection),
            BlocProvider<GraphPersonContextCubit>(
              create: (_) => _StubContextCubit(),
            ),
            BlocProvider<ScreenCubit>(
              create: (_) => ScreenCubit(FakeUiEffectPort()),
            ),
          ],
          child: Scaffold(
            body: ConstellationBody(
              legendExpanded: false,
              onToggleLegend: () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
  return selection;
}

Future<void> _tap(WidgetTester tester, String label) async {
  final action = find.text(label);
  expect(
    action,
    findsOneWidget,
    reason: 'the selection bar offers $label',
  );
  await tester.ensureVisible(action);
  await tester.tap(action);
  await tester.pumpAndSettle();
}

void main() {
  late PeopleTagsTestRig rig;

  setUp(() async {
    rig = await PeopleTagsTestRig.create(addToTagProbeRepository('p1'));
    GetIt.I.registerSingleton<PeopleTagsCase>(rig.peopleTags);
  });

  tearDown(() async {
    await GetIt.I.reset();
    await rig.dispose();
  });

  group('selection bar bulk actions', () {
    testWidgets(
      'Add to tag on four selected people makes one apply call naming all four',
      (tester) async {
        final server = LayoutHistoryServer();
        final h = (await tester.runAsync(() => layoutHistoryHarness(server)))!;
        final selection = await _mount(tester, h.cubit);
        selection.addAll([
          for (final id in ['p1', 'p2', 'p3', 'p4']) _person(id),
        ]);
        await tester.pumpAndSettle();

        await _tap(tester, 'Add to tag…');
        expect(
          find.text('+ Tag'),
          findsOneWidget,
          reason: 'the tag sheet opened',
        );
        await tester.tap(find.widgetWithText(CheckboxListTile, 'Climbers'));
        await tester.pump();
        // Closing the sheet sends the batch.
        await tester.tapAt(const Offset(5, 5));
        await tester.pumpAndSettle();

        expect(rig.repository.appliedOps, hasLength(1));
        expect(
          rig.repository.appliedOps.single.map(
            (o) => (o.tagId, o.personId, o.add),
          ),
          unorderedEquals([
            for (final id in ['p1', 'p2', 'p3', 'p4']) ('Tb', id, true),
          ]),
        );
      },
    );

    testWidgets(
      'Tidy up on a selection moves only the selected people',
      (tester) async {
        final server = LayoutHistoryServer();
        final h = (await tester.runAsync(() => layoutHistoryHarness(server)))!;
        final selection = await _mount(tester, h.cubit);
        h.cubit.requestConstellationLayoutForTest(
          algorithm: _OverlappingFreePeople(_positions(h.cubit)),
        );
        await tester.pumpAndSettle();
        final before = _positions(h.cubit);
        selection.addAll([_person('p3')]);
        await tester.pumpAndSettle();

        await _tap(tester, 'Tidy up');

        final after = _positions(h.cubit);
        expect(after['p3'], isNot(before['p3']), reason: 'the selected moved');
        expect(after['p4'], before['p4'], reason: 'the unselected stays');
        expect(server.batches, isEmpty, reason: 'tidying writes no pins');
      },
    );

    testWidgets(
      'Unpin on a selection unpins its pinned people in one batch and one undo',
      (tester) async {
        final server = LayoutHistoryServer();
        final h = (await tester.runAsync(() => layoutHistoryHarness(server)))!;
        final selection = await _mount(tester, h.cubit);
        final pinned = Map.of(server.anchors);
        // p3 is selected too but was never pinned.
        selection.addAll([_person('p1'), _person('p2'), _person('p3')]);
        await tester.pumpAndSettle();

        await _tap(tester, 'Unpin');
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pumpAndSettle();

        expect(server.batches, hasLength(1));
        expect(
          server.batches.single.map((op) => (op['kind'], op['targetId'])),
          unorderedEquals([('DELETE', 'p1'), ('DELETE', 'p2')]),
        );
        expect(server.anchors, isEmpty);

        final undone = await tester.runAsync(h.cubit.undoArrangement);
        await tester.pumpAndSettle();

        expect(undone, isTrue);
        expect(server.anchors.keys.toSet(), pinned.keys.toSet());
        expect(
          h.cubit.canUndoArrangement,
          isFalse,
          reason: 'one undo took back the whole unpin',
        );
      },
    );

    testWidgets(
      'Arrange in a sector on a selection places only the selected people',
      (tester) async {
        final server = LayoutHistoryServer();
        final h = (await tester.runAsync(() => layoutHistoryHarness(server)))!;
        final selection = await _mount(tester, h.cubit);
        final pinnedBefore = Map.of(server.anchors);
        selection.addAll([_person('p3'), _person('p4')]);
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const Key('constellation.selection.arrange')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('constellation.selection.sector_apply')),
        );
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pumpAndSettle();

        expect(server.batches, hasLength(1));
        expect(
          server.batches.single.map((op) => op['targetId']),
          unorderedEquals(['p3', 'p4']),
        );
        for (final entry in pinnedBefore.entries) {
          expect(
            server.anchors[entry.key],
            entry.value,
            reason: '${entry.key.id} is not part of the selection',
          );
        }
      },
    );
  });
}
