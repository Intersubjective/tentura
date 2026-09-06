import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_creation_context.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_error_code.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

void main() {
  group('BeaconCreationContext', () {
    test('sealed variants carry expected fields', () {
      const standalone = BeaconCreationContextStandalone();
      const child = BeaconCreationContextChild(parentBeaconId: 'P1');
      const promoted = BeaconCreationContextPromotedChild(
        parentBeaconId: 'P1',
        sourceMessageId: 'M1',
      );

      expect(standalone, isA<BeaconCreationContext>());
      expect(child.parentBeaconId, 'P1');
      expect(promoted.sourceMessageId, 'M1');
    });
  });

  group('BeaconHierarchyErrorCode', () {
    test('wire names match plan §3.5', () {
      expect(
        BeaconHierarchyErrorCode.beaconChildCreateForbidden.wireName,
        'BEACON_CHILD_CREATE_FORBIDDEN',
      );
      expect(
        BeaconHierarchyErrorCode.coordinationKindDisabled.wireName,
        'COORDINATION_KIND_DISABLED',
      );
    });
  });

  group('BeaconStatus helpers used by hierarchy projections', () {
    test('reviewOpen is wrapping up and active section', () {
      expect(BeaconStatus.reviewOpen.isWrappingUp, isTrue);
      expect(BeaconStatus.reviewOpen.isActiveSection, isTrue);
    });
  });
}
