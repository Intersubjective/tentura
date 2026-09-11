import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/constellation/domain/constellation_consts.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';

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
            expect(revision > BigInt.from(9007199254740991), isTrue);
          }
          final roundTrip =
              ConstellationAnchorRevision.parseDecimalString(
                revision.toString(),
              );
          expect(roundTrip, isA<ConstellationAnchorRevisionParsed>());
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
            expect(
              (validation as ConstellationAnchorTargetInvalid).reason,
              ConstellationAnchorTargetInvalidReason.invalidEgoPerson,
            );
          case 'emptyId':
            expect(validation, isA<ConstellationAnchorTargetInvalid>());
            expect(
              (validation as ConstellationAnchorTargetInvalid).reason,
              ConstellationAnchorTargetInvalidReason.emptyId,
            );
          case 'unknownWireKind':
            expect(validation, isA<ConstellationAnchorTargetInvalid>());
            expect(
              (validation as ConstellationAnchorTargetInvalid).reason,
              ConstellationAnchorTargetInvalidReason.unknownWireKind,
            );
          default:
            fail('unknown expectation ${raw['expect']}');
        }
      });
    }

    test('distinct typed keys for shared raw id', () {
      final rawId = constellationAnchorDistinctTypedKeyFixture['sharedRawId']!;
      final person = ConstellationAnchorTarget.person(rawId);
      final beacon = ConstellationAnchorTarget.beacon(rawId);
      expect(person.mapKey, constellationAnchorDistinctTypedKeyFixture['personMapKey']);
      expect(beacon.mapKey, constellationAnchorDistinctTypedKeyFixture['beaconMapKey']);
      expect(person, isNot(equals(beacon)));
      expect(person.graphNodeId, beacon.graphNodeId);
    });
  });

  group('ConstellationAnchor paint order', () {
    test('later placedAt wins; kind and id tie-break', () {
      final earlier = ConstellationAnchor(
        target: ConstellationAnchorTarget.beacon('B1'),
        position: const ConstellationAnchorPosition(
          xUnits: 0,
          yUnits: 0,
          coordinateSpaceVersion: 1,
        ),
        revision: ConstellationAnchorRevision.zero,
        placedAt: DateTime.utc(2026, 1, 1),
      );
      final laterPerson = ConstellationAnchor(
        target: ConstellationAnchorTarget.person('U1'),
        position: const ConstellationAnchorPosition(
          xUnits: 0,
          yUnits: 0,
          coordinateSpaceVersion: 1,
        ),
        revision: ConstellationAnchorRevision.zero,
        placedAt: DateTime.utc(2026, 1, 2),
      );
      expect(
        ConstellationAnchor.comparePaintOrder(earlier, laterPerson),
        lessThan(0),
      );

      final sameTimeBeacon = ConstellationAnchor(
        target: ConstellationAnchorTarget.beacon('B2'),
        position: const ConstellationAnchorPosition(
          xUnits: 0,
          yUnits: 0,
          coordinateSpaceVersion: 1,
        ),
        revision: ConstellationAnchorRevision.zero,
        placedAt: DateTime.utc(2026, 1, 2),
      );
      final sameTimePerson = ConstellationAnchor(
        target: ConstellationAnchorTarget.person('U2'),
        position: const ConstellationAnchorPosition(
          xUnits: 0,
          yUnits: 0,
          coordinateSpaceVersion: 1,
        ),
        revision: ConstellationAnchorRevision.zero,
        placedAt: DateTime.utc(2026, 1, 2),
      );
      expect(
        ConstellationAnchor.comparePaintOrder(sameTimeBeacon, sameTimePerson),
        lessThan(0),
      );
    });
  });

  group('C2 beacon status filters', () {
    for (final raw in constellationBeaconStatusFixtureCases) {
      test('status ${raw['status']} showClosed=${raw['showClosed']}', () {
        final status = raw['status'] as int;
        final showClosed = raw['showClosed'] as bool;
        final permitted = constellationBeaconStatusPermittedInField(
          status: status,
          showClosed: showClosed,
        );
        expect(permitted, raw['permitted']);
      });
    }
  });

  test('ConstellationAnchorProjection.empty serializes fixture map', () {
    final map = ConstellationAnchorProjection.empty.toFixtureMap();
    expect(map['revision'], '0');
    expect(map['serverFilteredBeaconCount'], 0);
    expect(map['anchorCount'], 0);
  });
}
