import 'dart:math' as math;

import 'package:ferry/ferry.dart'
    show Client, DataSource, FetchPolicy, Link, NextLink, OperationType;
import 'package:flutter_test/flutter_test.dart';
import 'package:gql_exec/gql_exec.dart' show Request, Response;
import 'package:tentura/data/gql/_g/schema.schema.gql.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/features/constellation/data/gql/_g/constellation_field_fetch.req.gql.dart';
import 'package:tentura/features/constellation/data/model/constellation_field_mapper.dart';
import 'package:tentura/features/constellation/domain/constellation_anchor_composition.dart';
import 'package:tentura/features/constellation/domain/constellation_consts.dart';
import 'package:tentura/features/constellation/domain/constellation_density.dart';
import 'package:tentura/features/constellation/domain/constellation_filters.dart';
import 'package:tentura/features/constellation/domain/constellation_layout.dart';
import 'package:tentura/features/constellation/domain/constellation_pin_position.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

class _FakeLink extends Link {
  _FakeLink(this.response);

  final Response response;

  @override
  Stream<Response> request(Request request, [NextLink? forward]) =>
      Stream.value(response);
}

const _ego = 'U_ego';
const _spacing = 16.0;
final _asOf = DateTime.utc(2026, 10, 3, 12);

/// Inside the 72 h active window.
final _fresh = _asOf.subtract(const Duration(hours: 71));

/// Past the 72 h active window.
final _stale = _asOf.subtract(const Duration(hours: 73));

ConstellationPost _post(
  String id, {
  String authorId = 'peer-a',
  String rootExcerpt = 'Who has a ladder?',
  DateTime? lastActivityAt,
  bool isPinned = false,
}) => ConstellationPost(
  id: id,
  authorId: authorId,
  rootExcerpt: rootExcerpt,
  lastActivityAt: lastActivityAt ?? _fresh,
  isPinned: isPinned,
);

ConstellationRequest _request() => ConstellationRequest(
  id: 'req-1',
  authorId: 'peer-a',
  title: 'Move a sofa',
  status: 0,
);

ConstellationMemberWeb _web(
  String postId,
  String personId, [
  ConstellationMemberWebState state = ConstellationMemberWebState.inside,
]) => ConstellationMemberWeb(beaconId: postId, personId: personId, state: state);

ConstellationField _field({
  List<ConstellationRequest> requests = const [],
  List<ConstellationPost> posts = const [],
  List<ConstellationMemberWeb> memberWebs = const [],
  ConstellationAnchorProjection? projection,
}) => ConstellationField(
  loadedAt: _asOf,
  context: 'ctx',
  peers: [
    ConstellationPerson(id: 'peer-a'),
    ConstellationPerson(id: 'peer-b'),
  ],
  edges: [
    ConstellationTrustEdgeEntity(src: _ego, dst: 'peer-a', tier: 1),
    ConstellationTrustEdgeEntity(src: _ego, dst: 'peer-b', tier: 1),
  ],
  requests: requests,
  posts: posts,
  memberWebs: memberWebs,
  anchorProjection: projection,
);

ConstellationAnchorProjection _projectionPinning(String beaconId) =>
    ConstellationAnchorProjection(
      revision: ConstellationAnchorRevision.zero,
      anchors: [
        ConstellationAnchor(
          target: ConstellationAnchorTarget.beacon(beaconId),
          position: ConstellationAnchorPosition(
            xUnits: 1,
            yUnits: 1,
            coordinateSpaceVersion: kConstellationCoordinateSpaceVersionV1,
          ),
          revision: ConstellationAnchorRevision.zero,
          placedAt: DateTime.utc(2026, 10, 1),
        ),
      ],
      pinnedPeers: const [],
      pinnedRequests: const [],
      supportPeers: const [],
      supportEdges: const [],
      serverFilteredBeaconIds: const [],
      serverFilteredBeaconCount: 0,
    );

ConstellationComposedPresentation _compose(
  ConstellationField field, {
  ConstellationLabelBudget labelBudget = (perPerson: 3, total: 150),
  List<ConstellationMemberWeb> selectedRequestWebs = const [],
}) => composeConstellationPresentation(
  viewerId: _ego,
  field: field,
  localFilters: const (
    capabilitySlugs: {},
    location: LocationFilter.any,
    timing: TimingFilterAny(),
    includeUnspecified: true,
  ),
  asOfUtc: _asOf,
  labelBudget: labelBudget,
  selectedRequestWebs: selectedRequestWebs,
);

ConstellationPlacedLayoutInput _layoutInput(
  ConstellationComposedPresentation composed,
) => layoutInputFromComposition(
  viewerId: _ego,
  composition: composed,
  labelPlan: composed.labelPlan,
  nodeSizes: const {
    'peer-a': (width: 40.0, height: 40.0),
    'peer-b': (width: 40.0, height: 40.0),
    'post-1': (width: 36.0, height: 36.0),
    'req-1': (width: 36.0, height: 36.0),
  },
  spacing: _spacing,
);

double _distance(ConstellationPoint a, ConstellationPoint b) =>
    math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));

void main() {
  group('Post wire mapping', () {
    test('maps posts, member webs and caps from the field query', () async {
      final client = Client(
        link: _FakeLink(
          Response(
            data: {
              '__typename': 'query_root',
              'constellationField': {
                '__typename': 'v2_ConstellationField',
                'loadedAt': '2026-09-09T12:00:00.000Z',
                'context': '',
                'peersCapped': true,
                'requestsCapped': true,
                'peers': [],
                'edges': [],
                'requests': [],
                'posts': [
                  {
                    '__typename': 'v2_ConstellationPost',
                    'id': 'post-1',
                    'authorId': 'peer-a',
                    'lastActivityAt': '2026-09-09T10:00:00.000Z',
                    'rootExcerpt': 'Who has a ladder?',
                    'isPinned': true,
                    'hiddenReachCount': 3,
                  },
                ],
                'memberWebs': [
                  {
                    '__typename': 'v2_ConstellationMemberWeb',
                    'beaconId': 'post-1',
                    'personId': 'peer-b',
                    'state': 'FORWARDED',
                  },
                  {
                    '__typename': 'v2_ConstellationMemberWeb',
                    'beaconId': 'post-1',
                    'personId': 'peer-c',
                    'state': 'INSIDE',
                  },
                ],
                'anchorProjection': {
                  '__typename': 'v2_ConstellationAnchorProjection',
                  'revision': '0',
                  'anchors': [],
                  'pinnedPeers': [],
                  'pinnedRequests': [],
                  'supportPeers': [],
                  'supportEdges': [],
                  'serverFilteredBeaconIds': [],
                  'serverFilteredBeaconCount': 0,
                },
              },
            },
            response: {},
          ),
        ),
        defaultFetchPolicies: {
          OperationType.query: FetchPolicy.NoCache,
          OperationType.mutation: FetchPolicy.NoCache,
        },
      );
      final response = await client
          .request(
            GConstellationFieldFetchReq((b) {
              b.vars
                ..showClosed = false
                ..participatedOnly = false
                ..projection = Gv2_ConstellationProjection.FULL;
            }),
          )
          .firstWhere((event) => event.dataSource == DataSource.Link);
      final field = mapConstellationFieldFromFieldFetch(
        response.dataOrThrow(label: 'test').constellationField,
      );

      expect(field.peersCapped, isTrue);
      expect(field.requestsCapped, isTrue);
      final post = field.posts.single;
      expect(post.id, 'post-1');
      expect(post.authorId, 'peer-a');
      expect(post.rootExcerpt, 'Who has a ladder?');
      expect(post.lastActivityAt, DateTime.utc(2026, 9, 9, 10));
      expect(post.isPinned, isTrue);
      expect(post.hiddenReachCount, 3);
      expect(field.memberWebs.map((w) => (w.beaconId, w.personId, w.state)), [
        ('post-1', 'peer-b', ConstellationMemberWebState.forwarded),
        ('post-1', 'peer-c', ConstellationMemberWebState.inside),
      ]);
    });
  });

  group('Post composition', () {
    test('a Post inside the active window is drawn alongside Requests', () {
      final composed = _compose(
        _field(requests: [_request()], posts: [_post('post-1')]),
      );
      expect(composed.labelPlan.drawnRequestIds, containsAll(['req-1', 'post-1']));
      expect(composed.eligibleRequestIds, containsAll(['req-1', 'post-1']));
    });

    test('a composed Post node carries its root excerpt and the Post glyph', () {
      final composed = _compose(
        _field(posts: [_post('post-1', rootExcerpt: 'Who has a ladder?')]),
      );
      final node = composed.beaconNodes.singleWhere((n) => n.id == 'post-1');
      expect(node.kind, BeaconKind.post);
      expect(node.label, 'Who has a ladder?');
      expect(node.glyph, FieldBeaconGlyph.post);
      expect(node.hasStatusMarker, isFalse);
    });

    test('Requests and Posts share one per-author label budget', () {
      final composed = _compose(
        _field(requests: [_request()], posts: [_post('post-1')]),
        labelBudget: (perPerson: 1, total: 1),
      );
      expect(composed.labelPlan.drawnRequestIds, hasLength(1));
      expect(composed.labelPlan.overflowHiddenCountByAuthor['peer-a'], 1);
    });

    test('Request nodes are unchanged when Posts are present', () {
      final without = _compose(_field(requests: [_request()]));
      final mixed = _compose(
        _field(requests: [_request()], posts: [_post('post-1')]),
      );
      final request = mixed.beaconNodes.singleWhere((n) => n.id == 'req-1');
      expect(request.kind, BeaconKind.request);
      expect(request.label, 'Move a sofa');
      expect(request.glyph, FieldBeaconGlyph.request);
      expect(request.hasStatusMarker, isTrue);
      expect(without.beaconNodes.map((n) => n.id), ['req-1']);
    });

    test('a Post past the active window and not pinned is absent', () {
      final composed = _compose(
        _field(posts: [_post('post-old', lastActivityAt: _stale)]),
      );
      expect(composed.labelPlan.drawnRequestIds, isNot(contains('post-old')));
      expect(composed.beaconNodes.map((n) => n.id), isNot(contains('post-old')));
      expect(composed.dormantBeaconIds, isNot(contains('post-old')));
    });

    test('a pinned Post past the active window is dormant and keeps its anchor',
        () {
      final composed = _compose(
        _field(
          posts: [_post('post-old', lastActivityAt: _stale, isPinned: true)],
          projection: _projectionPinning('post-old'),
        ),
      );
      expect(composed.dormantBeaconIds, contains('post-old'));
      expect(composed.eligibleRequestIds, contains('post-old'));
      expect(composed.beaconNodes.map((n) => n.id), contains('post-old'));
      expect(composed.labelPlan.drawnRequestIds, isNot(contains('post-old')));

      final input = _layoutInput(composed);
      expect(input.pinnedRequestIds, contains('post-old'));
      final layout = computeConstellationPlacedLayout(input: input);
      expect(
        layout.positions['post-old'],
        constellationV1AnchorToPoint(input.anchorByNodeId['post-old']!),
      );
    });
  });

  group('FieldBeaconNode', () {
    test('a Post node is labelled with the root excerpt and has no status marker',
        () {
      final node = FieldBeaconNode(
        post: _post('post-1', rootExcerpt: 'Who has a ladder?'),
      );
      expect(node.kind, BeaconKind.post);
      expect(node.label, 'Who has a ladder?');
      expect(node.id, 'post-1');
      expect(node.userId, 'peer-a');
      expect(node.glyph, FieldBeaconGlyph.post);
      expect(node.hasStatusMarker, isFalse);
    });

    test('a Request node keeps its title as label and its status marker', () {
      final node = FieldBeaconNode(request: _request());
      expect(node.kind, BeaconKind.request);
      expect(node.label, 'Move a sofa');
      expect(node.glyph, FieldBeaconGlyph.request);
      expect(node.hasStatusMarker, isTrue);
    });
  });

  group('Post placement', () {
    test('Post members join the field only while the Post is selected', () {
      final webs = [_web('post-1', 'peer-b')];
      final field = _field(posts: [_post('post-1')], memberWebs: webs);

      final idle = _compose(field);
      expect(idle.keptPeerIds, contains('peer-a'));
      expect(idle.keptPeerIds, isNot(contains('peer-b')));

      final selected = _compose(field, selectedRequestWebs: webs);
      expect(selected.keptPeerIds, containsAll(['peer-a', 'peer-b']));
    });

    test('an unanchored Post is a satellite of its author', () {
      final composed = _compose(
        _field(
          posts: [_post('post-1')],
          memberWebs: [_web('post-1', 'peer-b')],
        ),
      );
      final input = _layoutInput(composed);
      expect(input.satelliteRequestIdsByAuthor['peer-a'], contains('post-1'));
      expect(input.requestAuthorById['post-1'], 'peer-a');

      final layout = computeConstellationPlacedLayout(input: input);
      final post = layout.positions['post-1']!;
      expect(
        _distance(post, layout.positions['peer-a']!),
        lessThan(_distance(post, layout.positions[_ego]!)),
      );
    });

    test('adding a Post does not move people', () {
      ConstellationLayout layoutFor(ConstellationField field) {
        final composed = _compose(field);
        return computeConstellationPlacedLayout(input: _layoutInput(composed));
      }

      final without = layoutFor(_field(requests: [_request()]));
      final mixed = layoutFor(
        _field(
          requests: [_request()],
          posts: [_post('post-1')],
          memberWebs: [_web('post-1', 'peer-b')],
        ),
      );
      expect(without.positions['req-1'], isNotNull);
      expect(mixed.positions['req-1'], isNotNull);
      for (final id in ['peer-a', 'peer-b', _ego]) {
        expect(mixed.positions[id], without.positions[id], reason: id);
      }
      expect(mixed.positions['post-1'], isNotNull);
    });
  });
}
