@TestOn('vm')
library;

// Real path on a 375x667 phone in Russian: the Field response goes through
// the real transport, GraphQL mapper and repository into the Field cubit and
// the mounted Field. A selected Post, Request or person keeps the edges it
// shows at the default zoom (trust path, ladder and participant edges) when
// the map is zoomed out to the lowest scale the Field allows, where people are
// overview dots; each such edge stays at least one device pixel wide at every
// zoom, and the default zoom keeps painting what it painted before.
//
// The fixture also holds a Request budded from the Post: the Field draws that
// Post → Request edge with nothing selected, and keeps it (dimmed) while
// something that does not touch it is selected. It is the edge that stays
// "unselected" in these tests.

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/data/repository/constellation_repository.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_presentation_frame.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_tap_resolver.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../support/constellation_store_fixture.dart';
import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';
import 'fixtures/constellation_reference_fixture.dart';

const _viewerId = 'Uviewer000001';
const _viewer = Profile(id: _viewerId, displayName: 'Я');
const _amy = 'Uamy000000001';
const _bob = 'Ubob000000001';
const _cat = 'Ucat000000001';
const _dan = 'Udan000000001';
const _eve = 'Ueve000000001';
const _fay = 'Ufay000000001';
const _post = 'Ppost00000001';
const _request = 'Reve000000001';
const _budded = 'Rgrow00000001';

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

Map<String, dynamic> _edge(String src, String dst) => {
  '__typename': 'v2_ConstellationEdge',
  'src': src,
  'dst': dst,
  'tier': 1,
};

Map<String, dynamic> _requestJson(
  String id,
  String authorId,
  String title, {
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
  'lastActivityAt': DateTime.now().toUtc().toIso8601String(),
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

Map<String, dynamic> _memberWeb(String personId, String state) => {
  '__typename': 'v2_ConstellationMemberWeb',
  'beaconId': _post,
  'personId': personId,
  'state': state,
};

/// Ego → amy → bob explicitly; bob trusts eve and fay (who hold a Request
/// each). bob's Post has participants cat and dan.
Map<String, dynamic> _fieldResponse() {
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
        _peer(_amy, 'Анна Длиннофамильная-Константинопольская'),
        _peer(_bob, 'Борис'),
        _peer(_cat, 'Катя'),
        _peer(_dan, 'Даня'),
        _peer(_eve, 'Ева'),
        _peer(_fay, 'Фая'),
      ],
      'edges': [
        _edge(_viewer.id, _amy),
        _edge(_amy, _bob),
        _edge(_bob, _eve),
        _edge(_bob, _fay),
      ],
      'requests': [
        _requestJson(_request, _eve, 'Нужна стремянка'),
        _requestJson('Rfay000000001', _fay, 'Помочь с переездом'),
        _requestJson(
          _budded,
          _fay,
          'Лестница нашлась, нужен водитель',
          parentBeaconId: _post,
        ),
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
          'rootExcerpt': 'У кого есть лестница на выходные?',
          'isPinned': false,
          'hiddenReachCount': 0,
          'has_unread': false,
        },
      ],
      'memberWebs': [
        _memberWeb(_cat, 'INSIDE'),
        _memberWeb(_dan, 'FORWARDED'),
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

String _pair(String x, String y) => x.compareTo(y) <= 0 ? '$x–$y' : '$y–$x';

/// One mark the edge painter drew: how thick it is in scene px, its alpha,
/// whether it was a stroked line or path, and its stroke width if so.
typedef _Mark = ({double thickness, double alpha, bool stroke, double width});

/// Canvas that keeps every mark an edge can be drawn with: stroked or filled
/// lines, paths, rects and rounded rects. Circles and ovals (end dots) are
/// left out: they are decorations, not the edge itself.
final class _MarkRecordingCanvas implements Canvas {
  final marks = <_Mark>[];

  void _fill(double thickness, Paint paint) => marks.add((
    thickness: thickness,
    alpha: paint.color.a,
    stroke: false,
    width: 0,
  ));

  void _stroke(Paint paint) => marks.add((
    thickness: paint.strokeWidth,
    alpha: paint.color.a,
    stroke: true,
    width: paint.strokeWidth,
  ));

  /// Thickness of a filled shape: for a long thin quad of length L and
  /// thickness t, the perimeter is about 2L + 2t and the bounds' diagonal L.
  static double _shapeThickness(double perimeter, Rect bounds) => math.max(
    0,
    perimeter / 2 -
        math.sqrt(
          bounds.width * bounds.width + bounds.height * bounds.height,
        ),
  );

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) {
    if ((p2 - p1).distance == 0) return;
    _stroke(paint);
  }

  @override
  void drawPath(Path path, Paint paint) {
    final metrics = path.computeMetrics().toList();
    final length = metrics.fold<double>(0, (sum, m) => sum + m.length);
    if (length == 0) return;
    if (paint.style == PaintingStyle.stroke) {
      _stroke(paint);
    } else {
      _fill(_shapeThickness(length, path.getBounds()), paint);
    }
  }

  @override
  void drawRect(Rect rect, Paint paint) {
    if (paint.style == PaintingStyle.stroke) {
      _stroke(paint);
    } else {
      _fill(math.min(rect.width, rect.height), paint);
    }
  }

  @override
  void drawRRect(RRect rrect, Paint paint) => drawRect(rrect.outerRect, paint);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

GraphView<dynamic, dynamic> _graphView(WidgetTester tester) =>
    tester.widget<GraphView<dynamic, dynamic>>(
      find.byWidgetPredicate((w) => w is GraphView),
    );

/// The edge scene the Field hands to its edge painter: every edge of the
/// render topology, as undirected pairs of domain ids.
Set<String> _scenePairs(ConstellationCubit cubit) => {
  for (final edge
      in cubit.graphController.renderSnapshot.topology.edgesById.values)
    if (edge.payload.source.id != edge.payload.destination.id)
      _pair(edge.payload.source.id, edge.payload.destination.id),
};

/// What the mounted Field's edge layer paints this frame: every edge of the
/// scene topology handed to the Field's own edge painter at its scene
/// positions (as the graph view's edge layer does), keyed by the undirected
/// pair of domain ids, with the marks each one drew.
Map<String, List<_Mark>> _paintedEdges(
  WidgetTester tester,
  ConstellationCubit cubit,
) {
  final painter = _graphView(tester).edgePainter;
  expect(
    painter,
    isA<ConstellationEdgePainter>(),
    reason: 'the Field draws its edges with its own edge painter',
  );
  final edgePainter = painter as ConstellationEdgePainter;
  final snapshot = cubit.graphController.renderSnapshot;
  final result = <String, List<_Mark>>{};
  for (final edge in snapshot.topology.edgesById.values) {
    final payload = edge.payload;
    if (payload.source.id == payload.destination.id) continue;
    final src = snapshot.resolvePosition(edge.sourceId);
    final dst = snapshot.resolvePosition(edge.destinationId);
    if (src == null || dst == null) continue;
    final canvas = _MarkRecordingCanvas();
    edgePainter.paint(
      canvas,
      payload,
      Offset(src.x, src.y),
      Offset(dst.x, dst.y),
    );
    (result[_pair(payload.source.id, payload.destination.id)] ??= []).addAll(
      canvas.marks,
    );
  }
  return result;
}

/// Scene thickness of the thickest visible (alpha > 0) mark of each edge
/// drawn at all; edges with no visible mark are left out.
Map<String, double> _visibleEdges(Map<String, List<_Mark>> painted) => {
  for (final MapEntry(:key, :value) in painted.entries)
    if (value.any((m) => m.alpha > 0 && m.thickness > 0))
      key: value
          .where((m) => m.alpha > 0)
          .map((m) => m.thickness)
          .reduce(math.max),
};

typedef _Field = ({
  ConstellationCubit cubit,
  ConstellationPresentationFrameHolder holder,
});

Future<_Field> _mountField(WidgetTester tester) async {
  await usePhoneSurface(tester);
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
  final holder = ConstellationPresentationFrameHolder();
  await pumpConstellationBody(
    tester,
    cubit,
    size: kPhoneSurface,
    disableAnimations: true,
    presentationFrameHolder: holder,
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  final context = tester.element(find.byType(ConstellationBody));
  expect(Localizations.localeOf(context), const Locale('ru'));
  expect(MediaQuery.sizeOf(context), kPhoneSurface);
  expect(
    holder.frame?.detail,
    isNot(ConstellationDetailLevel.overview),
    reason: 'the Field opens at the default zoom, not the overview',
  );
  expect(cubit.state.selectedRequestId, isNull);
  expect(cubit.state.selectedPersonId, isNull);
  return (cubit: cubit, holder: holder);
}

Future<void> _selectBeacon(
  WidgetTester tester,
  ConstellationCubit cubit,
  String beaconId,
) async {
  cubit.focusBeacon(beaconId, insets: EdgeInsets.zero);
  await tester.pumpAndSettle();
  final node = find.byKey(TestIds.key(TestIds.graphNode(beaconId)));
  expect(node, findsOneWidget);
  await tester.tap(node);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  expect(cubit.state.selectedRequestId, beaconId);
}

/// A selectable node of the Field.
typedef _Selection = ({
  String label,

  /// Domain id of the selected node.
  String id,
  Future<void> Function(WidgetTester tester, ConstellationCubit cubit) select,

  /// Edges the selection rules must produce on this fixture, each with the
  /// rule that draws it. A sanity check that the fixture exercises the rules;
  /// the edge set under test is what the rules actually paint (see
  /// [_selectionEdges]).
  List<(String, String, String)> ruleEdges,
});

final _postSelection = (
  label: 'a selected Post',
  id: _post,
  select: (WidgetTester tester, ConstellationCubit cubit) =>
      _selectBeacon(tester, cubit, _post),
  ruleEdges: [
    (_viewerId, _amy, 'trust path to the author: hop Ego–amy'),
    (_amy, _bob, 'trust path to the author: hop amy–bob'),
    (_bob, _post, 'ladder: author–Post'),
    (_post, _cat, 'participant: Post–cat (inside)'),
    (_post, _dan, 'participant: Post–dan (forwarded)'),
    (_post, _budded, 'own edge: Post–budded Request'),
  ],
);

final _requestSelection = (
  label: 'a selected Request',
  id: _request,
  select: (WidgetTester tester, ConstellationCubit cubit) =>
      _selectBeacon(tester, cubit, _request),
  ruleEdges: [
    (_viewerId, _amy, 'trust path to the author: hop Ego–amy'),
    (_amy, _bob, 'trust path to the author: hop amy–bob'),
    (_bob, _eve, 'trust path to the author: hop bob–eve'),
    (_eve, _request, 'ladder: author–Request'),
  ],
);

final _personSelection = (
  label: 'a selected person',
  id: _bob,
  select: (WidgetTester tester, ConstellationCubit cubit) async {
    cubit.selectPerson(_bob);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(cubit.state.selectedPersonId, _bob);
  },
  ruleEdges: [
    (_viewerId, _amy, 'trust path to the person: hop Ego–amy'),
    (_amy, _bob, 'trust path to the person: hop amy–bob'),
    (_bob, _eve, 'trust fan of the person: bob–eve'),
    (_bob, _fay, 'trust fan of the person: bob–fay'),
    (_bob, _post, 'ladder: the person–their Post'),
  ],
);

final _selections = [_postSelection, _requestSelection, _personSelection];

/// The selection's edges as the Field's rules paint them at the default
/// zoom: what selecting added to the edges painted with nothing selected
/// ([ambient]), plus any ambient edge that ends at the selected node.
Set<String> _selectionEdges(
  _Selection selection, {
  required Set<String> withSelection,
  required Set<String> ambient,
}) => {
  for (final pair in withSelection)
    if (!ambient.contains(pair) || pair.split('–').contains(selection.id)) pair,
};

Future<void> _zoomTo(
  WidgetTester tester,
  ConstellationCubit cubit,
  double scale,
) async {
  final controller = cubit.graphController;
  controller.zoomBy(scale / controller.cameraScale);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

/// The lowest camera scale the mounted Field allows.
double _lowestScale(WidgetTester tester) => _graphView(tester).minScale;

Future<void> _zoomToLowest(WidgetTester tester, _Field field) async {
  final lowest = _lowestScale(tester);
  await _zoomTo(tester, field.cubit, lowest);
  expect(
    field.cubit.graphController.cameraScale,
    closeTo(lowest, 1e-6),
    reason: 'the camera sits at the lowest scale the Field allows',
  );
  expect(
    field.holder.frame?.detail,
    ConstellationDetailLevel.overview,
    reason: 'at the lowest scale people are overview dots',
  );
}

/// [thickness] (scene px) covers at least one device pixel on screen at
/// devicePixelRatio 1 and 2.
void _expectAtLeastOneDevicePixel(
  double thickness, {
  required double cameraScale,
  required String what,
}) {
  for (final devicePixelRatio in const [1.0, 2.0]) {
    expect(
      thickness * cameraScale * devicePixelRatio,
      greaterThanOrEqualTo(1),
      reason:
          '$what (scale $cameraScale, devicePixelRatio $devicePixelRatio) is '
          '$thickness scene px thick',
    );
  }
}

/// Selects [selection] on a freshly mounted Field and returns the Field, the
/// edges painted before the selection, and the selection's edges.
Future<({_Field field, Set<String> ambient, Set<String> edges})> _select(
  WidgetTester tester,
  _Selection selection,
) async {
  final field = await _mountField(tester);
  final ambient = _visibleEdges(
    _paintedEdges(tester, field.cubit),
  ).keys.toSet();
  await selection.select(tester, field.cubit);
  final withSelection = _visibleEdges(
    _paintedEdges(tester, field.cubit),
  ).keys.toSet();
  final edges = _selectionEdges(
    selection,
    withSelection: withSelection,
    ambient: ambient,
  );
  expect(
    edges,
    containsAll([for (final (x, y, _) in selection.ruleEdges) _pair(x, y)]),
    reason:
        '${selection.label}: the selection rules draw these edges at the '
        'default zoom (${selection.ruleEdges.map((e) => e.$3).join('; ')}), '
        'painted: ${edges.toList()..sort()}',
  );
  return (field: field, ambient: ambient, edges: edges);
}

/// What each edge paints at the default zoom, as (on-screen width in logical
/// px, alpha) per stroke. The default zoom keeps exactly these widths, alphas
/// and stroke counts, for the selection's edges and for the edge that does
/// not touch the selection (Post–budded Request) alike.
const _defaultZoomStrokes = <String, Map<String, List<(double, double)>>>{
  'nothing selected': {
    '$_post–$_budded': [(1.5, 1)],
  },
  'a selected Post': {
    '$_post–$_budded': [(1.5, 0.25)],
    '$_post–$_bob': [(1.5, 1)],
    '$_post–$_cat': [(1.5, 0.25)],
    '$_post–$_dan': [(1.5, 0.25)],
    '$_amy–$_viewerId': [(2, 1)],
    '$_amy–$_bob': [(2, 1)],
  },
  'a selected Request': {
    '$_post–$_budded': [(1.5, 0.25)],
    '$_amy–$_viewerId': [(2, 1)],
    '$_amy–$_bob': [(2, 1)],
    '$_request–$_eve': [(1.5, 1)],
    '$_bob–$_eve': [(2, 1)],
  },
  'a selected person': {
    '$_post–$_budded': [(1.5, 0.25)],
    '$_amy–$_viewerId': [(2, 1)],
    '$_amy–$_bob': [(2, 1)],
    '$_bob–$_eve': [(2, 1)],
    '$_post–$_bob': [(1.5, 1)],
    '$_bob–$_fay': [(2, 1)],
  },
};

Map<String, List<(double, double)>> _onScreenStrokes(
  Map<String, List<_Mark>> painted,
  double scale,
) => {
  for (final MapEntry(:key, :value) in painted.entries)
    if (value.isNotEmpty)
      key: [
        for (final m in value)
          (
            double.parse((m.width * scale).toStringAsFixed(3)),
            double.parse(m.alpha.toStringAsFixed(3)),
          ),
      ],
};

void main() {
  group('Field edges of a selected node across zoom levels, 375x667 in '
      'Russian', () {
    for (final selection in _selections) {
      testWidgets('${selection.label} keeps every edge it shows at the '
          'default zoom painted at the lowest zoom', (tester) async {
        final (:field, :ambient, :edges) = await _select(tester, selection);
        final normal = _visibleEdges(
          _paintedEdges(tester, field.cubit),
        ).keys.toSet();

        await _zoomToLowest(tester, field);
        expect(
          field.cubit.state.selectedRequestId ??
              field.cubit.state.selectedPersonId,
          selection.id,
          reason: 'zooming out keeps the selection',
        );
        expect(
          _scenePairs(field.cubit),
          containsAll(edges),
          reason:
              'the edge scene handed to the painter at the lowest zoom holds '
              'every edge of the selection',
        );

        final lowest = _visibleEdges(
          _paintedEdges(tester, field.cubit),
        ).keys.toSet();
        for (final pair in edges.toList()..sort()) {
          expect(
            lowest,
            contains(pair),
            reason:
                '${selection.label}: $pair must stay painted (visible, '
                'non-zero thickness) at the lowest zoom, painted: '
                '${lowest.toList()..sort()}',
          );
        }
        expect(
          normal.containsAll(lowest),
          isTrue,
          reason:
              'the lowest zoom paints no edge the default zoom does not, '
              'painted: ${lowest.toList()..sort()}',
        );
      });
    }

    for (final selection in _selections) {
      testWidgets('every visible edge of ${selection.label} is at least one '
          'device pixel thick at the default, an intermediate and the lowest '
          'zoom', (tester) async {
        final (:field, :ambient, :edges) = await _select(tester, selection);
        final defaultScale = field.cubit.graphController.cameraScale;
        final lowestScale = _lowestScale(tester);
        expect(lowestScale, lessThan(defaultScale));

        for (final (scale, zoom) in [
          (defaultScale, 'default'),
          ((defaultScale + lowestScale) / 2, 'intermediate'),
          (lowestScale, 'lowest'),
        ]) {
          await _zoomTo(tester, field.cubit, scale);
          final cameraScale = field.cubit.graphController.cameraScale;
          final visible = _visibleEdges(_paintedEdges(tester, field.cubit));
          for (final pair in edges.toList()..sort()) {
            final thickness = visible[pair];
            expect(
              thickness,
              isNotNull,
              reason:
                  '${selection.label}: $pair is painted visibly at the $zoom '
                  'zoom (scale $cameraScale)',
            );
            _expectAtLeastOneDevicePixel(
              thickness!,
              cameraScale: cameraScale,
              what: '${selection.label}: $pair at the $zoom zoom',
            );
          }
        }
      });
    }

    testWidgets('at the default zoom every edge keeps its widths, alphas and '
        'stroke count, with or without a selection', (tester) async {
      final field = await _mountField(tester);
      final scale = field.cubit.graphController.cameraScale;
      expect(
        _onScreenStrokes(_paintedEdges(tester, field.cubit), scale),
        equals(_defaultZoomStrokes['nothing selected']),
        reason: 'nothing selected: (on-screen width, alpha) per stroke',
      );
      for (final selection in _selections) {
        await selection.select(tester, field.cubit);
        expect(field.cubit.graphController.cameraScale, scale);
        expect(
          _onScreenStrokes(_paintedEdges(tester, field.cubit), scale),
          equals(_defaultZoomStrokes[selection.label]),
          reason: '${selection.label}: (on-screen width, alpha) per stroke',
        );
      }
    });

    for (final selection in [_requestSelection, _personSelection]) {
      testWidgets('with ${selection.label}, an edge that does not touch the '
          'selection stays painted at the lowest zoom, at least one device '
          'pixel thick', (tester) async {
        final (:field, :ambient, :edges) = await _select(tester, selection);
        final normal = _visibleEdges(
          _paintedEdges(tester, field.cubit),
        ).keys.toSet();
        final unselected = normal.difference(edges);
        expect(
          unselected,
          contains(_pair(_post, _budded)),
          reason: 'the Post–budded Request edge stays drawn, unselected',
        );

        await _zoomToLowest(tester, field);
        final cameraScale = field.cubit.graphController.cameraScale;
        final lowest = _visibleEdges(_paintedEdges(tester, field.cubit));
        for (final pair in unselected.toList()..sort()) {
          final thickness = lowest[pair];
          expect(
            thickness,
            isNotNull,
            reason:
                'unselected $pair stays painted visibly at the lowest zoom, '
                'painted: ${lowest.keys.toList()..sort()}',
          );
          _expectAtLeastOneDevicePixel(
            thickness!,
            cameraScale: cameraScale,
            what: 'unselected $pair at the lowest zoom',
          );
        }
        expect(
          normal.containsAll(lowest.keys),
          isTrue,
          reason:
              'the lowest zoom paints no edge the default zoom does not, '
              'painted: ${lowest.keys.toList()..sort()}',
        );
      });
    }

    testWidgets('with nothing selected the lowest zoom paints the edges the '
        'default zoom paints, each at least one device pixel thick', (
      tester,
    ) async {
      final field = await _mountField(tester);
      final normal = _visibleEdges(
        _paintedEdges(tester, field.cubit),
      ).keys.toSet();
      expect(
        normal,
        {_pair(_post, _budded)},
        reason: 'nothing selected: only the Post–budded Request edge',
      );

      await _zoomToLowest(tester, field);
      expect(
        _scenePairs(field.cubit),
        {_pair(_post, _budded)},
        reason: 'zooming out leaves the edge scene as it was',
      );
      final cameraScale = field.cubit.graphController.cameraScale;
      final lowest = _visibleEdges(_paintedEdges(tester, field.cubit));
      expect(
        lowest.keys.toSet(),
        normal,
        reason:
            'zooming out with nothing selected paints the same edges, '
            'visibly: painted ${lowest.keys.toList()..sort()}',
      );
      for (final MapEntry(:key, :value) in lowest.entries) {
        _expectAtLeastOneDevicePixel(
          value,
          cameraScale: cameraScale,
          what: '$key with nothing selected at the lowest zoom',
        );
      }
    });
  });

  group('Field edge drawing has a single painter', () {
    test('the client draws Field edges only with ConstellationEdgePainter', () {
      final painterDeclaration = RegExp(
        r'class\s+(\w+)[^{;]*\b(?:implements|extends|with)\b[^{;]*\b'
        r'(?:RepaintingEdgePainter|EdgePainter|LineEdgePainter)\b',
      );
      final painters = <String>[
        for (final file in Directory('lib').listSync(recursive: true))
          if (file is File && file.path.endsWith('.dart'))
            for (final match in painterDeclaration.allMatches(
              file.readAsStringSync(),
            ))
              '${match.group(1)} (${file.path})',
      ];
      expect(
        painters.map((p) => p.split(' ').first),
        ['ConstellationEdgePainter'],
        reason: 'edge painters declared in lib/: $painters',
      );
    });
  });
}
