@TestOn('vm')
library;

// Real path: the Field response goes through the real transport, GraphQL
// mapper and repository into the Field cubit and the mounted Field.
//
// A Post that sits behind its author's «+N more» chip until the chip is
// expanded still gets one edge to each participant (inside and forwarded)
// and the author → Post edge when it is selected. With the chip expanded and
// nothing selected the Field draws no dashed edge at all (no budded-from
// link, no temporary-person link, no forwarded web) and no participant or
// author edge; Esc and collapse / expand keep it that way. A Request and a
// Post with the same participant states draw the same edge kinds.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:logging/logging.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/data/repository/constellation_member_webs_repository.dart';
import 'package:tentura/features/constellation/data/repository/constellation_repository.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_member_webs_case.dart';
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
const _eve = 'Ueve000000001';
const _boris = 'Uboris0000001';
const _fedor = 'Ufedor0000001';
const _tom = 'Utom000000001';
const _post = 'Ppost00000001';
const _postDeclined = 'Ppost00000002';

/// The Request budded from [_post] (amy's), and the Request that made tom a
/// temporary person on the Field.
const _budded = 'Rbud000000001';
const _eveRequest = 'Reve000000001';

const _desktop = Size(1200, 800);

/// More of bob's Requests than any satellite budget draws, all newer than
/// his Posts, so the Posts are the ones hidden behind his overflow chip.
final _bobRequestIds = [
  for (var i = 0; i < 9; i++) 'Rbob${i.toString().padLeft(9, '0')}',
];

/// Every edge kind the Field strokes dashed.
const _dashedKinds = {
  ConstellationEdgeKind.tier2Path,
  ConstellationEdgeKind.ringStub,
  ConstellationEdgeKind.webForwarded,
  ConstellationEdgeKind.draftRecipient,
  ConstellationEdgeKind.grewFrom,
  ConstellationEdgeKind.temporaryPresence,
};

Map<String, dynamic> _peer(
  String id,
  String displayName, {
  bool contactOnly = false,
  String presence = 'visible',
  String? temporaryBeaconId,
}) => {
  '__typename': 'v2_ConstellationPeer',
  'id': id,
  'pinState': null,
  'contactOnly': contactOnly,
  'presence': presence,
  'temporaryBeaconId': temporaryBeaconId,
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

Map<String, dynamic> _request(
  String id,
  String authorId,
  String title, {
  required DateTime lastActivityAt,
  String? parentBeaconId,
}) => {
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
  'lastActivityAt': lastActivityAt.toIso8601String(),
  'addressLabel': null,
  'hasCoordinates': false,
  'isMine': false,
  'viewerHasActiveHelpOffer': false,
  'viewerIsRoomParticipant': false,
  'viewerHasForwardEdge': false,
  'forwardedById': null,
  'forwardedByName': null,
  'parentBeaconId': parentBeaconId,
  'helpOfferCount': 0,
  'coverSource': 0,
  'coverThumb': null,
  'has_unread': false,
};

Map<String, dynamic> _postJson(
  String id,
  String excerpt, {
  required DateTime lastActivityAt,
}) {
  final now = DateTime.now().toUtc();
  return {
    '__typename': 'v2_ConstellationPost',
    'id': id,
    'authorId': _bob,
    'lastActivityAt': lastActivityAt.toIso8601String(),
    'expiresAt': now.add(const Duration(hours: 48)).toIso8601String(),
    'status': 0,
    'rootExcerpt': excerpt,
    'isPinned': false,
    'hiddenReachCount': 0,
    'has_unread': false,
  };
}

Map<String, dynamic> _memberWeb(
  String beaconId,
  String personId,
  String state,
) => {
  '__typename': 'v2_ConstellationMemberWeb',
  'beaconId': beaconId,
  'personId': personId,
  'state': state,
};

/// Anna ↔ amy trust each other; amy → bob, bob → eve. bob holds more
/// Requests than his satellites can show plus two older Posts: [_post] with
/// Boris INSIDE its room and Fedor who FORWARDED it (both contact-only, not
/// reached by trust), and [_postDeclined] with eve inside. amy's Request
/// [_budded] grew from [_post]; tom is on the Field only temporarily, through
/// eve's Request.
Map<String, dynamic> _fieldResponse() {
  final now = DateTime.now().toUtc();
  DateTime ago(int minutes) => now.subtract(Duration(minutes: minutes));
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
        _peer(_eve, 'Eve'),
        _peer(_boris, 'Boris', contactOnly: true, presence: 'contactOnly'),
        _peer(_fedor, 'Fedor', contactOnly: true, presence: 'contactOnly'),
        _peer(
          _tom,
          'Tom',
          presence: 'temporary',
          temporaryBeaconId: _eveRequest,
        ),
      ],
      'edges': [
        _edge(_viewer.id, _amy),
        _edge(_amy, _viewer.id),
        _edge(_amy, _bob),
        _edge(_bob, _eve),
      ],
      'requests': [
        for (final (i, id) in _bobRequestIds.indexed)
          _request(id, _bob, 'Bob request $i', lastActivityAt: ago(i + 1)),
        _request(_eveRequest, _eve, 'Need a ladder', lastActivityAt: ago(5)),
        _request(
          _budded,
          _amy,
          'Weekend ladder pickup',
          lastActivityAt: ago(6),
          parentBeaconId: _post,
        ),
      ],
      'posts': [
        _postJson(
          _post,
          'Who has a ladder for the weekend?',
          lastActivityAt: ago(600),
        ),
        _postJson(
          _postDeclined,
          'Declined: the van is booked',
          lastActivityAt: ago(700),
        ),
      ],
      'memberWebs': [
        _memberWeb(_post, _boris, 'INSIDE'),
        _memberWeb(_post, _fedor, 'FORWARDED'),
        _memberWeb(_postDeclined, _eve, 'INSIDE'),
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

/// Loads the Field through the wire into a cubit and mounts it at [size] in
/// [locale].
Future<ConstellationCubit> _mountField(
  WidgetTester tester, {
  required Size size,
  required Locale locale,
}) async {
  final sent = <WireSent>[];
  late ConstellationCubit cubit;
  await tester.runAsync(
    () => withRemoteWire(
      {'ConstellationFieldFetch': _fieldResponse()},
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
    locale: locale,
    disableAnimations: true,
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  final context = tester.element(find.byType(ConstellationBody));
  expect(Localizations.localeOf(context), locale);
  expect(MediaQuery.sizeOf(context), size);
  return cubit;
}

Set<String> _semanticIds(ConstellationCubit cubit) => {
  for (final edge in cubit.graphController.edges) edge.semanticId,
};

/// Edges from [beaconId] to a person, as semanticIds.
Set<String> _webIds(ConstellationCubit cubit, String beaconId) => {
  for (final id in _semanticIds(cubit))
    if (id.startsWith('fr:$beaconId->fp:')) id,
};

bool _selectionOnlyKind(ConstellationEdgeKind kind) =>
    _dashedKinds.contains(kind) ||
    kind == ConstellationEdgeKind.webInside ||
    kind == ConstellationEdgeKind.attachment;

/// Every edge the Field holds that it should not show while nothing is
/// selected (any dashed kind, a participant edge, an author edge): from the
/// kinds the painter reads and from the drawn edges' own kind suffix, so an
/// edge missing from either still counts.
List<String> _selectionOnlyEdges(ConstellationCubit cubit) => {
  for (final MapEntry(key: id, value: kind) in cubit.edgeKindByPair.entries)
    if (_selectionOnlyKind(kind)) id,
  for (final edge in cubit.graphController.edges)
    if (ConstellationEdgeKind.values.any(
      (kind) =>
          _selectionOnlyKind(kind) && edge.semanticId.endsWith('#${kind.name}'),
    ))
      edge.semanticId,
}.toList()..sort();

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

/// Kind of each web edge from [beaconId], by participant id.
Map<String, ConstellationEdgeKind?> _webKindsByPerson(
  ConstellationCubit cubit,
  String beaconId,
) => {
  for (final id in _webIds(cubit, beaconId))
    id.substring('fr:$beaconId->fp:'.length, id.indexOf('#')):
        cubit.edgeKindByPair[id],
};

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

Finder get _bobOverflowChip =>
    find.byKey(const Key('constellation.overflow.$_bob'));

/// Zooms the camera to full scale on bob, the way the user zooms in to read
/// his cluster: the overview draws no overflow chip.
Future<void> _zoomOntoBob(WidgetTester tester, ConstellationCubit cubit) async {
  final point = cubit.graphController.renderSnapshot.resolvePosition(
    'fp:$_bob',
  );
  expect(point, isNotNull, reason: 'bob is placed on the Field');
  cubit.graphController.jumpToPosition(
    Offset(point!.x, point.y),
    resetScale: true,
  );
  await tester.pumpAndSettle();
}

/// Taps bob's overflow chip, the way the user expands or collapses it.
Future<void> _tapOverflowChip(WidgetTester tester) async {
  expect(_bobOverflowChip, findsOneWidget, reason: "bob's overflow chip");
  await tester.tap(_bobOverflowChip);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

/// Mounts the Field and expands bob's overflow chip so his Posts show.
Future<ConstellationCubit> _mountExpanded(
  WidgetTester tester, {
  required Size size,
  required Locale locale,
}) async {
  final cubit = await _mountField(tester, size: size, locale: locale);
  expect(
    cubit.displayedRequestIds,
    isNot(anyOf(contains(_post), contains(_postDeclined))),
    reason: "precondition: bob's Posts are hidden behind his overflow chip",
  );
  expect(
    cubit.overflowHiddenCountByAuthor[_bob] ?? 0,
    greaterThanOrEqualTo(2),
    reason: 'precondition: bob has an overflow chip',
  );
  await _zoomOntoBob(tester, cubit);
  if (locale.languageCode == 'ru') {
    expect(
      find.descendant(
        of: _bobOverflowChip,
        matching: find.textContaining('ещё'),
      ),
      findsOneWidget,
      reason: 'the chip reads «ещё N» in Russian',
    );
  }
  await _tapOverflowChip(tester);
  expect(cubit.isSatelliteOverflowExpanded(_bob), isTrue);
  expect(
    cubit.displayedRequestIds,
    containsAll([_post, _postDeclined]),
    reason: "the expanded chip shows bob's Posts",
  );
  final placed = cubit.graphController.renderSnapshot.topology.nodesById.keys;
  expect(
    placed,
    containsAll([
      'fr:$_post',
      'fr:$_postDeclined',
      'fr:$_budded',
      'fr:$_eveRequest',
      'fp:$_tom',
    ]),
    reason:
        "precondition: bob's Posts, the Request budded from the Post and the "
        'temporary person with their Request are on the Field',
  );
  return cubit;
}

/// Taps [_post]'s node on the Field. The camera is first brought onto the
/// Post (focusing also selects it, so the selection is cleared again): only
/// the tap selects it.
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
  final node = find.byKey(TestIds.key(TestIds.graphNode(_post)));
  expect(node, findsOneWidget);
  await tester.tap(node);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  expect(cubit.state.selectedRequestId, _post);
}

/// Paints [edge] with the mounted Field's edge painter, at the positions the
/// Field gave its two nodes, onto a recording canvas.
_StrokeCanvas _paintEdge(
  WidgetTester tester,
  ConstellationCubit cubit,
  EdgeDetails edge,
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

  final canvas = _StrokeCanvas();
  (painter as ConstellationEdgePainter).paint(
    canvas,
    edge,
    at(edge, source: true),
    at(edge, source: false),
  );
  return canvas;
}

/// The mounted Field's edge painter strokes every edge in [ids].
void _expectPainterStrokes(
  WidgetTester tester,
  ConstellationCubit cubit,
  Iterable<String> ids,
) {
  for (final id in ids) {
    final edge = cubit.graphController.edges.singleWhere(
      (edge) => edge.semanticId == id,
    );
    final canvas = _paintEdge(tester, cubit, edge);
    expect(
      canvas.solidLines + canvas.dashedStrokes,
      greaterThan(0),
      reason: 'the painter strokes $id',
    );
  }
}

/// Painting every edge on the Field with the mounted Field's edge painter
/// strokes no dashed segment.
void _expectPainterStrokesNoDash(
  WidgetTester tester,
  ConstellationCubit cubit,
) {
  final dashed = [
    for (final edge in cubit.graphController.edges)
      if (_paintEdge(tester, cubit, edge).dashedStrokes > 0) edge.semanticId,
  ]..sort();
  expect(
    dashed,
    isEmpty,
    reason: 'the Field strokes no dashed segment while nothing is selected',
  );
}

/// Records the strokes the Field's edge painter makes: a solid edge is one
/// `drawLine`, a dashed edge strokes its dash path with `drawPath`. The
/// painter makes no other canvas call that returns a value; any call not
/// stubbed here fails loudly.
class _StrokeCanvas implements Canvas {
  int solidLines = 0;
  int dashedStrokes = 0;

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) => solidLines++;

  @override
  void drawPath(Path path, Paint paint) {
    if (paint.style == PaintingStyle.stroke) {
      dashedStrokes++;
    }
  }

  @override
  void drawCircle(Offset c, double radius, Paint paint) {}

  @override
  void save() {}

  @override
  void restore() {}

  @override
  void translate(double dx, double dy) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'the edge painter made an unexpected canvas call: '
    '${invocation.memberName}',
  );
}

void main() {
  for (final (:name, :size, :locale) in [
    (name: 'desktop 1200x800', size: _desktop, locale: const Locale('en')),
    (name: 'phone 375x667 ru', size: kPhoneSurface, locale: const Locale('ru')),
  ]) {
    group("Post behind its author's expanded overflow chip at $name", () {
      testWidgets(
        'the Field snapshot holds both participants of the Post',
        (tester) async {
          final cubit = await _mountField(tester, size: size, locale: locale);

          final webs = [
            for (final web in cubit.state.field!.memberWebs)
              if (web.beaconId == _post) (web.personId, web.state),
          ];
          expect(
            webs,
            unorderedEquals([
              (_boris, ConstellationMemberWebState.inside),
              (_fedor, ConstellationMemberWebState.forwarded),
            ]),
          );
        },
      );

      testWidgets(
        'selecting the Post draws one edge to each participant, including '
        'contact-only ones not placed before, and to every preview face',
        (tester) async {
          final cubit = await _mountExpanded(
            tester,
            size: size,
            locale: locale,
          );
          final placed =
              cubit.graphController.renderSnapshot.topology.nodesById.keys;
          expect(
            placed,
            isNot(anyOf(contains('fp:$_boris'), contains('fp:$_fedor'))),
            reason:
                'precondition: contact-only Boris and Fedor are not placed '
                'before the Post is selected',
          );
          expect(_webIds(cubit, _post), isEmpty);

          await _tapPost(tester, cubit);

          const expected = {
            'fr:$_post->fp:$_boris#webInside': ConstellationEdgeKind.webInside,
            'fr:$_post->fp:$_fedor#webForwarded':
                ConstellationEdgeKind.webForwarded,
          };
          expect(_webIds(cubit, _post), expected.keys.toSet());
          for (final MapEntry(key: id, value: kind) in expected.entries) {
            expect(cubit.edgeKindByPair[id], kind);
          }
          _expectPainterStrokes(tester, cubit, expected.keys);

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
          final webs = _webIds(cubit, _post);
          for (final id in faces) {
            expect(
              webs.where((web) => web.startsWith('fr:$_post->fp:$id#')),
              hasLength(1),
              reason:
                  'the preview shows $id as a face, so the Post has one '
                  'edge to them; drawn: ${webs.toList()..sort()}',
            );
          }
        },
      );

      testWidgets(
        'selecting the Post draws the author edge and the trust path '
        "Ego → amy → author, and none of the author's other trust edges",
        (tester) async {
          final cubit = await _mountExpanded(
            tester,
            size: size,
            locale: locale,
          );

          await _tapPost(tester, cubit);

          const attachment = 'fp:$_bob->fr:$_post#attachment';
          expect(_semanticIds(cubit), contains(attachment));
          expect(
            cubit.edgeKindByPair[attachment],
            ConstellationEdgeKind.attachment,
          );
          _expectPainterStrokes(tester, cubit, [attachment]);
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
            _expectPainterStrokes(tester, cubit, hop);
          }
          final drawn = _drawnPairs(cubit);
          expect(
            drawn,
            isNot(contains(_pair(_bob, _eve))),
            reason:
                "the author's trust edge to eve is not on the path, drawn: "
                '${drawn.toList()..sort()}',
          );
        },
      );

      testWidgets(
        'with nothing selected draws no dashed, participant or author edge',
        (tester) async {
          final cubit = await _mountExpanded(
            tester,
            size: size,
            locale: locale,
          );

          expect(cubit.state.selectedRequestId, isNull);
          expect(cubit.state.selectedPersonId, isNull);
          expect(
            cubit.state.field!.peers
                .singleWhere((peer) => peer.id == _tom)
                .fieldMembership,
            ConstellationFieldMembership.temporary,
            reason: 'precondition: tom is a temporary person',
          );
          expect(
            _selectionOnlyEdges(cubit),
            isEmpty,
            reason:
                'nothing is selected, so no budded-from, temporary-person, '
                'participant or author edge is drawn',
          );
          _expectPainterStrokesNoDash(tester, cubit);
        },
      );

      testWidgets(
        'Esc after selecting the Post leaves no edge of the Post and no '
        'dashed edge',
        (tester) async {
          final cubit = await _mountExpanded(
            tester,
            size: size,
            locale: locale,
          );
          await _tapPost(tester, cubit);
          expect(_webIds(cubit, _post), isNotEmpty);

          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();

          expect(cubit.state.selectedRequestId, isNull);
          expect(_webIds(cubit, _post), isEmpty);
          expect(
            _semanticIds(cubit),
            isNot(contains('fp:$_bob->fr:$_post#attachment')),
          );
          expect(_selectionOnlyEdges(cubit), isEmpty);
          _expectPainterStrokesNoDash(tester, cubit);
        },
      );

      testWidgets(
        'collapsing and expanding the chip again with nothing selected draws '
        'no dashed, participant or author edge',
        (tester) async {
          final cubit = await _mountExpanded(
            tester,
            size: size,
            locale: locale,
          );

          await _tapOverflowChip(tester);
          expect(cubit.isSatelliteOverflowExpanded(_bob), isFalse);
          await _tapOverflowChip(tester);
          expect(cubit.isSatelliteOverflowExpanded(_bob), isTrue);

          expect(cubit.state.selectedRequestId, isNull);
          expect(_selectionOnlyEdges(cubit), isEmpty);
          _expectPainterStrokesNoDash(tester, cubit);
        },
      );

      testWidgets(
        'a Request and a Post with the same participant states draw the same '
        'edge kinds',
        (tester) async {
          await tester.binding.setSurfaceSize(size);
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final sent = <WireSent>[];
          late ConstellationCubit cubit;
          await tester.runAsync(
            () => withRemoteWire(
              {
                'ConstellationFieldFetch': _fieldResponse(),
                // eve's Request has the Post's participants in the same
                // states: Boris inside, Fedor forwarded.
                'BeaconMemberWebs': {
                  '__typename': 'query_root',
                  'beaconMemberWebs': [
                    _memberWeb(_eveRequest, _boris, 'INSIDE'),
                    _memberWeb(_eveRequest, _fedor, 'FORWARDED'),
                  ],
                },
              },
              sent,
              (remote) async {
                final fixture = ConstellationStoreFixture(
                  ConstellationRepository(remote),
                  accountId: _viewer.id,
                );
                cubit = ConstellationCubit(
                  case_: fixture.store,
                  viewer: _viewer,
                  loadOnCreate: false,
                  memberWebsCase: ConstellationMemberWebsCase(
                    ConstellationMemberWebsRepository(remote),
                    env: const Env(),
                    logger: Logger('test'),
                  ),
                );
                addTearDown(() async {
                  if (!cubit.isClosed) await cubit.close();
                });
                await fixture.ready();
                await cubit.load().timeout(const Duration(seconds: 15));
                cubit.selectRequest(_eveRequest);
                final deadline = DateTime.now().add(
                  const Duration(seconds: 10),
                );
                while (_webIds(cubit, _eveRequest).length < 2 &&
                    DateTime.now().isBefore(deadline)) {
                  await Future<void>.delayed(const Duration(milliseconds: 20));
                }
              },
            ),
          );
          expect(
            sent.map((request) => request.operationName),
            containsAll(['ConstellationFieldFetch', 'BeaconMemberWebs']),
          );
          await pumpConstellationBody(
            tester,
            cubit,
            size: size,
            locale: locale,
            disableAnimations: true,
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(cubit.state.selectedRequestId, _eveRequest);

          final requestKinds = _webKindsByPerson(cubit, _eveRequest);
          expect(requestKinds, {
            _boris: ConstellationEdgeKind.webInside,
            _fedor: ConstellationEdgeKind.webForwarded,
          });
          _expectPainterStrokes(tester, cubit, _webIds(cubit, _eveRequest));

          cubit.selectRequest(null);
          await tester.pumpAndSettle();
          await _zoomOntoBob(tester, cubit);
          await _tapOverflowChip(tester);
          expect(cubit.isSatelliteOverflowExpanded(_bob), isTrue);
          expect(
            cubit.graphController.renderSnapshot.topology.nodesById.keys,
            contains('fr:$_post'),
            reason: "the expanded chip places bob's Post",
          );
          await _tapPost(tester, cubit);

          final postKinds = _webKindsByPerson(cubit, _post);
          expect(
            postKinds,
            requestKinds,
            reason:
                'the Post draws the same edge kind to each participant as '
                'the Request with the same participant states',
          );
          _expectPainterStrokes(tester, cubit, _webIds(cubit, _post));
        },
      );
    });
  }
}
