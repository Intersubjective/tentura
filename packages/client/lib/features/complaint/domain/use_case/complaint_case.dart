import 'package:injectable/injectable.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/domain/use_case/use_case_base.dart';
import 'package:tentura/features/credentials/domain/entity/credential_types.dart';
import 'package:tentura/features/credentials/domain/use_case/credentials_case.dart';

import '../../data/repository/complaint_repository.dart';
import '../util/feedback_email.dart';

@injectable
final class ComplaintCase extends UseCaseBase {
  ComplaintCase(
    this._complaintRepository,
    this._credentialsCase, {
    required super.env,
    required super.logger,
  });

  final ComplaintRepository _complaintRepository;
  final CredentialsCase _credentialsCase;

  Future<void> create({
    required String id,
    required ComplaintType type,
    required String email,
    required String details,
  }) =>
      _complaintRepository.create(
        id: id,
        type: type,
        email: email,
        details: details,
      );

  /// First linked email-OTP credential identifier, if it looks like an email.
  Future<String?> resolveDefaultFeedbackEmail() async {
    final credentials = await _credentialsCase.fetch();
    for (final credential in credentials) {
      if (credential.type != CredentialTypes.emailOtp) {
        continue;
      }
      final identifier = credential.identifier.trim();
      if (isValidFeedbackEmail(identifier)) {
        return identifier;
      }
    }
    return null;
  }
}
