import 'package:test/test.dart';
import 'package:tentura_server/consts/constellation_consts.dart';
import 'package:tentura_server/domain/entity/constellation_anchor.dart';
import 'package:tentura_server/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura_server/domain/entity/constellation_field.dart';

import 'constellation_anchor_contract_fixtures.dart';

void main() {
  group('ConstellationAnchorPosition', () {
    for (final raw in constellationAnchorCoordinateFixtureCases) {
      test('fixture ${raw['id']}', () {
        final result = ConstellationAnchorPosition.fromFixtureMap(raw);
        switch (raw['expect']) {
          case 'valid':
            expect(result, isA<ConstellationAnchorPositionValid>());
          case 'outOfRange':
            expect(result, isA<ConstellationAnchorPositionInvalid>());
            expect(
              (result as ConstellationAnchorPositionInvalid).reason,
              ConstellationAnchorPositionInvalidReason.outOfRange,
            );
          case 'nonFinite':
            expect(result, isA<ConstellationAnchorPositionInvalid>());
            expect(
              (result as ConstellationAnchorPositionInvalid).reason,
              ConstellationAnchorPositionInvalidReason.nonFinite,
            );
          case 'unsupportedCoordinateSpace':
            expect(result, isA<ConstellationAnchorPositionInvalid>());
            expect(
              (result as ConstellationAnchorPositionInvalid).reason,
              ConstellationAnchorPositionInvalidReason
                  .unsupportedCoordinateSpace,
            );
          default:
            fail('unknown expectation ${raw['expect']}');
        }
      });
    }

    test('v1 geometry round-trip at canvas centre', () {
      const xUnits = 2.5;
      const yUnits = -1.25;
      final render = constellationV1UnitsToRenderCentre(
        renderCentreX: kConstellationCanvasCentre,
        renderCentreY: kConstellationCanvasCentre,
        xUnits: xUnits,
        yUnits: yUnits,
      );
      final back = constellationRenderCentreToV1Units(
        renderCentreX: kConstellationCanvasCentre,
        renderCentreY: kConstellationCanvasCentre,
        renderX: render.x,
        renderY: render.y,
      );
      expect(back.xUnits, closeTo(xUnits, 1e-9));
      expect(back.yUnits, closeTo(yUnits, 1e-9));
    });
  });

  group('ConstellationAnchorRevision', () {
    for (final raw in constellationAnchorRevisionFixtureCases) {
      test('wire ${raw['wire']}', () {
        final parsed = ConstellationAnchorRevision.parseDecimalString(
          raw['wire'] as String,
        );
        if (raw['expectValid'] == true) {
          expect(parsed, isA<ConstellationAnchorRevisionParsed>());
          final revision = (parsed as ConstellationAnchorRevisionParsed)
              .revision
              .value;
          if (raw['exceedsJsSafeInteger'] == true) {
            expect(revision > BigInt.from(9007199254740992), isTrue);
          }
        } else {
          expect(parsed, isA<ConstellationAnchorRevisionMalformed>());
        }
      });
    }
  });

  group('ConstellationAnchorTarget', () {
    for (final raw in constellationAnchorTargetFixtureCases) {
      test('${raw['kindWire']}/${raw['targetId']}', () {
        final target = ConstellationAnchorTarget.tryFromWire(
          kindWire: raw['kindWire'] as String,
          targetId: raw['targetId'] as String,
        );
        final validation = validateConstellationAnchorTarget(
          target: target,
          viewerId: raw['viewerId'] as String,
        );
        switch (raw['expect']) {
          case 'valid':
            expect(validation, isA<ConstellationAnchorTargetValid>());
          case 'invalidEgoPerson':
            expect(validation, isA<ConstellationAnchorTargetInvalid>());
          case 'emptyId':
            expect(validation, isA<ConstellationAnchorTargetInvalid>());
          case 'unknownWireKind':
            expect(validation, isA<ConstellationAnchorTargetInvalid>());
          default:
            fail('unknown expectation ${raw['expect']}');
        }
      });
    }

    test('distinct typed keys for shared raw id', () {
      final rawId = constellationAnchorDistinctTypedKeyFixture['sharedRawId']!;
      final person = ConstellationAnchorTarget.person(rawId);
      final beacon = ConstellationAnchorTarget.beacon(rawId);
      expect(person.mapKey, isNot(equals(beacon.mapKey)));
    });
  });

  group('C2 beacon status filters', () {
    for (final raw in constellationBeaconStatusFixtureCases) {
      test('status ${raw['status']}', () {
        expect(
          constellationBeaconStatusPermittedInField(
            status: raw['status'] as int,
            showClosed: raw['showClosed'] as bool,
          ),
          raw['permitted'],
        );
      });
    }
  });

  test('ConstellationFieldSnapshot defaults empty anchor projection', () {
    final snapshot = ConstellationFieldSnapshot(
      loadedAt: DateTime.utc(2026),
      context: '',
      peers: const [],
      edges: const [],
      requests: const [],
      peersCapped: false,
      requestsCapped: false,
    );
    expect(snapshot.anchorProjection, ConstellationAnchorProjection.empty);
  });
}
