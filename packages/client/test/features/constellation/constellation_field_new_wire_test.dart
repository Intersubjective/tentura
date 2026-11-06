// #898 real-path: Field fetch maps isNew; acknowledge mutation uses peerIds.

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/constellation/data/model/constellation_field_mapper.dart';
import 'package:tentura/features/constellation/data/repository/constellation_new_people_repository.dart';
import 'package:tentura/features/constellation/data/repository/constellation_repository.dart';
import 'package:tentura/features/constellation/data/gql/_g/constellation_field_fetch.data.gql.dart';

import '../../support/remote_wire_harness.dart';

void main() {
  test('ConstellationFieldFetch maps peer isNew from the wire', () async {
    final wire = {
      '__typename': 'query_root',
      'constellationField': {
        '__typename': 'v2_ConstellationField',
        'loadedAt': '2026-11-04T12:00:00.000Z',
        'context': '',
        'peersCapped': false,
        'requestsCapped': false,
        'directContactIds': ['peer-new'],
        'peers': [
          {
            '__typename': 'v2_ConstellationPeer',
            'id': 'peer-new',
            'contactOnly': false,
            'displayName': 'Новый человек с очень длинным именем для телефона',
            'handle': null,
            'image': null,
            'isNew': true,
            'pinState': null,
            'presence': 'visible',
            'temporaryBeaconId': null,
            'bondContexts': <dynamic>[],
            'visible': true,
          },
          {
            '__typename': 'v2_ConstellationPeer',
            'id': 'peer-old',
            'contactOnly': false,
            'displayName': 'Old',
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
        'posts': [
          {
            '__typename': 'v2_ConstellationPost',
            'id': 'post-unread',
            'authorId': 'author',
            'rootExcerpt': 'Unread excerpt',
            'lastActivityAt': '2026-11-04T12:00:00.000Z',
            'expiresAt': null,
            'status': 0,
            'isPinned': false,
            'hiddenReachCount': 0,
            'has_unread': true,
          },
        ],
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

    final mapped = mapConstellationFieldFromFieldFetch(
      GConstellationFieldFetchData.fromJson(wire)!.constellationField,
    );
    final byId = {for (final p in mapped.peers) p.id: p.isNew};
    expect(byId['peer-new'], isTrue);
    expect(byId['peer-old'], isFalse);
    expect(mapped.posts.single.hasUnread, isTrue);
  });

  test(
    'ConstellationFieldFetch maps long RU displayName for arrangement label math',
    () async {
      final wire = {
        '__typename': 'query_root',
        'constellationField': {
          '__typename': 'v2_ConstellationField',
          'loadedAt': '2026-11-04T12:00:00.000Z',
          'context': '',
          'peersCapped': false,
          'requestsCapped': false,
          'directContactIds': <String>[],
          'peers': [
            {
              '__typename': 'v2_ConstellationPeer',
              'id': 'peer-long',
              'contactOnly': false,
              'displayName':
                  'Новый человек с очень длинным именем для телефона и раскладки меток на карте поля',
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

      final mapped = mapConstellationFieldFromFieldFetch(
        GConstellationFieldFetchData.fromJson(wire)!.constellationField,
      );
      final name = mapped.peers.single.displayName;
      expect(name, isNotNull);
      expect(name!.length, greaterThan(60));
    },
  );

  test(
    'ConstellationFieldFetch (wire → repository) maps ego-only field',
    () async {
      final wireResponse = {
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

      final sent = <WireSent>[];
      await withRemoteWire(
        {'ConstellationFieldFetch': wireResponse},
        sent,
        (remote) async {
          final field = await ConstellationRepository(remote).fetch();
          expect(sent.single.operationName, 'ConstellationFieldFetch');
          expect(field.peers.single.id, 'ego');
          expect(field.peers.single.displayName, isNotNull);
          expect(field.edges, isEmpty);
          expect(field.requests, isEmpty);
        },
      );
    },
  );

  test(
    'ConstellationFieldFetch (#1035 U1) maps Anna,Kira,Vera,Boris from the wire',
    () async {
      final wireResponse = {
        '__typename': 'query_root',
        'constellationField': {
          '__typename': 'v2_ConstellationField',
          'loadedAt': '2026-11-06T12:00:00.000Z',
          'context': '',
          'peersCapped': false,
          'requestsCapped': false,
          'directContactIds': ['kira', 'vera', 'boris'],
          'peers': [
            for (final id in ['anna', 'kira', 'vera', 'boris'])
              {
                '__typename': 'v2_ConstellationPeer',
                'id': id,
                'contactOnly': false,
                'displayName': switch (id) {
                  'anna' =>
                    'Анна с очень длинным отображаемым именем для миникарты поля',
                  'kira' => 'Кира',
                  'vera' => 'Вера',
                  'boris' => 'Борис',
                  _ => id,
                },
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
          'edges': [
            for (final dst in ['kira', 'vera', 'boris'])
              {
                '__typename': 'v2_ConstellationTrustEdge',
                'src': 'anna',
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

      final sent = <WireSent>[];
      await withRemoteWire(
        {'ConstellationFieldFetch': wireResponse},
        sent,
        (remote) async {
          final field = await ConstellationRepository(remote).fetch();
          expect(
            sent.map((s) => s.operationName),
            contains('ConstellationFieldFetch'),
          );
          expect(
            field.peers.map((p) => p.id).toSet(),
            {'anna', 'kira', 'vera', 'boris'},
          );
          expect(field.edges, hasLength(3));
        },
      );

      final mapped = mapConstellationFieldFromFieldFetch(
        GConstellationFieldFetchData.fromJson(wireResponse)!.constellationField,
      );
      expect(mapped.peers, hasLength(4));
      expect(
        {for (final p in mapped.peers) p.id},
        {'anna', 'kira', 'vera', 'boris'},
      );
    },
  );

  test('ConstellationAcknowledgeNew sends peerIds on the wire', () async {
    final sent = <WireSent>[];
    await withRemoteWire(
      {
        'ConstellationAcknowledgeNew': {
          '__typename': 'mutation_root',
          'constellationAcknowledgeNew': true,
        },
      },
      sent,
      (remote) async {
        await ConstellationNewPeopleRepository(remote).acknowledgeNew([
          'peer-a',
          'peer-b',
        ]);
        expect(sent.single.operationName, 'ConstellationAcknowledgeNew');
        expect(sent.single.variables['peerIds'], ['peer-a', 'peer-b']);
      },
    );
  });
}
