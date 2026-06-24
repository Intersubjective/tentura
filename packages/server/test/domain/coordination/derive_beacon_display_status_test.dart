import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/domain/coordination/derive_beacon_display_status.dart';

void main() {
  group('deriveBeaconDisplayStatus', () {
    test('draft phase', () {
      final r = deriveBeaconDisplayStatus(
        BeaconDisplayStatusInput(status: BeaconStatus.draft, tier: BeaconDisplayTier.coordination),
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
  });
}
