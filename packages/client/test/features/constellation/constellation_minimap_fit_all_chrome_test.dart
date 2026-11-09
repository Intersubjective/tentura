@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/data/repository/constellation_repository.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_tap_resolver.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';
import 'fixtures/constellation_reference_fixture.dart';

const _toggle = Key('constellation.minimap.toggle');
const _map = Key('constellation.minimap');
const _phoneNarrow = Size(355, 670);

Map<String, dynamic> _bobWireResponse() {
  Map<String, dynamic> peer(String id, String displayName) => {
    '__typename': 'v2_ConstellationPeer',
    'id': id,
    'contactOnly': false,
    'displayName': displayName,
    'handle': null,
    'image': null,
    'isNew': false,
    'pinState': null,
    'presence': 'visible',
    'temporaryBeaconId': null,
    'bondContexts': <dynamic>[],
    'visible': true,
  };

  return {
    '__typename': 'query_root',
    'constellationField': {
      '__typename': 'v2_ConstellationField',
      'loadedAt': '2026-11-06T12:00:00.000Z',
      'context': '',
      'peersCapped': false,
      'requestsCapped': false,
      'directContactIds': ['anna', 'boris', 'dima', 'kira'],
      'peers': [
        peer('bob', 'Боб'),
        peer('anna', 'Анна'),
        peer('boris', 'Борис'),
        peer('dima', 'Дима'),
        peer('kira', 'Кира'),
      ],
      'edges': [
        for (final dst in ['anna', 'boris', 'dima', 'kira'])
          {
            '__typename': 'v2_ConstellationEdge',
            'src': 'bob',
            'dst': dst,
            'tier': 1,
          },
      ],
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
}

Future<ConstellationCubit> _loadBobCubitFromWire() async {
  late final ConstellationField mappedField;
  await withRemoteWire(
    {'ConstellationFieldFetch': _bobWireResponse()},
    [],
    (remote) async {
      mappedField = await ConstellationRepository(remote).fetch();
    },
  );
  final cubit = ConstellationCubit(
    case_: constellationCaseForField(mappedField),
    viewer: const Profile(id: 'bob', displayName: 'Боб'),
  );
  await cubit.stream.firstWhere((s) => s.field != null);
  return cubit;
}

Future<void> _pumpBobField(
  WidgetTester tester, {
  required Size size,
  required Locale locale,
}) async {
  final cubit = await _loadBobCubitFromWire();
  addTearDown(cubit.close);
  await pumpConstellationBody(
    tester,
    cubit,
    size: size,
    locale: locale,
    presentationFrameHolder: ConstellationPresentationFrameHolder(),
    disableAnimations: true,
    arrangeV2Enabled: true,
  );
  await tester.pumpAndSettle();
}

void main() {
  group('minimap chrome after fit-all (#1225 r2)', () {
    testWidgets(
      '375 RU wire: open fit-all hides toggle and minimap',
      (tester) async {
        await usePhoneSurface(tester);
        await _pumpBobField(
          tester,
          size: kPhoneSurface,
          locale: const Locale('ru'),
        );
        expect(find.byKey(_toggle), findsNothing);
        expect(find.byKey(_map), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '355×670 RU wire: open fit-all hides chrome',
      (tester) async {
        await tester.binding.setSurfaceSize(_phoneNarrow);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await _pumpBobField(
          tester,
          size: _phoneNarrow,
          locale: const Locale('ru'),
        );
        expect(find.byKey(_toggle), findsNothing);
        expect(find.byKey(_map), findsNothing);
      },
    );

    testWidgets(
      '375 RU wire: zoom in shows toggle; fit-all hides again',
      (tester) async {
        await usePhoneSurface(tester);
        final cubit = await _loadBobCubitFromWire();
        addTearDown(cubit.close);
        await pumpConstellationBody(
          tester,
          cubit,
          size: kPhoneSurface,
          presentationFrameHolder: ConstellationPresentationFrameHolder(),
          disableAnimations: true,
          arrangeV2Enabled: true,
        );
        await tester.pumpAndSettle();
        cubit.graphController.zoomBy(2.2);
        await tester.pumpAndSettle();
        expect(find.byKey(_toggle), findsOneWidget);
        await tester.tap(find.byKey(TestIds.key(TestIds.constellationFitAll)));
        await tester.pumpAndSettle();
        expect(find.byKey(_toggle), findsNothing);
        expect(find.byKey(_map), findsNothing);
      },
    );

    testWidgets(
      '375 RU: expand minimap, fit-all, chrome hides',
      (tester) async {
        await usePhoneSurface(tester);
        final cubit = await _loadBobCubitFromWire();
        addTearDown(cubit.close);
        await pumpConstellationBody(
          tester,
          cubit,
          size: kPhoneSurface,
          presentationFrameHolder: ConstellationPresentationFrameHolder(),
          disableAnimations: true,
          arrangeV2Enabled: true,
        );
        await tester.pumpAndSettle();
        cubit.graphController.zoomBy(3);
        await tester.pumpAndSettle();
        expect(find.byKey(_toggle), findsOneWidget);
        await tester.ensureVisible(find.byKey(_toggle));
        await tester.tap(find.byKey(_toggle));
        await tester.pumpAndSettle();
        expect(
          tester.widget<IconButton>(find.byKey(_toggle)).tooltip,
          'Скрыть миникарту',
        );
        await tester.tap(find.byKey(TestIds.key(TestIds.constellationFitAll)));
        await tester.pumpAndSettle();
        expect(find.byKey(_toggle), findsNothing);
        expect(find.byKey(_map), findsNothing);
      },
    );

    testWidgets(
      '375 RU: pan off-screen brings collapsed toggle back',
      (tester) async {
        await usePhoneSurface(tester);
        final cubit = await _loadBobCubitFromWire();
        addTearDown(cubit.close);
        await pumpConstellationBody(
          tester,
          cubit,
          size: kPhoneSurface,
          presentationFrameHolder: ConstellationPresentationFrameHolder(),
          disableAnimations: true,
          arrangeV2Enabled: true,
        );
        await tester.pumpAndSettle();
        expect(find.byKey(_toggle), findsNothing);
        final insets = cubit.fieldCameraViewportInsets(
          tester.element(find.byType(ConstellationBody)),
          contextPanelVisible: false,
        );
        cubit.graphController.jumpToPosition(
          const Offset(8000, 8000),
          viewportInsets: insets,
        );
        await tester.pumpAndSettle();
        expect(find.byKey(_toggle), findsOneWidget);
        expect(find.byKey(_map), findsNothing);
      },
    );

  });
}
