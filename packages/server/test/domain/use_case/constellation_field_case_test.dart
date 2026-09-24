import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/custom_types.dart';
import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/mappers/constellation_gql_maps.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_constellation_field.dart';
import 'package:tentura_server/consts/constellation_consts.dart';
import 'package:tentura_server/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura_server/domain/entity/constellation_field.dart';
import 'package:tentura_server/domain/entity/gql_public/image_public_record.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/constellation_field_repository_port.dart';
import 'package:tentura_server/domain/use_case/constellation_field_case.dart';
import 'package:tentura_server/env.dart';

void main() {
  late _RecordingRepository repository;
  late ConstellationFieldCase case_;

  setUp(() {
    repository = _RecordingRepository();
    case_ = ConstellationFieldCase(
      repository,
      env: Env(environment: Environment.test),
      logger: Logger('ConstellationFieldCaseTest'),
    );
  });

  test('blank viewer returns empty snapshot without IO', () async {
    final snapshot = await case_.load(viewerId: '  ', context: '');

    expect(snapshot.peers, isEmpty);
    expect(snapshot.edges, isEmpty);
    expect(snapshot.requests, isEmpty);
    expect(snapshot.peersCapped, isFalse);
    expect(snapshot.requestsCapped, isFalse);
    expect(repository.visibleGraphPeerCalls, 0);
    expect(repository.readSnapshotCalls, 0);
  });

  test('load delegates to readSnapshot FULL', () async {
    await case_.load(viewerId: 'Uviewer', context: 'ctx');
    expect(repository.readSnapshotCalls, 1);
    expect(repository.lastReadParams?.projection, ConstellationProjection.full);
  });

  test('ANCHORS readSnapshot skips automatic peer discovery', () async {
    await case_.readSnapshot(
      viewerId: 'Uviewer',
      context: 'ctx',
      params: (
        filters: const ConstellationFieldMembershipFilters(),
        projection: ConstellationProjection.anchors,
      ),
    );
    expect(repository.visibleGraphPeerCalls, 0);
    expect(repository.lastReadParams?.projection, ConstellationProjection.anchors);
  });

  test('peersCapped and requestsCapped reflect repository overflow', () async {
    repository.graphPeerIds = (
      ids: {for (var i = 0; i < kConstellationPeerCap; i++) 'Upeer$i'},
      capped: true,
    );
    repository.stubDiscoverableRequests = [
      for (var i = 0; i < kConstellationRequestCap + 1; i++)
        _request(id: 'Bpeer$i', authorId: 'Uauthor$i'),
    ];

    final snapshot = await case_.load(viewerId: 'Uviewer', context: '');

    expect(snapshot.peersCapped, isTrue);
    expect(snapshot.requestsCapped, isTrue);
    expect(snapshot.requests, hasLength(kConstellationRequestCap));
    expect(repository.readSnapshotCalls, 1);
  });

  test('ego own non-discoverable active request is present', () async {
    repository.stubOwnRequests = [
      _request(
        id: 'Bmine001',
        authorId: 'Uviewer',
        isMine: true,
      ),
    ];

    final snapshot = await case_.load(viewerId: 'Uviewer', context: '');

    expect(snapshot.requests.single.id, 'Bmine001');
    expect(snapshot.requests.single.isMine, isTrue);
  });

  test('peer non-discoverable request is absent from discoverable query', () async {
    repository.stubDiscoverableRequests = const [];

    final snapshot = await case_.load(viewerId: 'Uviewer', context: '');

    expect(snapshot.requests, isEmpty);
    expect(repository.lastDiscoverableCap, kConstellationRequestCap);
  });

  test('ego requests survive the peer-request cap', () async {
    repository.stubOwnRequests = [
      _request(id: 'Bego001', authorId: 'Uegozzz', isMine: true),
    ];
    repository.stubDiscoverableRequests = [
      for (var i = 0; i < kConstellationRequestCap + 1; i++)
        _request(id: 'Bpeer$i', authorId: 'Upeer${i.toString().padLeft(3, '0')}'),
    ];

    final snapshot = await case_.load(viewerId: 'Uegozzz', context: '');

    expect(snapshot.requestsCapped, isTrue);
    expect(snapshot.requests.any((r) => r.id == 'Bego001'), isTrue);
    expect(snapshot.requests, hasLength(kConstellationRequestCap + 1));
  });

  test('overflow shape keeps graph cap, edges inside graph, authors in peers',
      () async {
    final graphIds = {
      for (var i = 0; i < kConstellationPeerCap; i++)
        'Ugraph${i.toString().padLeft(3, '0')}',
    };
    repository.graphPeerIds = (ids: graphIds, capped: true);
    repository.stubDiscoverableRequests = [
      _request(id: 'Boutside', authorId: 'Uoutside999'),
    ];
    repository.stubTrustEdges = [
      ConstellationEdgeRecord(
        src: graphIds.first,
        dst: graphIds.last,
        tier: 1,
      ),
    ];
    repository.stubPeerProfiles = [
      for (final id in {...graphIds, 'Uoutside999'})
        ConstellationPeerRecord(id: id, displayName: id),
    ];

    final snapshot = await case_.load(viewerId: 'Uviewer', context: '');

    expect(snapshot.peersCapped, isTrue);
    expect(snapshot.peers.map((p) => p.id).toSet(), graphIds.union({'Uoutside999'}));
    expect(snapshot.peers.length, kConstellationPeerCap + 1);
    expect(
      snapshot.edges.every(
        (e) => graphIds.contains(e.src) && graphIds.contains(e.dst),
      ),
      isTrue,
    );
    expect(snapshot.requests.single.authorId, 'Uoutside999');
    expect(repository.lastTrustEdgeNodeIds, contains('Uviewer'));
    expect(repository.lastTrustEdgeNodeIds!.length, kConstellationPeerCap + 1);
  });

  test('containment: edge endpoints and request authors stay in ego union V',
      () async {
    const ego = 'Uviewer';
    const visible = {'UpeerA', 'UpeerB'};
    repository.graphPeerIds = (ids: visible, capped: false);
    repository.stubDiscoverableRequests = [
      _request(id: 'B1', authorId: 'UpeerA'),
    ];
    repository.stubTrustEdges = [
      const ConstellationEdgeRecord(src: ego, dst: 'UpeerA', tier: 1),
    ];

    final snapshot = await case_.load(viewerId: ego, context: '');

    final allowed = {ego, ...visible};
    for (final edge in snapshot.edges) {
      expect(allowed, contains(edge.src));
      expect(allowed, contains(edge.dst));
    }
    for (final request in snapshot.requests) {
      expect(allowed, contains(request.authorId));
    }
  });

  test('wire hygiene: serialized snapshot has no forbidden keys', () async {
    repository.graphPeerIds = (
      ids: {'UpeerA'},
      capped: false,
    );
    repository.stubOwnRequests = [
      _request(
        id: 'B1',
        authorId: 'Uviewer',
        isMine: true,
        coverThumb: ImagePublicRecord(
          id: 'img1',
          hash: 'h',
          height: 1,
          width: 1,
          authorId: 'Uviewer',
          createdAt: DateTime.utc(2026),
        ),
      ),
    ];
    repository.stubTrustEdges = [
      const ConstellationEdgeRecord(src: 'Uviewer', dst: 'UpeerA', tier: 2),
    ];
    repository.stubPeerProfiles = const [
      ConstellationPeerRecord(id: 'UpeerA', displayName: 'A'),
      ConstellationPeerRecord(id: 'Uviewer', displayName: 'Viewer'),
    ];

    final snapshot = await case_.load(viewerId: 'Uviewer', context: '');
    final wire = constellationFieldToGqlMap(snapshot);

    expect(_forbiddenWireKeys(wire), isEmpty);
  });

  group('GraphQL registration and auth', () {
    late QueryConstellationField query;

    setUp(() {
      query = QueryConstellationField(constellationFieldCase: case_);
    });

    test('constellationField is wired in _queries_all.dart', () {
      final source = File(
        'lib/api/controllers/graphql/query/_queries_all.dart',
      ).readAsStringSync();
      expect(source, contains('QueryConstellationField'));
      expect(source, contains('...QueryConstellationField().all'));
    });

    test('constellationField exposes the dedicated query field', () {
      expect(
        query.all.map((field) => field.name),
        contains('constellationField'),
      );
    });

    test('exposes no context argument in the schema', () {
      final argNames = query.constellationField.inputs.map((i) => i.name).toSet();
      expect(argNames, containsAll(['showClosed', 'participatedOnly', 'projection']));
      expect(argNames, isNot(contains('context')));
      expect(
        customTypes.any((type) => type.name == 'ConstellationField'),
        isTrue,
      );
    });

    test('rejects missing JWT', () {
      expect(
        () => query.constellationField.resolve!(null, {}),
        throwsA(isA<UnauthorizedException>()),
      );
    });

    test('uses viewer identity only from JWT', () async {
      await query.constellationField.resolve!(null, {
        kGlobalInputQueryJwt: const JwtEntity(sub: 'Uviewer'),
        'showClosed': false,
        'participatedOnly': false,
        'projection': 'FULL',
      });

      expect(repository.lastViewerId, 'Uviewer');
      expect(repository.lastContext, kConstellationContext);
    });
  });
}

ConstellationRequestRecord _request({
  required String id,
  required String authorId,
  bool isMine = false,
  ImagePublicRecord? coverThumb,
}) => ConstellationRequestRecord(
  id: id,
  authorId: authorId,
  title: 'title',
  status: 0,
  needs: const ['need-a'],
  primaryNeedSlug: 'need-a',
  hasCoordinates: false,
  isMine: isMine,
  viewerHasActiveHelpOffer: false,
  viewerIsRoomParticipant: false,
  viewerHasForwardEdge: false,
  helpOfferCount: 0,
  coverThumb: coverThumb,
);

final _forbiddenKeyPattern = RegExp(
  r'score|weight|_mr$|meritrank|rank',
  caseSensitive: false,
);

Set<String> _forbiddenWireKeys(Object? value, [String prefix = '']) {
  final hits = <String>{};
  if (value is Map) {
    for (final entry in value.entries) {
      final key = entry.key.toString();
      final path = prefix.isEmpty ? key : '$prefix.$key';
      if (_forbiddenKeyPattern.hasMatch(key)) {
        hits.add(path);
      }
      hits.addAll(_forbiddenWireKeys(entry.value, path));
    }
  } else if (value is List) {
    for (var i = 0; i < value.length; i++) {
      hits.addAll(_forbiddenWireKeys(value[i], '$prefix[$i]'));
    }
  }
  return hits;
}

final class _RecordingRepository implements ConstellationFieldRepositoryPort {
  ({Set<String> ids, bool capped}) graphPeerIds = (
    ids: const {},
    capped: false,
  );
  List<ConstellationRequestRecord> stubOwnRequests = const [];
  List<ConstellationRequestRecord> stubDiscoverableRequests = const [];
  List<ConstellationEdgeRecord> stubTrustEdges = const [];
  List<ConstellationPeerRecord> stubPeerProfiles = const [];

  int visibleGraphPeerCalls = 0;
  int readSnapshotCalls = 0;
  ConstellationFieldReadParams? lastReadParams;
  String? lastViewerId;
  String? lastContext;
  int? lastDiscoverableCap;
  Set<String>? lastTrustEdgeNodeIds;

  @override
  Future<ConstellationFieldSnapshot> readSnapshot({
    required String viewerId,
    required String context,
    required ConstellationFieldReadParams params,
  }) async {
    readSnapshotCalls++;
    lastViewerId = viewerId;
    lastContext = context;
    lastReadParams = params;
    if (params.projection == ConstellationProjection.anchors) {
      return ConstellationFieldSnapshot(
        loadedAt: DateTime.now().toUtc(),
        context: context,
        peers: const [],
        edges: const [],
        requests: const [],
        peersCapped: false,
        requestsCapped: false,
        anchorProjection: ConstellationAnchorProjection.empty,
      );
    }
    return loadViaLegacyQueries(viewerId: viewerId, context: context);
  }

  Future<ConstellationFieldSnapshot> loadViaLegacyQueries({
    required String viewerId,
    required String context,
  }) async {
    final graphPeers = await visibleGraphPeerIds(
      viewerId: viewerId,
      context: context,
      cap: kConstellationPeerCap,
    );
    final ownRequests = await this.ownRequests(viewerId: viewerId);
    final peerRequestsRaw = await discoverableRequests(
      viewerId: viewerId,
      context: context,
      cap: kConstellationRequestCap,
    );
    final requestsCapped = peerRequestsRaw.length > kConstellationRequestCap;
    final peerRequests = requestsCapped
        ? peerRequestsRaw.sublist(0, kConstellationRequestCap)
        : peerRequestsRaw;
    final requests = [...ownRequests, ...peerRequests];
    final edgeNodeIds = {...graphPeers.ids, viewerId};
    final edges = await trustEdges(
      viewerId: viewerId,
      context: context,
      nodeIds: edgeNodeIds,
    );
    final profileIds = {...graphPeers.ids};
    for (final request in requests) {
      profileIds.add(request.authorId);
    }
    final peers = await peerProfiles(ids: profileIds);
    return ConstellationFieldSnapshot(
      loadedAt: DateTime.now().toUtc(),
      context: context,
      peers: peers,
      edges: edges,
      requests: requests,
      peersCapped: graphPeers.capped,
      requestsCapped: requestsCapped,
    );
  }

  @override
  Future<({Set<String> ids, bool capped})> visibleGraphPeerIds({
    required String viewerId,
    required String context,
    required int cap,
  }) async {
    visibleGraphPeerCalls++;
    lastViewerId = viewerId;
    lastContext = context;
    return graphPeerIds;
  }

  @override
  Future<List<ConstellationEdgeRecord>> trustEdges({
    required String viewerId,
    required String context,
    required Set<String> nodeIds,
  }) async {
    lastViewerId = viewerId;
    lastContext = context;
    lastTrustEdgeNodeIds = nodeIds;
    return stubTrustEdges;
  }

  @override
  Future<List<ConstellationRequestRecord>> ownRequests({
    required String viewerId,
  }) async {
    lastViewerId = viewerId;
    return stubOwnRequests;
  }

  @override
  Future<List<ConstellationRequestRecord>> discoverableRequests({
    required String viewerId,
    required String context,
    required int cap,
  }) async {
    lastViewerId = viewerId;
    lastContext = context;
    lastDiscoverableCap = cap;
    return stubDiscoverableRequests;
  }

  @override
  Future<List<ConstellationPeerRecord>> peerProfiles({
    required Set<String> ids,
  }) async {
    return [
      for (final peer in stubPeerProfiles)
        if (ids.contains(peer.id)) peer,
    ];
  }
}
