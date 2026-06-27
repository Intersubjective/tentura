import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/enums.dart';
import 'package:tentura_server/domain/entity/account_deletion_request_email_payload.dart';
import 'package:tentura_server/domain/entity/complaint_entity.dart';
import 'package:tentura_server/domain/use_case/complaint_case.dart';
import 'package:tentura_server/env.dart';

import 'complaint_case_mocks.mocks.dart';

void main() {
  late MockComplaintRepositoryPort complaintRepo;
  late MockEmailSenderPort emailSender;
  late ComplaintCase case_;

  const id = 'Ccomplaint';
  const email = 'user@example.com';
  const userId = 'Ureporter';
  const details = 'Please remove my profile';

  Env configuredEnv() => Env(
    environment: Environment.test,
    resendApiKey: 're_test',
    resendFromEmail: 'noreply@example.com',
    complaintEmail: 'admin@example.com',
  );

  setUp(() {
    complaintRepo = MockComplaintRepositoryPort();
    emailSender = MockEmailSenderPort();
    case_ = ComplaintCase(
      complaintRepo,
      emailSender,
      env: configuredEnv(),
      logger: Logger('ComplaintCaseTest'),
    );
    when(complaintRepo.create(any)).thenAnswer((_) async {});
    when(
      emailSender.sendAccountDeletionRequestAdminEmail(
        to: anyNamed('to'),
        payload: anyNamed('payload'),
      ),
    ).thenAnswer((_) async {});
    when(
      emailSender.sendAccountDeletionRequestUserConfirmation(
        to: anyNamed('to'),
        payload: anyNamed('payload'),
      ),
    ).thenAnswer((_) async {});
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
      verifyNever(
        emailSender.sendAccountDeletionRequestAdminEmail(
          to: anyNamed('to'),
          payload: anyNamed('payload'),
        ),
      );
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

    test('accountDeletionRequest sends admin and user emails', () async {
      final result = await case_.create(
        id: id,
        type: ComplaintType.accountDeletionRequest.name,
        email: email,
        userId: userId,
        details: details,
      );

      expect(result, isTrue);
      final payload = verify(
        emailSender.sendAccountDeletionRequestAdminEmail(
          to: 'admin@example.com',
          payload: captureAnyNamed('payload'),
        ),
      ).captured.single as AccountDeletionRequestEmailPayload;
      verify(
        emailSender.sendAccountDeletionRequestUserConfirmation(
          to: email,
          payload: anyNamed('payload'),
        ),
      ).called(1);
      expect(payload.complaintId, id);
      expect(payload.userId, userId);
      expect(payload.contactEmail, email);
      expect(payload.details, details);
    });

    test('accountDeletionRequest skips admin when COMPLAINT_EMAIL empty', () async {
      case_ = ComplaintCase(
        complaintRepo,
        emailSender,
        env: Env(
          environment: Environment.test,
          resendApiKey: 're_test',
          resendFromEmail: 'noreply@example.com',
        ),
        logger: Logger('ComplaintCaseTest'),
      );

      await case_.create(
        id: id,
        type: ComplaintType.accountDeletionRequest.name,
        email: email,
        userId: userId,
        details: details,
      );

      verifyNever(
        emailSender.sendAccountDeletionRequestAdminEmail(
          to: anyNamed('to'),
          payload: anyNamed('payload'),
        ),
      );
      verify(
        emailSender.sendAccountDeletionRequestUserConfirmation(
          to: email,
          payload: anyNamed('payload'),
        ),
      ).called(1);
    });

    test('admin email failure does not fail create or block user email', () async {
      when(
        emailSender.sendAccountDeletionRequestAdminEmail(
          to: anyNamed('to'),
          payload: anyNamed('payload'),
        ),
      ).thenThrow(StateError('resend down'));

      final result = await case_.create(
        id: id,
        type: ComplaintType.accountDeletionRequest.name,
        email: email,
        userId: userId,
        details: details,
      );

      expect(result, isTrue);
      verify(
        emailSender.sendAccountDeletionRequestUserConfirmation(
          to: email,
          payload: anyNamed('payload'),
        ),
      ).called(1);
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
