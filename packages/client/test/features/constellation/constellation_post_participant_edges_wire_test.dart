@TestOn('vm')
library;

// Real path: the Field response goes through the real transport, GraphQL
// mapper and repository into the Field cubit and the mounted Field. A Post
// selected on the Field draws the trust path Ego → … → author → Post and one
// edge from the Post to every participant its preview shows; nothing is drawn
// while nothing is selected, also after a list → map switch; Esc and
// deselecting clear the edges; mutual trust stays one twin stroke.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/data/repository/constellation_repository.dart';
import 'package:tentura/features/constellation/domain/constellation_consts.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/graph/domain/entity/edge_details.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../support/constellation_store_fixture.dart';
import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';
import 'fixtures/constellation_reference_fixture.dart';

const _viewer = Profile(id: 'Uviewer000001', displayName: 'Anna');
const _amy = 'Uamy000000001';
const _bob = 'Ubob000000001';
const _cat = 'Ucat000000001';
const _dan = 'Udan000000001';
const _eve = 'Ueve000000001';
const _fay = 'Ufay000000001';
const _boris = 'Uboris0000001';
const _fedor = 'Ufedor0000001';
const _ghost = 'Ughost0000001';
const _post = 'Ppost00000001';

const _desktop = Size(1200, 800);

/// Indirect peers (amy trusts each) that fill the Field's render budget on
/// their own; they sort after every named person above.
final _fillerIds = [
  for (var i = 0; i < constellationRenderPeerCap(); i++)
    'Vfill${i.toString().padLeft(8, '0')}',
];

Map<String, dynamic> _peer(
  String id,
  String displayName, {
  bool contactOnly = false,
  String presence = 'visible',
}) => {
  '__typename': 'v2_ConstellationPeer',
  'id': id,
  'pinState': null,
  'contactOnly': contactOnly,
  'presence': presence,
  'temporaryBeaconId': null,
  'bondContexts': <dynamic>[],
  'displayName': displayName,
  'handle': null,
  'isNew': false,
  'image': null,
};

Map<String, dynamic> _edge(String src, String dst) => {
  '__typename': 'v2_ConstellationEdge',
  'src': src,
  'dst': dst,
  'tier': 1,
};

Map<String, dynamic> _request(String id, String authorId, String title) => {
  '__typename': 'v2_ConstellationRequest',
  'id': id,
  'pinState': null,
  'authorId': authorId,
  'title': title,
  'status': 0,
  'needs': <String>[],
  'primaryNeedSlug': null,
  'startAt': null,
  'endAt': null,
  'lastActivityAt': DateTime.now().toUtc().toIso8601String(),
  'addressLabel': null,
  'hasCoordinates': false,
  'isMine': false,
  'viewerHasActiveHelpOffer': false,
  'viewerIsRoomParticipant': false,
  'viewerHasForwardEdge': false,
  'forwardedById': null,
  'forwardedByName': null,
  'parentBeaconId': null,
  'helpOfferCount': 0,
  'coverSource': 0,
  'coverThumb': null,
  'has_unread': false,
};

Map<String, dynamic> _memberWeb(String personId, String state) => {
  '__typename': 'v2_ConstellationMemberWeb',
  'beaconId': _post,
  'personId': personId,
  'state': state,
};

/// Anna ↔ amy trust each other explicitly; amy → bob. bob trusts eve and
/// fay, who hold a Request each. bob's Post has cat inside its room and dan
/// as a forwarder; both are people on the Field.
///
/// [extraPeers] / [extraEdges] / [extraWebs] add the participants a test
/// needs beyond cat and dan.
Map<String, dynamic> _fieldResponse({
  List<Map<String, dynamic>> extraPeers = const [],
  List<Map<String, dynamic>> extraEdges = const [],
  List<Map<String, dynamic>> extraWebs = const [],
}) {
  final now = DateTime.now().toUtc();
  return {
    '__typename': 'query_root',
    'constellationField': {
      '__typename': 'v2_ConstellationField',
      'loadedAt': now.toIso8601String(),
      'context': '',
      'peersCapped': false,
      'requestsCapped': false,
      'directContactIds': [_amy],
      'peers': [
        _peer(_amy, 'Amy'),
        _peer(_bob, 'Bob'),
        _peer(_cat, 'Cat'),
        _peer(_dan, 'Dan'),
        _peer(_eve, 'Eve'),
        _peer(_fay, 'Fay'),
        ...extraPeers,
      ],
      'edges': [
        _edge(_viewer.id, _amy),
        _edge(_amy, _viewer.id),
        _edge(_amy, _bob),
        _edge(_bob, _eve),
        _edge(_bob, _fay),
        ...extraEdges,
      ],
      'requests': [
        _request('Reve000000001', _eve, 'Need a ladder'),
        _request('Rfay000000001', _fay, 'Help me move'),
      ],
      'posts': [
        {
          '__typename': 'v2_ConstellationPost',
          'id': _post,
          'authorId': _bob,
          'lastActivityAt': now
              .subtract(const Duration(hours: 1))
              .toIso8601String(),
          'expiresAt': now.add(const Duration(hours: 48)).toIso8601String(),
          'status': 0,
          'rootExcerpt': 'Who has a ladder for the weekend?',
          'isPinned': false,
          'hiddenReachCount': 0,
          'has_unread': false,
        },
      ],
      'memberWebs': [
        _memberWeb(_cat, 'INSIDE'),
        _memberWeb(_dan, 'FORWARDED'),
        ...extraWebs,
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
}

/// Loads [response] through the wire into a cubit and mounts the Field at
/// [size].
Future<ConstellationCubit> _mountField(
  WidgetTester tester, {
  required Size size,
  Map<String, dynamic>? response,
}) async {
  final sent = <WireSent>[];
  late ConstellationCubit cubit;
  await tester.runAsync(
    () => withRemoteWire(
      {'ConstellationFieldFetch': response ?? _fieldResponse()},
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
  expect(
    sent.map((request) => request.operationName),
    contains('ConstellationFieldFetch'),
  );
  await pumpConstellationBody(
    tester,
    cubit,
    size: size,
    locale: const Locale('en'),
    disableAnimations: true,
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  return cubit;
}

/// Taps the Post's node on the Field, the way the user selects it. The
/// camera is first brought onto the Post (focusing also selects it, so the
/// selection is cleared again): only the tap selects the Post.
Future<void> _tapPost(WidgetTester tester, ConstellationCubit cubit) async {
  cubit.focusBeacon(_post, insets: EdgeInsets.zero);
  await tester.pumpAndSettle();
  cubit.selectRequest(null);
  await tester.pumpAndSettle();
  expect(
    cubit.state.selectedRequestId,
    isNull,
    reason: 'precondition: nothing is selected before the tap',
  );
  final postNode = find.byKey(TestIds.key(TestIds.graphNode(_post)));
  expect(postNode, findsOneWidget);
  await tester.tap(postNode);
  await tester.pumpAndSettle();
  expect(
    tester.takeException(),
    isNull,
    reason: 'selecting the Post must render without an exception',
  );
  expect(cubit.state.selectedRequestId, _post);
}

Set<String> _semanticIds(ConstellationCubit cubit) => {
  for (final edge in cubit.graphController.edges) edge.semanticId,
};

/// The Post → person edges drawn, as semanticIds.
Set<String> _postWebIds(ConstellationCubit cubit) => {
  for (final id in _semanticIds(cubit))
    if (id.startsWith('fr:$_post->fp:')) id,
};

/// SemanticIds of every drawn edge between [x] and [y], either direction.
List<String> _edgesBetween(ConstellationCubit cubit, String x, String y) => [
  for (final edge in cubit.graphController.edges)
    if (_pair(edge.source.id, edge.destination.id) == _pair(x, y))
      edge.semanticId,
];

String _pair(String x, String y) => x.compareTo(y) <= 0 ? '$x–$y' : '$y–$x';

/// Every drawn edge as an undirected pair of domain ids.
Set<String> _drawnPairs(ConstellationCubit cubit) => {
  for (final edge in cubit.graphController.edges)
    if (edge.source.id != edge.destination.id)
      _pair(edge.source.id, edge.destination.id),
};

/// Canvas that keeps every point a `draw*` call touches (line ends, path and
/// rect corners, circle extents), so a test can see where a stroke went.
class _GeometryCanvas implements Canvas {
  final points = <Offset>[];

  void _add(Object? arg) {
    switch (arg) {
      case final Offset o:
        points.add(o);
      case final Path path:
        final b = path.getBounds();
        points.addAll([b.topLeft, b.bottomRight]);
      case final Rect r:
        points.addAll([r.topLeft, r.bottomRight]);
      case final List<Offset> list:
        points.addAll(list);
      case final Float32List raw:
        for (var i = 0; i + 1 < raw.length; i += 2) {
          points.add(Offset(raw[i], raw[i + 1]));
        }
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName.toString();
    if (!name.contains('"draw')) {
      return null;
    }
    final args = invocation.positionalArguments;
    if (name.contains('"drawCircle"')) {
      final centre = args[0] as Offset;
      final r = args[1] as double;
      points.addAll([centre - Offset(r, r), centre + Offset(r, r)]);
      return null;
    }
    args.forEach(_add);
    return null;
  }

  /// Bounds of everything drawn, or null when nothing was.
  Rect? get bounds {
    if (points.isEmpty) return null;
    var rect = Rect.fromPoints(points.first, points.first);
    for (final p in points.skip(1)) {
      rect = rect.expandToInclude(Rect.fromPoints(p, p));
    }
    return rect;
  }
}

/// The mounted Field draws its scene with the Field's edge painter, and that
/// painter strokes every edge in [kinds] (semanticId → expected kind) from
/// the rim of its source node to the rim of its destination node, at the
/// positions the Field gave the two nodes, and nowhere else.
void _expectFieldEdgePainterPaints(
  WidgetTester tester,
  ConstellationCubit cubit,
  Map<String, ConstellationEdgeKind> kinds,
) {
  final painter = tester
      .widget<GraphView<dynamic, dynamic>>(
        find.byWidgetPredicate((w) => w is GraphView),
      )
      .edgePainter;
  expect(painter, isA<ConstellationEdgePainter>());
  final snapshot = cubit.graphController.renderSnapshot;
  Offset at(EdgeDetails edge, {required bool source}) {
    final node = source ? edge.source : edge.destination;
    final point = snapshot.resolvePosition(node.graphNodeId);
    expect(point, isNotNull, reason: '${node.graphNodeId} has a position');
    return Offset(point!.x, point.y);
  }

  for (final MapEntry(key: id, value: kind) in kinds.entries) {
    final edge = cubit.graphController.edges.singleWhere(
      (edge) => edge.semanticId == id,
    );
    expect(cubit.edgeKindByPair[id], kind, reason: '$id is drawn as $kind');
    final src = at(edge, source: true);
    final dst = at(edge, source: false);
    final canvas = _GeometryCanvas();
    (painter as ConstellationEdgePainter).paint(canvas, edge, src, dst);
    final drawn = canvas.bounds;
    expect(drawn, isNotNull, reason: 'the painter draws $id');
    // The stroke is trimmed to the node rims. It starts at the source rim;
    // a dashed stroke may stop up to one dash + gap short of the far rim.
    final direction = (dst - src) / (dst - src).distance;
    final srcRim = src + direction * (edge.source.size / 2 + 2);
    final dstRim = dst - direction * (edge.destination.size / 2 + 2);
    final trimmedLength = (dstRim - srcRim).distance;
    final farSlack = math.max(24, trimmedLength * 0.15).toDouble();
    expect(
      drawn!.inflate(4).contains(srcRim) &&
          drawn.inflate(farSlack).contains(dstRim),
      isTrue,
      reason:
          '$id is drawn from $srcRim to $dstRim (source $src, '
          'destination $dst); drawn bounds: $drawn',
    );
    final between = Rect.fromPoints(src, dst).inflate(8);
    expect(
      between.contains(drawn.topLeft) && between.contains(drawn.bottomRight),
      isTrue,
      reason: '$id is drawn only between its two nodes; drawn: $drawn',
    );
  }
}

const _participantsRow = Key('constellation.field_preview.participants');
const _forwardedRow = Key('constellation.field_preview.forwarded');

/// Ids of the faces the Post preview's participant and forwarded rows show
/// (only the rows in [rows]).
Set<String> _previewFaceIds(
  WidgetTester tester, {
  List<Key> rows = const [_participantsRow, _forwardedRow],
}) {
  final ids = <String>{};
  for (final key in rows) {
    final stacks = find.descendant(
      of: find.byKey(key),
      matching: find.byType(TenturaAvatarStack),
    );
    for (final element in stacks.evaluate()) {
      final stack = element.widget as TenturaAvatarStack;
      ids.addAll(stack.profiles.map((profile) => profile.id));
    }
  }
  return ids;
}

/// The «+N» the Post preview row with [key] shows, or 0 without one.
int _previewHiddenCount(WidgetTester tester, Key key) {
  final texts = find.descendant(
    of: find.byKey(key),
    matching: find.textContaining(RegExp(r'^\+\d+$')),
  );
  if (texts.evaluate().isEmpty) {
    return 0;
  }
  final text = tester.widget<Text>(texts.first).data!;
  return int.parse(text.substring(1));
}

void main() {
  for (final (:name, :size) in [
    (name: 'desktop 1200x800', size: _desktop),
    (name: 'phone 375x667', size: kPhoneSurface),
  ]) {
    group('Post selected on the Field at $name', () {
      testWidgets('draws one edge from the Post to each participant', (
        tester,
      ) async {
        final cubit = await _mountField(tester, size: size);

        await _tapPost(tester, cubit);

        const expected = {
          'fr:$_post->fp:$_cat#webInside': ConstellationEdgeKind.webInside,
          'fr:$_post->fp:$_dan#webForwarded':
              ConstellationEdgeKind.webForwarded,
        };
        expect(_postWebIds(cubit), expected.keys.toSet());
        _expectFieldEdgePainterPaints(tester, cubit, expected);
      });

      testWidgets(
        'draws the trust path Ego → amy → author and the author → Post edge, '
        "and none of the author's other trust edges",
        (tester) async {
          final cubit = await _mountField(tester, size: size);

          await _tapPost(tester, cubit);

          final ids = _semanticIds(cubit);
          expect(ids, contains('fp:$_bob->fr:$_post#attachment'));
          final drawn = _drawnPairs(cubit);
          for (final (x, y, what) in [
            (_viewer.id, _amy, 'path hop Ego–amy'),
            (_amy, _bob, 'path hop amy–bob'),
          ]) {
            final hop = _edgesBetween(cubit, x, y);
            expect(
              hop,
              hasLength(1),
              reason: '$what is drawn as exactly one trust edge: $hop',
            );
          }
          expect(
            drawn,
            isNot(
              anyOf(contains(_pair(_bob, _eve)), contains(_pair(_bob, _fay))),
            ),
            reason:
                "the author's trust edges to eve and fay are not on the "
                'path, drawn: ${drawn.toList()..sort()}',
          );
        },
      );

      for (final (:fieldFull, :situation) in [
        (fieldFull: false, situation: 'with room on the Field'),
        (
          fieldFull: true,
          situation: 'when unrelated people fill the render budget',
        ),
      ]) {
        testWidgets(
          'a participant who was not placed before the selection gets an '
          'edge like every face the Post preview shows, $situation',
          (tester) async {
            // Boris (inside the room) and Fedor (forwarded it) hold nothing
            // on the Field and are reached by no trust path: the Field does
            // not place them until the Post that lists them is selected
            // (QA: the preview listed such a participant, the canvas drew no
            // edge to him).
            final cubit = await _mountField(
              tester,
              size: size,
              response: _fieldResponse(
                extraPeers: [
                  _peer(
                    _boris,
                    'Boris',
                    contactOnly: true,
                    presence: 'contactOnly',
                  ),
                  _peer(
                    _fedor,
                    'Fedor',
                    contactOnly: true,
                    presence: 'contactOnly',
                  ),
                  if (fieldFull)
                    for (final id in _fillerIds) _peer(id, 'Filler $id'),
                ],
                extraEdges: [
                  if (fieldFull) ...[
                    _edge(_amy, _cat),
                    _edge(_amy, _dan),
                    for (final id in _fillerIds) _edge(_amy, id),
                  ],
                ],
                extraWebs: [
                  _memberWeb(_boris, 'INSIDE'),
                  _memberWeb(_fedor, 'FORWARDED'),
                ],
              ),
            );
            final placed =
                cubit.graphController.renderSnapshot.topology.nodesById.keys;
            expect(
              placed,
              isNot(anyOf(contains('fp:$_boris'), contains('fp:$_fedor'))),
              reason:
                  'precondition: Boris and Fedor are not placed before the '
                  'selection',
            );
            expect(
              cubit.state.composition?.renderBudgetCapped,
              fieldFull,
              reason: fieldFull
                  ? 'precondition: the fillers use up the render budget'
                  : 'precondition: the render budget has room',
            );

            await _tapPost(tester, cubit);
            if (fieldFull) {
              expect(
                cubit.state.composition?.renderBudgetCapped,
                isTrue,
                reason:
                    'the render budget is still full with the Post selected',
              );
            }

            expect(
              _previewFaceIds(tester, rows: const [_participantsRow]),
              contains(_boris),
              reason: 'the Post preview lists Boris among its participants',
            );
            expect(
              _previewFaceIds(tester, rows: const [_forwardedRow]),
              contains(_fedor),
              reason: 'the Post preview lists Fedor among its forwarders',
            );
            final faces = _previewFaceIds(tester)..remove(_viewer.id);
            final webs = _postWebIds(cubit);
            for (final id in faces) {
              expect(
                webs.where((web) => web.startsWith('fr:$_post->fp:$id#')),
                hasLength(1),
                reason:
                    'the preview shows $id as a face, so the Post has an '
                    'edge to them; drawn: ${webs.toList()..sort()}',
              );
            }
            expect(
              webs,
              containsAll([
                'fr:$_post->fp:$_boris#webInside',
                'fr:$_post->fp:$_fedor#webForwarded',
              ]),
            );
          },
        );
      }

      testWidgets(
        'a participant who is not a person on the Field gets no edge and is '
        'counted in the Post +N and the preview +N instead',
        (tester) async {
          final cubit = await _mountField(
            tester,
            size: size,
            response: _fieldResponse(
              extraWebs: [_memberWeb(_ghost, 'FORWARDED')],
            ),
          );

          await _tapPost(tester, cubit);

          final webs = _postWebIds(cubit);
          expect(
            webs.where((id) => id.startsWith('fr:$_post->fp:$_ghost')),
            isEmpty,
          );
          expect(webs, {
            'fr:$_post->fp:$_cat#webInside',
            'fr:$_post->fp:$_dan#webForwarded',
          });
          expect(
            cubit.postOverflowCountByPostId[_post],
            1,
            reason: "the unplaced participant adds 1 to the Post's +N",
          );
          expect(
            _previewHiddenCount(
              tester,
              const Key('constellation.field_preview.forwarded'),
            ),
            1,
          );
        },
      );

      testWidgets('draws no edge while nothing is selected', (tester) async {
        final cubit = await _mountField(tester, size: size);

        expect(cubit.state.selectedRequestId, isNull);
        expect(cubit.state.selectedPersonId, isNull);
        expect(
          _semanticIds(cubit),
          isEmpty,
          reason: 'no Post or Request has an author edge without a selection',
        );
      });

      testWidgets('deselecting the Post removes all its edges', (
        tester,
      ) async {
        final cubit = await _mountField(tester, size: size);
        await _tapPost(tester, cubit);
        expect(_postWebIds(cubit), isNotEmpty);

        cubit.selectRequest(null);
        await tester.pumpAndSettle();

        expect(_postWebIds(cubit), isEmpty);
        expect(
          _semanticIds(cubit),
          isNot(contains('fp:$_bob->fr:$_post#attachment')),
        );
        expect(_semanticIds(cubit), isEmpty);
      });

      testWidgets('Esc clears the Post selection and its edges', (
        tester,
      ) async {
        final cubit = await _mountField(tester, size: size);
        await _tapPost(tester, cubit);
        expect(_postWebIds(cubit), isNotEmpty);
        // The tap gave the Field keyboard focus, so keys reach its handlers.
        final focus = FocusManager.instance.primaryFocus?.context;
        expect(
          focus?.findAncestorWidgetOfExactType<ConstellationBody>(),
          isNotNull,
          reason: 'keyboard focus is on the mounted Field after the tap',
        );
        // Another key reaches the Field too and keeps the selection: it is
        // Esc that clears it.
        await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
        await tester.pumpAndSettle();
        expect(cubit.state.selectedRequestId, _post);
        expect(_postWebIds(cubit), isNotEmpty);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();

        expect(cubit.state.selectedRequestId, isNull);
        expect(_semanticIds(cubit), isEmpty);
      });

      testWidgets(
        'selecting a person with mutual trust draws one twin stroke for the '
        'pair, not a second one-way edge',
        (tester) async {
          final cubit = await _mountField(tester, size: size);

          cubit.selectPerson(_amy);
          await tester.pumpAndSettle();

          final between = _edgesBetween(cubit, _viewer.id, _amy);
          expect(between, hasLength(1), reason: 'drawn: $between');
          expect(between.single, endsWith('#mutualTrust'));
          expect(
            cubit.edgeKindByPair[between.single],
            ConstellationEdgeKind.mutualTrust,
            reason: 'the pair is drawn with the mutual trust stroke',
          );
        },
      );
    });
  }

  testWidgets(
    'at 375x667 switching to the list and back to the map with nothing '
    'selected draws no edge',
    (tester) async {
      final cubit = await _mountField(tester, size: kPhoneSurface);
      expect(_semanticIds(cubit), isEmpty);

      cubit.setViewMode(ConstellationViewMode.text);
      await tester.pumpAndSettle();
      cubit.setViewMode(ConstellationViewMode.map);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final ids = _semanticIds(cubit);
      expect(
        ids,
        isEmpty,
        reason:
            'no attachment, ring stub or web edge without a selection; '
            'drawn: ${ids.toList()..sort()}',
      );
    },
  );
}
