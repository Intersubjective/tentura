// QA #938 round: tab reset, toolbar top, hint vs camera, overflow label.

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:tentura/app/router/home_tab_branches.dart';
import 'package:tentura/features/graph/domain/entity/edge_details.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/constellation/data/repository/constellation_repository.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_selection_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_camera_controls.dart';
import 'package:tentura/features/home/ui/widget/home_tab_transition_listener.dart';
import 'package:tentura/ui/l10n/l10n_ru.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';
import 'fixtures/constellation_field_test_harness.dart';
import 'fixtures/constellation_reference_fixture.dart';

final _egoOnlyWire = {
  '__typename': 'query_root',
  'constellationField': {
    '__typename': 'v2_ConstellationField',
    'loadedAt': '2026-11-06T12:00:00.000Z',
    'context': '',
    'peersCapped': false,
    'requestsCapped': false,
    'directContactIds': <dynamic>[],
    'peers': [
      {
        '__typename': 'v2_ConstellationPeer',
        'id': 'ego',
        'contactOnly': false,
        'displayName': 'Ego',
        'handle': null,
        'image': null,
        'isNew': false,
        'pinState': null,
        'presence': 'visible',
        'temporaryBeaconId': null,
        'bondContexts': <dynamic>[],
        'visible': true,
      },
    ],
    'edges': <dynamic>[],
    'requests': <dynamic>[],
    'posts': <dynamic>[],
    'memberWebs': <dynamic>[],
    'anchorProjection': {
      '__typename': 'v2_ConstellationAnchorProjection',
      'revision': '0',
      'anchors': <dynamic>[],
      'pinnedPeers': <dynamic>[],
      'pinnedRequests': <dynamic>[],
      'supportPeers': <dynamic>[],
      'supportEdges': <dynamic>[],
      'serverFilteredBeaconIds': <dynamic>[],
      'serverFilteredBeaconCount': 0,
    },
  },
};

void main() {
  testWidgets('re-entering the Field tab exits Arranging (onEnter)', (
    tester,
  ) async {
    final selection = ConstellationSelectionCubit()..enterArranging();
    addTearDown(selection.close);
    final fieldIndex = HomeTabSpec.forTab(HomeTab.constellation).index;
    final workIndex = HomeTabSpec.forTab(HomeTab.work).index;
    final tabs = _FakeTabsRouter(fieldIndex);

    await tester.pumpWidget(
      HomeTabTransitionListener(
        tabsRouter: tabs,
        tab: HomeTab.constellation,
        onLeave: selection.exitArranging,
        onEnter: selection.exitArranging,
        child: const SizedBox(),
      ),
    );
    expect(selection.state.arranging, isTrue);

    tabs.setActiveIndex(workIndex);
    await tester.pump();
    expect(selection.state.arranging, isFalse);

    selection.enterArranging();
    tabs.setActiveIndex(fieldIndex);
    await tester.pump();
    expect(selection.state.arranging, isFalse);
  });

  testWidgets(
    'Arranging toolbar sits in top chrome above the map at 375 RU',
    (tester) async {
      await usePhoneSurface(tester);
      final cubit = await loadReferenceCubit();
      addTearDown(cubit.close);

      await pumpConstellationBody(
        tester,
        cubit,
        arrangeV2Enabled: true,
      );
      tester.constellationSelectionUnderTest().enterArranging();
      await tester.pumpAndSettle();

      final toolbar = find.byKey(const Key('constellation.arranging.toolbar'));
      expect(toolbar, findsOneWidget);
      final graph = find.byType(GraphView<NodeDetails, EdgeDetails>);
      expect(
        find.descendant(of: graph, matching: toolbar),
        findsNothing,
        reason: 'toolbar is in top chrome, not on the map stack',
      );
      expect(
        find.byKey(const Key('constellation.arranging.hint')),
        findsOneWidget,
      );
    },
  );

  testWidgets('hold-hint OK clears the camera column at 375 RU', (
    tester,
  ) async {
    await usePhoneSurface(tester);
    final cubit = await loadReferenceCubit();
    addTearDown(cubit.close);

    await pumpConstellationBody(
      tester,
      cubit,
      arrangeV2Enabled: true,
      stabilizeFieldChrome: false,
    );
    await tester.pumpAndSettle();

    final hint = find.byKey(const Key('constellation.field_hold_hint'));
    expect(hint, findsOneWidget);
    final ok = find.descendant(
      of: hint,
      matching: find.widgetWithText(TextButton, L10nRu().buttonOk),
    );
    final fit = find.byKey(TestIds.key(TestIds.constellationFitAll));
    expect(fit, findsOneWidget);

    final okRect = tester.getRect(ok);
    final fitRect = tester.getRect(fit);
    expect(
      okRect.right,
      lessThan(fitRect.left - 4),
      reason: 'OK stays left of the camera column',
    );
    expect(
      okRect.bottom,
      greaterThan(fitRect.bottom + 4),
      reason: 'hold hint sits below the camera stack',
    );
  });

  testWidgets('⋯ overflow uses non-Arranging semantics', (tester) async {
    await usePhoneSurface(tester);
    final cubit = await loadReferenceCubit();
    addTearDown(cubit.close);

    await pumpConstellationBody(
      tester,
      cubit,
      arrangeV2Enabled: true,
    );
    tester.constellationSelectionUnderTest().enterArranging();
    await tester.pumpAndSettle();

    final more = find.byKey(const Key('constellation.arranging.more'));
    final button = tester.widget<IconButton>(more);
    expect(
      button.tooltip,
      L10nRu().constellationArrangingMoreActions,
    );
    expect(
      (button.icon as Icon).semanticLabel,
      L10nRu().constellationArrangingMoreActions,
    );
  });

  testWidgets('camera Arrange hides while already Arranging', (tester) async {
    await usePhoneSurface(tester);
    final cubit = await loadReferenceCubit();
    addTearDown(cubit.close);

    await pumpConstellationBody(
      tester,
      cubit,
      arrangeV2Enabled: true,
    );
    tester.constellationSelectionUnderTest().enterArranging();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('constellation.camera.arrange')), findsNothing);
    expect(find.byType(ConstellationCameraControls), findsOneWidget);
  });

  test('wire field load then enterArranging via selection cubit', () async {
    late ConstellationField field;
    final sent = <WireSent>[];
    await withRemoteWire(
      {'ConstellationFieldFetch': _egoOnlyWire},
      sent,
      (remote) async {
        field = await ConstellationRepository(remote).fetch();
        expect(sent.single.operationName, 'ConstellationFieldFetch');
      },
    );
    final cubit = await loadReferenceCubit(field: field);
    addTearDown(cubit.close);
    final selection = ConstellationSelectionCubit();
    addTearDown(selection.close);
    expect(cubit.canArrange, isFalse);
    selection.enterArranging();
    expect(selection.state.arranging, isTrue);
    selection.exitArranging();
    expect(selection.state.arranging, isFalse);
  });
}

class _FakeTabsRouter extends Fake with ChangeNotifier implements TabsRouter {
  _FakeTabsRouter(this._index);

  int _index;

  @override
  int get activeIndex => _index;

  @override
  void setActiveIndex(int value, {bool notify = true}) {
    _index = value;
    if (notify) notifyListeners();
  }

}
