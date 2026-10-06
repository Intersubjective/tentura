import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/domain/coordination/derive_beacon_display_status.dart';

void main() {
  group('deriveBeaconDisplayStatus', () {
    test('draft phase', () {
      final r = deriveBeaconDisplayStatus(
        BeaconDisplayStatusInput(
          status: BeaconStatus.draft,
          tier: BeaconDisplayTier.coordination,
        ),
      );
      expect(r.phase, BeaconDisplayPhase.draft);
    });

    test('needsMoreHelp from persisted status', () {
      final r = deriveBeaconDisplayStatus(
        BeaconDisplayStatusInput(
          status: BeaconStatus.needsMoreHelp,
          tier: BeaconDisplayTier.coordination,
        ),
      );
      expect(r.phase, BeaconDisplayPhase.needsMoreHelp);
    });

    test('enoughHelp with unreviewed offers stays enoughHelpInMotion', () {
      final r = deriveBeaconDisplayStatus(
        BeaconDisplayStatusInput(
          status: BeaconStatus.enoughHelp,
          tier: BeaconDisplayTier.coordination,
          hasUnreviewedOffers: true,
          helpOfferCount: 2,
        ),
      );
      expect(r.phase, BeaconDisplayPhase.enoughHelpInMotion);
      expect(r.phase, isNot(BeaconDisplayPhase.offersAwaitingAuthor));
      expect(r.suggestedAction, BeaconDisplayPrimaryAction.reviewOffers);
    });

    test('enoughHelp with reviewed offers stays enoughHelpInMotion', () {
      final r = deriveBeaconDisplayStatus(
        BeaconDisplayStatusInput(
          status: BeaconStatus.enoughHelp,
          tier: BeaconDisplayTier.coordination,
          hasUnreviewedOffers: false,
          helpOfferCount: 2,
        ),
      );
      expect(r.phase, BeaconDisplayPhase.enoughHelpInMotion);
    });

    test('enoughHelp public tier suggests forward', () {
      final r = deriveBeaconDisplayStatus(
        BeaconDisplayStatusInput(
          status: BeaconStatus.enoughHelp,
          tier: BeaconDisplayTier.public,
        ),
      );
      expect(r.phase, BeaconDisplayPhase.enoughHelpInMotion);
      expect(r.suggestedAction, BeaconDisplayPrimaryAction.forward);
    });

    test('blocked when open blocker signal', () {
      final r = deriveBeaconDisplayStatus(
        BeaconDisplayStatusInput(
          status: BeaconStatus.open,
          tier: BeaconDisplayTier.coordination,
          hasOpenBlocker: true,
        ),
      );
      expect(r.phase, BeaconDisplayPhase.blocked);
    });

    group('wrapping-up (reviewOpen) Request', () {
      test('coordination viewer gets no suggested action', () {
        final r = deriveBeaconDisplayStatus(
          BeaconDisplayStatusInput(
            status: BeaconStatus.reviewOpen,
            tier: BeaconDisplayTier.coordination,
          ),
        );
        expect(r.phase, BeaconDisplayPhase.wrappingUp);
        expect(r.suggestedAction, BeaconDisplayPrimaryAction.none);
      });

      test('keeps the review countdown slot for coordination viewers', () {
        final r = deriveBeaconDisplayStatus(
          BeaconDisplayStatusInput(
            status: BeaconStatus.reviewOpen,
            tier: BeaconDisplayTier.coordination,
            reviewClosesAt: DateTime.utc(2026, 10, 10),
          ),
        );
        expect(r.slot2Kind, BeaconDisplaySlot2Kind.reviewCountdown);
        expect(r.suggestedAction, BeaconDisplayPrimaryAction.none);
      });

      test('public viewer gets no suggested action', () {
        final r = deriveBeaconDisplayStatus(
          BeaconDisplayStatusInput(
            status: BeaconStatus.reviewOpen,
            tier: BeaconDisplayTier.public,
          ),
        );
        expect(r.suggestedAction, BeaconDisplayPrimaryAction.none);
      });

      test('no derived result carries a primary action the client dropped', () {
        for (final tier in BeaconDisplayTier.values) {
          for (final status in BeaconStatus.values) {
            final r = deriveBeaconDisplayStatus(
              BeaconDisplayStatusInput(status: status, tier: tier),
            );
            expect(
              r.suggestedAction.name,
              isNot('reviewContributions'),
              reason: '$status / $tier',
            );
          }
        }
      });
    });

    test('primary action enum has no reviewContributions value', () {
      expect(
        BeaconDisplayPrimaryAction.values.map((v) => v.name),
        isNot(contains('reviewContributions')),
      );
    });
  });
}
