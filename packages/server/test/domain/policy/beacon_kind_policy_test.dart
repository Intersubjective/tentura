import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/policy/beacon_kind_policy.dart';

BeaconEntity _beacon({
  required BeaconKind kind,
  BeaconStatus status = BeaconStatus.open,
}) => BeaconEntity(
  id: 'B1',
  title: kind == BeaconKind.post ? '' : 'Title',
  author: const UserEntity(id: 'Uauthor'),
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  status: status,
  kind: kind,
);

void main() {
  group('BeaconKindPolicy.requireRequest', () {
    test('rejects a Post with BeaconNotRequestException', () {
      expect(
        () => BeaconKindPolicy.requireRequest(_beacon(kind: BeaconKind.post)),
        throwsA(isA<BeaconNotRequestException>()),
      );
    });

    test('rejects a Post whatever its status', () {
      for (final status in BeaconStatus.values) {
        expect(
          () => BeaconKindPolicy.requireRequest(
            _beacon(kind: BeaconKind.post, status: status),
          ),
          throwsA(isA<BeaconNotRequestException>()),
          reason: 'status ${status.name}',
        );
      }
    });

    test('lets a Request through', () {
      expect(
        () => BeaconKindPolicy.requireRequest(
          _beacon(kind: BeaconKind.request),
        ),
        returnsNormally,
      );
    });

    test('lets a Request through whatever its status', () {
      for (final status in BeaconStatus.values) {
        expect(
          () => BeaconKindPolicy.requireRequest(
            _beacon(kind: BeaconKind.request, status: status),
          ),
          returnsNormally,
          reason: 'status ${status.name}',
        );
      }
    });
  });

  group('BeaconNotRequestException', () {
    test('carries the beacon exception code appended after 1320', () {
      const exception = BeaconNotRequestException();
      final code = exception.code;

      expect(code, isA<BeaconExceptionCodes>());
      expect(
        (code as BeaconExceptionCodes).exceptionCode,
        BeaconExceptionCode.beaconNotRequest,
      );
      expect(code.codeNumber, 1321);
    });
  });
}
