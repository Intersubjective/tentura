// U094: server texts a user can see carry no internal names.
import 'package:test/test.dart';

import 'package:tentura_root/domain/entity/beacon_hierarchy_delivery_direction.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/policy/beacon_hierarchy_notice_copy.dart';

void main() {
  test('busy error names no database or internal component', () {
    final e = ConstellationException(
      constellationCode: ConstellationExceptionCode.retryLater,
    );
    expect(e.description, 'Busy right now. Try again in a few seconds.');
    expect(e.description, isNot(contains('onstellation')));
    expect(e.description, isNot(contains('database')));
  });

  test('hierarchy notice uses the plain status name', () {
    final body = BeaconHierarchyNoticeCopy.noticeBody(
      direction: BeaconHierarchyDeliveryDirection.ancestor,
      toStatus: BeaconStatus.reviewOpen,
      occurredAt: DateTime.utc(2026, 10, 14),
      sourceDeleted: false,
    );
    expect(body, 'An ancestor request entered Final check on 2026-10-14');
  });
}
