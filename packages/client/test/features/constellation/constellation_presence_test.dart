import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:tentura/data/repository/presence_repository.dart';
import 'package:tentura/data/service/remote_api_service.dart'
    show WebSocketState;
import 'package:tentura/data/service/user_presence_service.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/constellation/domain/constellation_presence.dart';
import 'package:tentura/features/constellation/domain/constellation_trust_chain.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_presence_cubit.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_presentation_frame.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_node_ring_layer.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_presence_halo_layer.dart';
import 'package:tentura/ui/test_ids.dart';

import 'fixtures/constellation_reference_fixture.dart';

/// A presence service fed by pushed messages; records every watch sent.
final class _PresenceHarness {
  _PresenceHarness() {
    repository = PresenceRepository(
      UserPresenceService.forTesting(
        messages: _messages.stream,
        connectionState: const Stream<WebSocketState>.empty(),
        send: (raw) {
          final json = jsonDecode(raw) as Map<String, dynamic>;
          final payload = json['payload'] as Map<String, dynamic>;
          final params = payload['params'] as Map<String, dynamic>;
          sent.add({...(params['peer_ids'] as List).cast<String>()});
        },
      ),
    );
  }

  final _messages = StreamController<Map<String, dynamic>>.broadcast();
  late final PresenceRepository repository;

  /// Each watch update's full peer list, in order.
  final sent = <Set<String>>[];

  void push(Map<String, String> statuses) => _messages.add({
    'type': 'subscription',
    'path': 'user_presence',
    'payload': {
      'intent': 'watch_updates',
      'events': [
        for (final MapEntry(key: id, value: status) in statuses.entries)
          {'user_id': id, 'status': status},
      ],
    },
  });

  Future<void> dispose() => _messages.close();
}

ConstellationTrustEdgeEntity _edge(String src, String dst) =>
    ConstellationTrustEdgeEntity(src: src, dst: dst, tier: 1);

/// Maria trusts back (a friend), Yuri is only trusted, Igor is no contact.
ConstellationField _field() => ConstellationField(
  loadedAt: DateTime.utc(2026, 10, 23),
  context: '',
  peers: const [
    ConstellationPerson(id: 'm', displayName: 'Maria'),
    ConstellationPerson(id: 'y', displayName: 'Yuri'),
    ConstellationPerson(id: 'i', displayName: 'Igor'),
  ],
  edges: [
    _edge('ego', 'm'),
    _edge('m', 'ego'),
    _edge('ego', 'y'),
    _edge('m', 'i'),
  ],
  directContactIds: const ['m', 'y'],
);

ConstellationPresentationFrame _frameOf(
  List<(GraphNodeId, Offset, double)> nodes, {
  ConstellationDetailLevel detail = ConstellationDetailLevel.bare,
  bool cullToViewport = true,
}) => computeConstellationPresentationFrame(
  snapshot: const Object(),
  cameraRevision: 1,
  detail: detail,
  viewport: const Size(400, 400),
  nodesInPaintOrder: [
    for (final (id, centre, diameter) in nodes)
      ConstellationFrameNodeInput(
        id: id,
        centre: centre,
        bodyDiameter: diameter,
        badgeOverhang: 0,
        labelSize: Size.zero,
        priority: 2,
        ring: 1,
        labelCandidate: false,
      ),
  ],
  chips: const [],
  gap: 2,
  minTarget: kMinInteractiveDimension,
  rtl: false,
  cullToViewport: cullToViewport,
);

void main() {
  group('constellationPresenceWatchIds', () {
    test('asks for the direct contacts on the map, never the viewer', () async {
      final cubit = await loadReferenceCubit(field: _field());
      addTearDown(cubit.close);
      final state = cubit.state;
      final ids = constellationPresenceWatchIds(
        field: state.field,
        composition: state.composition,
        viewerId: 'ego',
      );
      expect(ids, {'m', 'y'});
    });

    test(
      'a contact the composition leaves off the map is not asked for',
      () async {
        final cubit = await loadReferenceCubit(field: _field());
        addTearDown(cubit.close);
        final state = cubit.state;
        final field = state.field!.copyWith(
          directContactIds: const ['m', 'y', 'ghost'],
        );
        expect(
          constellationPresenceWatchIds(
            field: field,
            composition: state.composition,
            viewerId: 'ego',
          ),
          isNot(contains('ghost')),
        );
      },
    );

    test('nothing before the field is composed', () {
      expect(
        constellationPresenceWatchIds(
          field: null,
          composition: null,
          viewerId: 'ego',
        ),
        isEmpty,
      );
    });
  });

  group('ConstellationPresenceCubit', () {
    late _PresenceHarness harness;
    late StreamController<Set<String>> watchIds;

    setUp(() {
      harness = _PresenceHarness();
      watchIds = StreamController<Set<String>>();
    });

    tearDown(() async {
      await watchIds.close();
      await harness.dispose();
    });

    ConstellationPresenceCubit make({Set<String> initial = const {}}) =>
        ConstellationPresenceCubit(
          watchIds: watchIds.stream,
          initialWatchIds: initial,
          repository: harness.repository,
        );

    test('watches the set once and again only when it changes', () async {
      final cubit = make(initial: {'m', 'y'});
      addTearDown(cubit.close);
      expect(harness.sent, [
        {'m', 'y'},
      ]);

      watchIds
        ..add({'y', 'm'})
        ..add({'m', 'y'});
      await pumpEventQueue();
      expect(harness.sent, hasLength(1), reason: 'same set: no churn');

      watchIds.add({'m'});
      await pumpEventQueue();
      expect(harness.sent.last, {'m'});
      expect(cubit.watchedIds, {'m'});
    });

    test('state is who of the watched people is online', () async {
      final cubit = make(initial: {'m', 'y'});
      addTearDown(cubit.close);

      harness.push({'m': 'online', 'y': 'inactive', 'stranger': 'online'});
      await pumpEventQueue();
      expect(cubit.state, {'m'});
      expect(cubit.isOnline('m'), isTrue);
      expect(cubit.isOnline('y'), isFalse, reason: 'away is not online');
      expect(cubit.isOnline('stranger'), isFalse);

      harness.push({'m': 'offline'});
      await pumpEventQueue();
      expect(cubit.state, isEmpty);
    });

    test('a person already online shows as soon as they are watched', () async {
      // Another screen watches m, so the service already knows m is online.
      harness.repository.watch('friends', {'m'});
      final cubit = make();
      addTearDown(cubit.close);
      harness.push({'m': 'online'});
      await pumpEventQueue();
      expect(cubit.state, isEmpty);

      watchIds.add({'m'});
      await pumpEventQueue();
      expect(cubit.state, {'m'});

      watchIds.add({'y'});
      await pumpEventQueue();
      expect(cubit.state, isEmpty, reason: 'm left the field');
    });

    test('close drops only the field watch', () async {
      harness.repository.watch('friends', {'z'});
      final cubit = make(initial: {'m'});
      expect(harness.sent.last, {'z', 'm'});
      await cubit.close();
      expect(harness.sent.last, {'z'});
    });

    test('closing the only watch clears it on the server', () async {
      final cubit = make(initial: {'m'});
      await cubit.close();
      expect(harness.sent.last, isEmpty);
    });

    test('a hidden field watches nobody; shown again, its people', () async {
      harness.repository.watch('friends', {'z'});
      final cubit = make(initial: {'m'});
      addTearDown(cubit.close);
      harness.push({'m': 'online'});
      await pumpEventQueue();
      expect(cubit.state, {'m'});

      cubit.setVisible(false);
      expect(harness.sent.last, {'z'}, reason: 'only the field watch drops');
      expect(cubit.state, isEmpty);

      // People arriving while hidden are watched once it shows again.
      watchIds.add({'m', 'y'});
      await pumpEventQueue();
      expect(harness.sent.last, {'z'});

      cubit.setVisible(true);
      expect(harness.sent.last, {'z', 'm', 'y'});
      // Unwatched statuses are dropped (#533); the server answers the new
      // watch with a fresh snapshot.
      harness.push({'m': 'online'});
      await pumpEventQueue();
      expect(cubit.state, {'m'});
    });

    test('an emptied field drops its watch', () async {
      harness.repository.watch('friends', {'z'});
      final cubit = make(initial: {'m'});
      addTearDown(cubit.close);
      watchIds.add(const {});
      await pumpEventQueue();
      expect(harness.sent.last, {'z'});
    });
  });

  group('halo geometry', () {
    test('sits outside the body and scales with it, with a floor', () {
      final small = constellationPresenceHaloGeometry(
        body: Rect.fromCircle(center: Offset.zero, radius: 4),
      );
      final large = constellationPresenceHaloGeometry(
        body: Rect.fromCircle(center: Offset.zero, radius: 40),
      );
      expect(small.innerRadius, greaterThan(4));
      expect(large.innerRadius, greaterThan(40));
      expect(small.width, kConstellationPresenceHaloMinWidth);
      expect(large.width, 40 * kConstellationPresenceHaloWidthRatio);
      expect(large.width, greaterThan(small.width));
    });
  });

  group('halo layer', () {
    Finder halos() => find.byKey(const ValueKey('constellation.presenceHalos'));

    Future<void> pumpLayer(
      WidgetTester tester, {
      required ConstellationPresentationFrame frame,
      required Set<GraphNodeId> online,
      Set<GraphNodeId> dimmed = const {},
      bool disableAnimations = false,
      bool tickersEnabled = true,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(800, 600),
              disableAnimations: disableAnimations,
            ),
            child: TickerMode(
              enabled: tickersEnabled,
              child: Scaffold(
                body: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 400,
                    height: 400,
                    child: ConstellationPresenceHaloLayer(
                      frame: frame,
                      onlineGraphIds: online,
                      dimmedGraphIds: dimmed,
                      viewport: const Size(400, 400),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    ConstellationPresenceHaloPainter painterOf(WidgetTester tester) =>
        tester.widget<CustomPaint>(halos()).painter!
            as ConstellationPresenceHaloPainter;

    testWidgets('an online person gets a halo in the positive colour', (
      tester,
    ) async {
      final frame = _frameOf([('p', const Offset(200, 200), 40)]);
      await pumpLayer(
        tester,
        frame: frame,
        online: {'p'},
        disableAnimations: true,
      );
      final tt = tester.element(halos()).tt;
      final g = painterOf(tester).geometryOf('p')!;
      expect(g.innerRadius, greaterThan(20), reason: 'never over the node');
      // Still (reduced motion): the band fully out.
      expect(
        halos(),
        paints
          ..circle(
            x: 200,
            y: 200,
            radius: g.innerRadius + g.width * 0.3,
            strokeWidth: g.width * 0.6,
            style: PaintingStyle.stroke,
          )
          ..circle(
            x: 200,
            y: 200,
            radius: g.innerRadius + g.width * 0.8,
            strokeWidth: g.width * 0.4,
            style: PaintingStyle.stroke,
          ),
      );
      expect(painterOf(tester).color, tt.good);
    });

    testWidgets('off the selected trust chain the halo fades', (tester) async {
      final frame = _frameOf([
        ('on', const Offset(100, 200), 40),
        ('off', const Offset(300, 200), 40),
      ]);
      await pumpLayer(
        tester,
        frame: frame,
        online: {'on', 'off'},
        dimmed: {'off'},
        disableAnimations: true,
      );
      final good = tester.element(halos()).tt.good;
      // Same frame, nothing dimmed: both full.
      await pumpLayer(
        tester,
        frame: frame,
        online: {'on', 'off'},
        disableAnimations: true,
      );
      expect(
        halos(),
        paints
          ..circle(x: 100, y: 200, color: good.withValues(alpha: 0.9))
          ..circle(x: 100, y: 200, color: good.withValues(alpha: 0.3))
          ..circle(x: 300, y: 200, color: good.withValues(alpha: 0.9)),
      );

      // The chain selected: the halo off it repaints faded.
      await pumpLayer(
        tester,
        frame: frame,
        online: {'on', 'off'},
        dimmed: {'off'},
        disableAnimations: true,
      );
      expect(
        halos(),
        paints
          ..circle(x: 100, y: 200, color: good.withValues(alpha: 0.9))
          ..circle(x: 100, y: 200, color: good.withValues(alpha: 0.3))
          ..circle(
            x: 300,
            y: 200,
            color: good.withValues(
              alpha: 0.9 * kConstellationTrustChainDimOpacity,
            ),
          )
          ..circle(
            x: 300,
            y: 200,
            color: good.withValues(
              alpha: 0.3 * kConstellationTrustChainDimOpacity,
            ),
          ),
      );
    });

    testWidgets('the halo scales with the body on screen', (tester) async {
      final frame = _frameOf([
        ('far', const Offset(100, 100), 8),
        ('near', const Offset(250, 250), 80),
      ]);
      await pumpLayer(
        tester,
        frame: frame,
        online: {'far', 'near'},
        disableAnimations: true,
      );
      final painter = painterOf(tester);
      final far = painter.geometryOf('far')!;
      final near = painter.geometryOf('near')!;
      expect(far.innerRadius, greaterThan(4));
      expect(near.innerRadius, greaterThan(40));
      expect(near.width / far.width, greaterThan(2));
      expect(
        far.width,
        greaterThanOrEqualTo(kConstellationPresenceHaloMinWidth),
      );
    });

    testWidgets('offline people get nothing', (tester) async {
      final frame = _frameOf([
        ('on', const Offset(100, 100), 40),
        ('off', const Offset(300, 300), 40),
      ]);
      await pumpLayer(tester, frame: frame, online: const {});
      expect(halos(), findsNothing);

      await pumpLayer(
        tester,
        frame: frame,
        online: {'on'},
        disableAnimations: true,
      );
      expect(painterOf(tester).geometryOf('off'), isNull);
      expect(
        halos(),
        isNot(paints..circle(x: 300, y: 300)),
      );
    });

    testWidgets('it hugs the body; the trust disc draws over it', (
      tester,
    ) async {
      final frame = _frameOf([
        ('p', const Offset(200, 200), 40),
      ], detail: ConstellationDetailLevel.normal);
      await pumpLayer(
        tester,
        frame: frame,
        online: {'p'},
        disableAnimations: true,
      );
      final g = painterOf(tester).geometryOf('p')!;
      expect(g.innerRadius, greaterThan(20));
      expect(g.innerRadius, lessThan(20 * 1.2), reason: 'no ring to clear');
    });

    testWidgets('it pulses while an online person is on screen', (
      tester,
    ) async {
      final frame = _frameOf([('p', const Offset(200, 200), 40)]);
      await pumpLayer(tester, frame: frame, online: {'p'});
      final controller = (painterOf(tester).pulse! as CurvedAnimation).parent;
      expect(controller.isAnimating, isTrue);
      final before = controller.value;
      await tester.pump(kConstellationPresencePulseHalfPeriod ~/ 2);
      expect(controller.value, isNot(before));

      // Panned away: the ticker stops.
      final away = frame.translated(
        snapshot: const Object(),
        cameraRevision: 2,
        delta: const Offset(1000, 1000),
      );
      await pumpLayer(tester, frame: away, online: {'p'});
      expect(controller.isAnimating, isFalse);
    });

    testWidgets('a halo just off screen does not keep the ticker running', (
      tester,
    ) async {
      // Body radius 20 centred 40 px left of the viewport: the band ends
      // well before x = 0.
      // The field places off-screen nodes too (a pan may reveal them).
      final frame = _frameOf([
        ('p', const Offset(-40, 200), 40),
      ], cullToViewport: false);
      await pumpLayer(tester, frame: frame, online: {'p'});
      final painter = painterOf(tester);
      expect(painter.geometryOf('p')!.outerRadius, lessThan(40));
      final controller = (painter.pulse! as CurvedAnimation).parent;
      expect(controller.isAnimating, isFalse);
    });

    testWidgets('reduced motion draws it still, with no ticker', (
      tester,
    ) async {
      final frame = _frameOf([('p', const Offset(200, 200), 40)]);
      await pumpLayer(
        tester,
        frame: frame,
        online: {'p'},
        disableAnimations: true,
      );
      expect(painterOf(tester).pulse, isNull);
      expect(SchedulerBinding.instance.transientCallbackCount, 0);
    });

    testWidgets('a hidden field (tickers off) does not pulse', (tester) async {
      final frame = _frameOf([('p', const Offset(200, 200), 40)]);
      await pumpLayer(
        tester,
        frame: frame,
        online: {'p'},
        tickersEnabled: false,
      );
      expect(SchedulerBinding.instance.transientCallbackCount, 0);
    });
  });

  group('on the field', () {
    testWidgets('an online friend gets a halo and an "Online" label', (
      tester,
    ) async {
      final harness = _PresenceHarness();
      addTearDown(harness.dispose);
      final cubit = await loadReferenceCubit(field: _field());
      addTearDown(cubit.close);
      final watch = StreamController<Set<String>>();
      addTearDown(watch.close);
      final presence = ConstellationPresenceCubit(
        watchIds: watch.stream,
        initialWatchIds: constellationPresenceWatchIds(
          field: cubit.state.field,
          composition: cubit.state.composition,
          viewerId: 'ego',
        ),
        repository: harness.repository,
      );
      addTearDown(presence.close);

      await pumpConstellationBody(
        tester,
        cubit,
        size: const Size(1200, 900),
        locale: const Locale('en'),
        presence: presence,
      );
      final maria = find.byKey(TestIds.key(TestIds.graphNode('m')));
      expect(maria, findsOneWidget);
      expect(tester.getSemantics(maria).label, isNot(contains('Online')));
      expect(
        find.byKey(const ValueKey('constellation.presenceHalos')),
        findsNothing,
      );

      harness.push({'m': 'online', 'y': 'offline'});
      await tester.pump();
      await tester.pump();

      expect(
        tester.getSemantics(maria).label,
        allOf(contains('Maria'), contains('Online')),
      );
      final yuri = find.byKey(TestIds.key(TestIds.graphNode('y')));
      expect(tester.getSemantics(yuri).label, isNot(contains('Online')));
      final painter =
          tester
                  .widget<CustomPaint>(
                    find.byKey(const ValueKey('constellation.presenceHalos')),
                  )
                  .painter!
              as ConstellationPresenceHaloPainter;
      expect(painter.onlineGraphIds, {'fp:m'});

      harness.push({'m': 'offline'});
      await tester.pump();
      await tester.pump();
      expect(tester.getSemantics(maria).label, isNot(contains('Online')));
      expect(
        find.byKey(const ValueKey('constellation.presenceHalos')),
        findsNothing,
      );
    });
  });
}
