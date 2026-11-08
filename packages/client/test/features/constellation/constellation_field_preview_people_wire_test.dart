@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/data/model/constellation_field_mapper.dart';
import 'package:tentura/features/constellation/data/repository/constellation_repository.dart';
import 'package:tentura/features/constellation/data/gql/_g/constellation_field_fetch.data.gql.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_post_preview_sheet.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/constellation_store_fixture.dart';
import '../../support/people_tags_widget_harness.dart';
import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';

const _viewer = Profile(id: 'Uviewer000001', displayName: 'Viewer');
const _amy = 'Uamy000000001';
const _bob = 'Ubob000000001';
const _post = 'Ppost00000001';

Map<String, dynamic> _peer(String id, String displayName) => {
  '__typename': 'v2_ConstellationPeer',
  'id': id,
  'pinState': null,
  'contactOnly': false,
  'presence': 'visible',
  'temporaryBeaconId': null,
  'bondContexts': <dynamic>[],
  'displayName': displayName,
  'handle': null,
  'isNew': false,
  'image': null,
};

Map<String, dynamic> _memberWeb(String personId, String state) => {
  '__typename': 'v2_ConstellationMemberWeb',
  'beaconId': _post,
  'personId': personId,
  'state': state,
};

Map<String, dynamic> _fieldWire() => {
  '__typename': 'query_root',
  'constellationField': {
    '__typename': 'v2_ConstellationField',
    'loadedAt': DateTime.utc(2026, 11, 8).toIso8601String(),
    'context': '',
    'peersCapped': false,
    'requestsCapped': false,
    'directContactIds': <dynamic>[],
    'peers': [
      _peer(_amy, 'Amy Longdisplayname Example'),
      _peer(_bob, 'Bob Longdisplayname Example'),
    ],
    'edges': [
      {
        '__typename': 'v2_ConstellationEdge',
        'src': _viewer.id,
        'dst': _amy,
        'tier': 1,
      },
      {
        '__typename': 'v2_ConstellationEdge',
        'src': _viewer.id,
        'dst': _bob,
        'tier': 1,
      },
    ],
    'requests': <dynamic>[],
    'posts': [
      {
        '__typename': 'v2_ConstellationPost',
        'id': _post,
        'authorId': _amy,
        'lastActivityAt': DateTime.utc(2026, 11, 8).toIso8601String(),
        'expiresAt': null,
        'status': 0,
        'rootExcerpt': 'Need a drill',
        'isPinned': false,
        'hiddenReachCount': 1,
        'has_unread': false,
      },
    ],
    'memberWebs': [
      _memberWeb(_amy, 'INSIDE'),
      _memberWeb(_bob, 'FORWARDED'),
    ],
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
  testWidgets('wire Field payload renders post preview participant stacks', (
    tester,
  ) async {
    await usePhoneSurface(tester);
    final sent = <WireSent>[];
    late ConstellationCubit cubit;
    final wire = _fieldWire();
    await tester.runAsync(
      () => withRemoteWire(
        {'ConstellationFieldFetch': wire},
        sent,
        (remote) async {
          final store = ConstellationStoreFixture(
            ConstellationRepository(remote),
            accountId: _viewer.id,
          );
          cubit = store.createCubit(viewer: _viewer);
          await store.ready();
          await cubit.load().timeout(const Duration(seconds: 15));
        },
      ),
    );
    final mapped = mapConstellationFieldFromFieldFetch(
      GConstellationFieldFetchData.fromJson(wire)!.constellationField,
    );
    expect(cubit.state.field!.memberWebs, mapped.memberWebs);
    cubit.selectRequest(_post);
    await tester.pumpPeopleTagsWidget(
      MaterialApp(
        locale: const Locale('ru'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: TenturaResponsiveScope(
          child: BlocProvider.value(
            value: cubit,
            child: ConstellationPostPreviewSheet(
              post: cubit.state.field!.posts.single,
              authorDisplayName: 'Amy',
              onOpen: () {},
              onClose: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('constellation.field_preview.participants')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('constellation.field_preview.forwarded')),
      findsOneWidget,
    );
    expect(find.text('+1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
