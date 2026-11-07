// Refs #1047, #1048, #1062 — Field arranging chrome gating and empty-field UI.

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:tentura/app/router/home_tab_branches.dart';
import 'package:tentura/features/constellation/data/gql/_g/constellation_field_fetch.data.gql.dart';
import 'package:tentura/features/constellation/data/model/constellation_field_mapper.dart';
import 'package:tentura/features/constellation/data/repository/constellation_repository.dart';
import 'package:tentura/features/constellation/domain/constellation_visibility.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_selection_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_arranging_toolbar.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_no_contacts.dart';
import 'package:tentura/features/graph/domain/entity/edge_details.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/home/ui/widget/home_tab_transition_listener.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';
import 'fixtures/constellation_arrange_harness.dart';
import 'fixtures/constellation_field_test_harness.dart';
import 'fixtures/constellation_reference_fixture.dart';

const _egoOnlyWire = {
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
        'displayName':
            'Очень длинное отображаемое имя для проверки легенды поля на телефоне',
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

Future<ConstellationField> _egoOnlyFieldFromWire() async {
  final sent = <WireSent>[];
  late ConstellationField field;
  await withRemoteWire(
    {'ConstellationFieldFetch': _egoOnlyWire},
    sent,
    (remote) async {
      field = await ConstellationRepository(remote).fetch();
      expect(sent.single.operationName, 'ConstellationFieldFetch');
    },
  );
  return field;
}

Future<void> _waitForVisibilityRestored(ConstellationCubit cubit) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!cubit.state.visibilityRestored && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(cubit.state.visibilityRestored, isTrue);
}

Future<ConstellationCubit> _loadField(ConstellationField field) async {
  final cubit = ConstellationCubit(
    case_: constellationCaseForField(field),
    viewer: kRefEgo,
  );
  await cubit.stream.firstWhere((s) => s.status is StateIsSuccess);
  await _waitForVisibilityRestored(cubit);
  return cubit;
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

void main() {
  test('ego-only wire field has no contacts for the viewer', () async {
    final mapped = mapConstellationFieldFromFieldFetch(
      GConstellationFieldFetchData.fromJson(_egoOnlyWire)!.constellationField,
    );
    expect(constellationFieldHasNoContacts(mapped, 'ego'), isTrue);
    final fromRepo = await _egoOnlyFieldFromWire();
    expect(constellationFieldHasNoContacts(fromRepo, 'ego'), isTrue);
  });

  test('canArrange is false with only the viewer on the field', () async {
    final cubit = await _loadField(
      await _egoOnlyFieldFromWire(),
    );
    addTearDown(cubit.close);
    expect(cubit.canArrange, isFalse);
  });

  test('canArrange is true with an own Request but no contacts', () async {
    final field = (await _egoOnlyFieldFromWire()).copyWith(
      requests: const [
        ConstellationRequest(
          id: 'req-mine',
          authorId: 'ego',
          title: 'Свой запрос для проверки расположения на пустом поле',
          status: 0,
          isMine: true,
        ),
      ],
    );
    final cubit = await _loadField(field);
    addTearDown(cubit.close);
    expect(cubit.canArrange, isTrue);
  });

  testWidgets('empty Field RU phone: invite banner only in top chrome', (
    tester,
  ) async {
    await usePhoneSurface(tester);
    final cubit = await _loadField(await _egoOnlyFieldFromWire());
    addTearDown(cubit.close);
    final l10n = lookupL10n(const Locale('ru'));

    await pumpConstellationBody(
      tester,
      cubit,
      locale: const Locale('ru'),
      arrangeV2Enabled: true,
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(ConstellationNoContactsBanner.bannerKey), findsOneWidget);
    expect(find.byKey(const Key('constellation.show')), findsNothing);
    expect(
      find.byKey(const Key('constellation.field_hold_hint')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('constellation.camera.arrange')),
      findsNothing,
    );

    final bodySize = tester.getSize(find.byType(ConstellationBody));
    final graphSize = tester.getSize(
      find.byType(GraphView<NodeDetails, EdgeDetails>),
    );
    expect(
      graphSize.height / bodySize.height,
      greaterThanOrEqualTo(0.55),
    );

    expect(l10n.constellationArrangeEntry, isNotEmpty);
  });

  testWidgets('one contact shows chips, tag row and Arrange FAB', (
    tester,
  ) async {
    await usePhoneSurface(tester);
    final cubit = await loadReferenceCubit(
      field: constellationReferenceField(egoRequestCount: 0),
    );
    addTearDown(cubit.close);
    await pumpConstellationBody(
      tester,
      cubit,
      locale: const Locale('ru'),
      arrangeV2Enabled: true,
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('constellation.show')), findsOneWidget);
    expect(
      find.byKey(const Key('constellation.camera.arrange')),
      findsOneWidget,
    );

    final selection = tester.constellationSelectionUnderTest();
    await tester.tap(find.byKey(const Key('constellation.camera.arrange')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ConstellationArrangingToolbar), findsOneWidget);
    expect(selection.state.arranging, isTrue);
  });

  testWidgets('hiding every visibility layer exits Arranging', (tester) async {
    final cubit = await loadReferenceCubit(
      field: constellationReferenceField(egoRequestCount: 0),
    );
    addTearDown(cubit.close);
    final selection = ConstellationSelectionCubit()..enterArranging();
    addTearDown(selection.close);

    await pumpArrangeBody(
      tester,
      cubit,
      arrangeV2Enabled: true,
      selection: selection,
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(selection.state.arranging, isTrue);

    cubit.setVisibility(
      const ConstellationVisibility(
        requests: false,
        posts: false,
        firstDegree: false,
        secondDegree: false,
        furtherDegrees: false,
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(selection.state.arranging, isFalse);
    expect(
      find.byKey(const Key('constellation.camera.arrange')),
      findsNothing,
    );
  });

  testWidgets('stored hold-hint dismissal shows no hint frame', (tester) async {
    final cubit = await loadReferenceCubit(
      field: constellationReferenceField(egoRequestCount: 0),
    );
    addTearDown(cubit.close);
    cubit.dismissFieldHoldHint();

    await pumpConstellationBody(
      tester,
      cubit,
      locale: const Locale('ru'),
      arrangeV2Enabled: true,
    );
    await tester.pump();
    expect(
      find.byKey(const Key('constellation.field_hold_hint')),
      findsNothing,
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      find.byKey(const Key('constellation.field_hold_hint')),
      findsNothing,
    );
  });

  testWidgets('leaving the Field tab exits Arranging', (tester) async {
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
        child: const SizedBox(),
      ),
    );

    tabs.setActiveIndex(workIndex);
    await tester.pump();
    expect(selection.state.arranging, isFalse);
  });
}
