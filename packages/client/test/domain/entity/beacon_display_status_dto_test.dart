import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon_coordination_phase.dart';
import 'package:tentura/domain/entity/beacon_display_status_dto.dart';

Map<String, dynamic> _json({
  String phase = 'wrappingUp',
  String suggestedAction = 'none',
  String slot2Kind = 'reviewCountdown',
  String tier = 'coordination',
}) => {
  'beaconId': 'b1',
  'status': BeaconStatus.reviewOpen.smallintValue,
  'phase': phase,
  'suggestedAction': suggestedAction,
  'slot2Kind': slot2Kind,
  'tier': tier,
};

void main() {
  group('beaconDisplayStatusFromGql', () {
    test('parses known enum values', () {
      final dto = beaconDisplayStatusFromGql(
        _json(suggestedAction: 'reviewOffers'),
      );
      expect(dto.phase, BeaconCoordinationPhase.wrappingUp);
      expect(dto.suggestedAction, BeaconPhasePrimaryAction.reviewOffers);
      expect(dto.slot2Kind, BeaconPhaseSlot2Kind.reviewCountdown);
      expect(dto.tier, BeaconDisplayTier.coordination);
    });

    test('unknown primary action (removed reviewContributions) falls back to '
        'none without throwing', () {
      final dto = beaconDisplayStatusFromGql(
        _json(suggestedAction: 'reviewContributions'),
      );
      expect(dto.suggestedAction, BeaconPhasePrimaryAction.none);
      expect(dto.phase, BeaconCoordinationPhase.wrappingUp);
      expect(dto.status, BeaconStatus.reviewOpen);
    });

    test('unknown phase yields a valid phase without throwing', () {
      late BeaconDisplayStatusDto dto;
      expect(
        () => dto = beaconDisplayStatusFromGql(_json(phase: 'someNewPhase')),
        returnsNormally,
      );
      expect(BeaconCoordinationPhase.values, contains(dto.phase));
    });

    test('unknown slot2 kind falls back to none without throwing', () {
      final dto = beaconDisplayStatusFromGql(_json(slot2Kind: 'newSlotKind'));
      expect(dto.slot2Kind, BeaconPhaseSlot2Kind.none);
    });

    test('unknown tier yields a valid tier without throwing', () {
      late BeaconDisplayStatusDto dto;
      expect(
        () => dto = beaconDisplayStatusFromGql(_json(tier: 'newTier')),
        returnsNormally,
      );
      expect(BeaconDisplayTier.values, contains(dto.tier));
    });

    test('every enum unknown at once still yields a usable dto', () {
      final dto = beaconDisplayStatusFromGql(
        _json(
          phase: 'x1',
          suggestedAction: 'x2',
          slot2Kind: 'x3',
          tier: 'x4',
        ),
      );
      expect(dto.beaconId, 'b1');
      expect(dto.suggestedAction, BeaconPhasePrimaryAction.none);
      expect(dto.slot2Kind, BeaconPhaseSlot2Kind.none);
      expect(dto.toPhaseResult().suggestedAction, BeaconPhasePrimaryAction.none);
    });

    test('a single unknown value is reported through logging as exactly one entry', () {
      final records = <LogRecord>[];
      final previousLevel = Logger.root.level;
      Logger.root.level = Level.ALL;
      final sub = Logger.root.onRecord.listen(records.add);
      addTearDown(() async {
        await sub.cancel();
        Logger.root.level = previousLevel;
      });

      beaconDisplayStatusFromGql(_json(suggestedAction: 'reviewContributions'));

      final reported = records.where((r) => r.level >= Level.INFO).toList();
      expect(reported, hasLength(1));
      expect(
        reported.single.message,
        contains('reviewContributions'),
      );
    });

    test('known values are not reported through logging', () {
      final records = <LogRecord>[];
      final previousLevel = Logger.root.level;
      Logger.root.level = Level.ALL;
      final sub = Logger.root.onRecord.listen(records.add);
      addTearDown(() async {
        await sub.cancel();
        Logger.root.level = previousLevel;
      });

      beaconDisplayStatusFromGql(_json());

      expect(records.where((r) => r.level >= Level.INFO), isEmpty);
    });
  });
}
