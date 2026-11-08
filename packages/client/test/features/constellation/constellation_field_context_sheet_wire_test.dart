@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/data/repository/constellation_repository.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/graph/ui/widget/graph_person_context_panel.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';
import 'fixtures/constellation_reference_fixture.dart';

Map<String, dynamic> _annaWireField() {
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
      'loadedAt': '2026-11-08T12:00:00.000Z',
      'context': '',
      'peersCapped': false,
      'requestsCapped': false,
      'directContactIds': ['kira'],
      'peers': [
        peer('anna', 'Анна с длинным отображаемым именем для карты поля'),
        peer('kira', 'Кира'),
      ],
      'edges': [
        {
          '__typename': 'v2_ConstellationEdge',
          'src': 'anna',
          'dst': 'kira',
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

Future<ConstellationCubit> _loadAnnaCubitFromWire() async {
  late final ConstellationField mappedField;
  await withRemoteWire(
    {'ConstellationFieldFetch': _annaWireField()},
    [],
    (remote) async {
      mappedField = await ConstellationRepository(remote).fetch();
    },
  );
  final cubit = ConstellationCubit(
    case_: constellationCaseForField(mappedField),
    viewer: const Profile(id: 'anna', displayName: 'Анна'),
  );
  await cubit.stream.firstWhere((s) => s.field != null);
  return cubit;
}

void main() {
  testWidgets(
    '375×667 RU: wire field selects a person into the map-aware sheet (#974)',
    (tester) async {
      await usePhoneSurface(tester);
      final cubit = await _loadAnnaCubitFromWire();
      addTearDown(cubit.close);
      await pumpConstellationBody(
        tester,
        cubit,
        size: kPhoneSurface,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(TestIds.key(TestIds.graphNode('kira'))));
      await tester.pumpAndSettle();

      expect(cubit.state.selectedPersonId, 'kira');
      expect(
        find.byKey(const Key('field.context_sheet.handle')),
        findsOneWidget,
      );
      expect(find.byType(GraphPersonContextPanel), findsOneWidget);
      expect(find.text('Кира'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
}
