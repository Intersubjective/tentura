import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/env.dart';
import 'package:tentura/features/complaint/data/repository/complaint_repository.dart';
import 'package:tentura/features/complaint/domain/use_case/complaint_case.dart';
import 'package:tentura/features/credentials/domain/entity/credential_entity.dart';
import 'package:tentura/features/credentials/domain/entity/credential_types.dart';
import 'package:tentura/features/credentials/domain/use_case/credentials_case.dart';

import '../credentials/credentials_case_test.dart'
    show FakeCredentialsRepository, TrackingAuthLocal;

class _FakeComplaintRepository extends Fake implements ComplaintRepository {}

void main() {
  late FakeCredentialsRepository credentialsRepo;
  late CredentialsCase credentialsCase;
  late ComplaintCase case_;

  setUp(() {
    credentialsRepo = FakeCredentialsRepository();
    credentialsCase = CredentialsCase(
      credentialsRepo,
      TrackingAuthLocal(),
      env: const Env(),
      logger: Logger('CredentialsCaseTest'),
    );
    case_ = ComplaintCase(
      _FakeComplaintRepository(),
      credentialsCase,
      env: Env.fromEnvironment(),
      logger: Logger('ComplaintCaseTest'),
    );
  });

  group('resolveDefaultFeedbackEmail', () {
    test('returns first valid email_otp identifier', () async {
      credentialsRepo.credentials = [
        const CredentialEntity(
          id: 'c1',
          type: CredentialTypes.ed25519Device,
          identifier: 'pubkey',
        ),
        const CredentialEntity(
          id: 'c2',
          type: CredentialTypes.emailOtp,
          identifier: 'user@example.com',
        ),
      ];

      expect(await case_.resolveDefaultFeedbackEmail(), 'user@example.com');
    });

    test('returns null when no email_otp credential', () async {
      credentialsRepo.credentials = [
        const CredentialEntity(
          id: 'c1',
          type: CredentialTypes.ed25519Device,
          identifier: 'pubkey',
        ),
      ];

      expect(await case_.resolveDefaultFeedbackEmail(), isNull);
    });

    test('returns null when email_otp identifier is not an email', () async {
      credentialsRepo.credentials = [
        const CredentialEntity(
          id: 'c1',
          type: CredentialTypes.emailOtp,
          identifier: 'not-an-email',
        ),
      ];

      expect(await case_.resolveDefaultFeedbackEmail(), isNull);
    });
  });
}
