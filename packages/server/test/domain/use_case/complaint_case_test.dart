import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/enums.dart';
import 'package:tentura_server/domain/entity/complaint_entity.dart';
import 'package:tentura_server/domain/use_case/complaint_case.dart';
import 'package:tentura_server/env.dart';

import 'complaint_case_mocks.mocks.dart';

void main() {
  late MockComplaintRepositoryPort complaintRepo;
  late ComplaintCase case_;

  const id = 'Ccomplaint';
  const email = 'user@example.com';
  const userId = 'Ureporter';
  const details = 'Inappropriate content';

  setUp(() {
    complaintRepo = MockComplaintRepositoryPort();
    case_ = ComplaintCase(
      complaintRepo,
      env: Env(environment: Environment.test),
      logger: Logger('ComplaintCaseTest'),
    );
    when(complaintRepo.create(any)).thenAnswer((_) async {});
  });

  ComplaintEntity capturedEntity() =>
      verify(complaintRepo.create(captureAny)).captured.single
          as ComplaintEntity;

  group('ComplaintCase.create', () {
    test('returns true and persists entity with mapped type', () async {
      final before = DateTime.timestamp();

      final result = await case_.create(
        id: id,
        type: ComplaintType.violatesCsaePolicy.name,
        email: email,
        userId: userId,
        details: details,
      );

      expect(result, isTrue);
      final entity = capturedEntity();
      expect(entity.id, id);
      expect(entity.type, ComplaintType.violatesCsaePolicy);
      expect(entity.email, email);
      expect(entity.userId, userId);
      expect(entity.details, details);
      expect(entity.createdAt.isAfter(before.subtract(const Duration(seconds: 1))),
          isTrue);
    });

    test('maps violatesPlatformRules type', () async {
      await case_.create(
        id: id,
        type: ComplaintType.violatesPlatformRules.name,
        email: email,
        userId: userId,
        details: details,
      );

      expect(capturedEntity().type, ComplaintType.violatesPlatformRules);
    });

    test('unknown type string maps to ComplaintType.unknown', () async {
      await case_.create(
        id: id,
        type: 'notAComplaintType',
        email: email,
        userId: userId,
        details: details,
      );

      expect(capturedEntity().type, ComplaintType.unknown);
    });

    test('repository failure propagates', () async {
      when(complaintRepo.create(any)).thenThrow(Exception('db down'));

      await expectLater(
        case_.create(
          id: id,
          type: ComplaintType.violatesCsaePolicy.name,
          email: email,
          userId: userId,
          details: details,
        ),
        throwsA(isA<Exception>()),
      );
    });
  });
}
