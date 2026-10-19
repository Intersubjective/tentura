import 'package:injectable/injectable.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/domain/port/beacon_write_port.dart';
import 'package:tentura/domain/use_case/use_case_base.dart';
import 'package:tentura/features/credentials/domain/entity/credential_types.dart';
import 'package:tentura/features/credentials/domain/use_case/credentials_case.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';

import '../../data/repository/complaint_repository.dart';
import '../util/feedback_email.dart';

@injectable
final class ComplaintCase extends UseCaseBase {
  ComplaintCase(
    this._complaintRepository,
    this._credentialsCase,
    this._beacons,
    this._profiles, {
    required super.env,
    required super.logger,
  });

  final ComplaintRepository _complaintRepository;
  final CredentialsCase _credentialsCase;
  final BeaconWritePort _beacons;
  final ProfileRepositoryPort _profiles;

  /// What is being reported, looked up by [id] (#488): a beacon's title and
  /// author name, or a person's name (no author). Null for other ids.
  Future<({String title, String author})?> fetchReportedItem(String id) async {
    if (id.startsWith('B')) {
      final beacon = await _beacons.fetchBeaconById(id);
      return (title: beacon.title, author: beacon.author.shownName);
    }
    if (id.startsWith('U')) {
      final profile = await _profiles.fetchById(id);
      return (title: profile.shownName, author: '');
    }
    return null;
  }

  Future<void> create({
    required String id,
    required ComplaintType type,
    required String email,
    required String details,
  }) => _complaintRepository.create(
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
