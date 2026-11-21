import 'dart:ui' show PictureRecorder;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/constellation_field_unread_glow.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_new_people_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_new_people_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/util/constellation_presentation_frame.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_field_new_ring_layer.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_field_unread_glow_layer.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/constellation_store_fixture.dart';
import '../../support/phone_surface.dart';

const _peerId = 'peer-new';
const _personGraph = 'fp:$_peerId';

ConstellationPresentationFrame _personFrame(
  ConstellationDetailLevel detail,
) {
  final radius = detail == ConstellationDetailLevel.overview
      ? kConstellationOverviewDotDiameter / 2
      : 22.0;
  return ConstellationPresentationFrame(
    snapshot: 'new-glow-$detail',
    cameraRevision: 0,
    detail: detail,
    paintOrder: const [_personGraph],
    bodies: {
      _personGraph: Rect.fromCircle(
        center: const Offset(80, 80),
        radius: radius,
      ),
    },
    labels: const {},
    tapTargets: const {},
    chips: const {},
    forcedLabels: const {},
  );
}

Map<String, String> _glowForField(ConstellationField field) =>
    constellationFieldUnreadGlowGraphIds(
      field: field,
      beaconGraphIdsOnMap: const {},
      personGraphIdsOnMap: const {_personGraph},
    );

ConstellationField _fieldWithNewPeer({required bool isNew}) =>
    ConstellationField(
      loadedAt: DateTime.utc(2026, 11, 4),
      context: '',
      peers: [
        ConstellationPerson(
          id: _peerId,
          displayName: 'New person',
          isNew: isNew,
        ),
      ],
      edges: const [
        ConstellationTrustEdgeEntity(src: 'ego', dst: _peerId, tier: 1),
      ],
      directContactIds: const [_peerId],
    );

class _StubRepository implements ConstellationRepositoryPort {
  _StubRepository(this.field);

  final ConstellationField field;

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async => field;
}

Future<void> _pumpMapHighlights(
  WidgetTester tester, {
  required ConstellationPresentationFrame frame,
  required Map<String, String> glowByGraphId,
  required Set<String> newGraphIds,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      home: SizedBox(
        width: 200,
        height: 200,
        child: Stack(
          children: [
            ConstellationFieldUnreadGlowLayer(
              frame: frame,
              glowByGraphId: glowByGraphId,
              colorForAuthor: (_) => const Color(0xFF625B71),
            ),
            ConstellationFieldNewRingLayer(
              frame: frame,
              newGraphIds: newGraphIds,
              accentColor: const Color(0xFF625B71),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  tearDown(ConstellationFieldUnreadGlowAtlas.resetForTest);

  group('isNew person map highlights (#256 xdle.4)', () {
    for (final detail in [
      ConstellationDetailLevel.close,
      ConstellationDetailLevel.overview,
    ]) {
      testWidgets('isNew draws accent ring and ambient glow at $detail', (
        tester,
      ) async {
        final field = _fieldWithNewPeer(isNew: true);
        final frame = _personFrame(detail);
        await _pumpMapHighlights(
          tester,
          frame: frame,
          glowByGraphId: _glowForField(field),
          newGraphIds: const {_personGraph},
        );
        expect(
          find.byKey(const ValueKey('constellation.fieldNewRings')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('constellation.fieldUnreadGlow')),
          findsOneWidget,
        );
      });
    }

    testWidgets('cleared isNew removes ring and glow layers', (tester) async {
      final frame = _personFrame(ConstellationDetailLevel.close);
      final opened = _fieldWithNewPeer(isNew: false);
      await _pumpMapHighlights(
        tester,
        frame: frame,
        glowByGraphId: _glowForField(opened),
        newGraphIds: const {},
      );

      expect(
        find.byKey(const ValueKey('constellation.fieldNewRings')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('constellation.fieldUnreadGlow')),
        findsNothing,
      );
    });

    testWidgets('isNew with unread items draws one glow at overview', (
      tester,
    ) async {
      final field = _fieldWithNewPeer(isNew: true).copyWith(
        posts: [
          ConstellationPost(
            id: 'post-1',
            authorId: _peerId,
            rootExcerpt: 'Unread',
            lastActivityAt: DateTime.utc(2026, 11, 5),
            hasUnread: true,
          ),
        ],
      );
      final glow = _glowForField(field);
      expect(glow.keys, hasLength(1));
      expect(glow.keys.single, _personGraph);

      await _pumpMapHighlights(
        tester,
        frame: _personFrame(ConstellationDetailLevel.overview),
        glowByGraphId: glow,
        newGraphIds: const {_personGraph},
      );
      expect(
        find.byKey(const ValueKey('constellation.fieldUnreadGlow')),
        findsOneWidget,
      );
    });

    testWidgets('person without isNew or unread draws no glow layer', (
      tester,
    ) async {
      final field = _fieldWithNewPeer(isNew: false);
      await _pumpMapHighlights(
        tester,
        frame: _personFrame(ConstellationDetailLevel.overview),
        glowByGraphId: _glowForField(field),
        newGraphIds: const {},
      );
      expect(
        find.byKey(const ValueKey('constellation.fieldUnreadGlow')),
        findsNothing,
      );
    });

    test('painters draw ring and glow for the same person body', () {
      final frame = _personFrame(ConstellationDetailLevel.close);
      final ringRecorder = PictureRecorder();
      ConstellationFieldNewRingPainter(
        frame: frame,
        newGraphIds: const {_personGraph},
        accentColor: const Color(0xFF625B71),
        gap: 4,
        minTrustRadius: 14,
        badgeDiameter: 18,
      ).paint(Canvas(ringRecorder), const Size(200, 200));

      final atlas = ConstellationFieldUnreadGlowAtlas.instance;
      final glowRecorder = PictureRecorder();
      ConstellationFieldUnreadGlowPainter(
        frame: frame,
        glowSites: const {
          _personGraph: (authorId: _peerId, opacity: 1),
        },
        colorForAuthor: (_) => const Color(0xFF625B71),
        atlas: atlas,
        spread: 2.15,
        alphaDark: 0.34,
        alphaLight: TenturaTokens.light.fieldUnreadGlowAlphaLight,
        unreadDotSize: 10,
        unreadDotColor: Colors.blue,
        isDark: false,
        highContrast: false,
        pulseBoost: 1,
      ).paint(Canvas(glowRecorder), const Size(200, 200));

      expect(ringRecorder.endRecording(), isNotNull);
      expect(glowRecorder.endRecording(), isNotNull);
    });

    test('selectPerson acknowledge clears isNew and glow resolution', () async {
      final field = _fieldWithNewPeer(isNew: true);
      final fixture = ConstellationStoreFixture(
        _StubRepository(field),
        accountId: 'ego',
      );
      final port = _RecordingPort([]);
      final case_ = ConstellationNewPeopleCase(
        port,
        fixture.store,
        env: const Env.fromEnvironment(),
        logger: Logger('test'),
      );
      final cubit = ConstellationCubit(
        case_: fixture.store,
        viewer: const Profile(id: 'ego', displayName: 'Viewer'),
        loadOnCreate: false,
        newPeopleCase: case_,
      );
      addTearDown(() async {
        if (!cubit.isClosed) await cubit.close();
      });
      await cubit.load();

      expect(_glowForField(cubit.state.field!), isNotEmpty);
      cubit.selectPerson(_peerId);
      await Future<void>.delayed(Duration.zero);

      expect(cubit.fieldPersonById(_peerId)!.isNew, isFalse);
      expect(_glowForField(cubit.state.field!), isEmpty);
    });

    testWidgets('375×667 RU: isNew glow layer lays out without overflow', (
      tester,
    ) async {
      await usePhoneSurface(tester);
      final field = _fieldWithNewPeer(isNew: true);
      await tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('ru'),
          home: SizedBox(
            width: 375,
            height: 667,
            child: ConstellationFieldUnreadGlowLayer(
              frame: _personFrame(ConstellationDetailLevel.overview),
              glowByGraphId: _glowForField(field),
              colorForAuthor: (_) => const Color(0xFF625B71),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}

final class _RecordingPort implements ConstellationNewPeoplePort {
  _RecordingPort(this.calls);

  final List<List<String>> calls;

  @override
  Future<void> acknowledgeNew(Iterable<String> peerIds) async {
    calls.add(peerIds.toList());
  }
}
