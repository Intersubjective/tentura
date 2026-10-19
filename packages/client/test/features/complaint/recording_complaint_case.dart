// SPDX-License-Identifier: AGPL-3.0-only
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/port/beacon_write_port.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/complaint/data/repository/complaint_repository.dart';
import 'package:tentura/features/complaint/domain/use_case/complaint_case.dart';
import 'package:tentura/features/credentials/domain/use_case/credentials_case.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';

import '../credentials/credentials_case_test.dart'
    show FakeCredentialsRepository, TrackingAuthLocal;

/// One recorded complaint send.
typedef CreatedComplaint = ({
  String id,
  ComplaintType type,
  String email,
  String details,
});

/// Records complaints at the repository instead of sending them.
class _RecordingComplaintRepository extends Fake
    implements ComplaintRepository {
  _RecordingComplaintRepository(this.created);

  final List<CreatedComplaint> created;

  @override
  Future<void> create({
    required String id,
    required String email,
    required String details,
    required ComplaintType type,
  }) async {
    created.add((id: id, type: type, email: email, details: details));
  }
}

/// Serves one beacon by id (#488: the form fetches what is reported); any
/// other id, or no beacon at all, fails like the real repository.
class FakeComplaintBeacons extends Fake implements BeaconWritePort {
  FakeComplaintBeacons([this.beacon]);

  final Beacon? beacon;

  /// Ids asked for, oldest first.
  final requested = <String>[];

  @override
  Future<Beacon> fetchBeaconById(String id) async {
    requested.add(id);
    final b = beacon;
    if (b == null || b.id != id) {
      throw StateError('beacon $id not available');
    }
    return b;
  }
}

/// Serves one profile by id; any other id, or none, fails.
class FakeComplaintProfiles extends Fake implements ProfileRepositoryPort {
  FakeComplaintProfiles([this.profile]);

  final Profile? profile;

  /// Ids asked for, oldest first.
  final requested = <String>[];

  @override
  Future<Profile> fetchById(String id) async {
    requested.add(id);
    final p = profile;
    if (p == null || p.id != id) {
      throw StateError('profile $id not available');
    }
    return p;
  }
}

/// A real [ComplaintCase] (final class, cannot be faked) wired to a recording
/// repository and an empty credentials store (no default feedback email).
///
/// `beacon` / `profile` are what the reported-item fetch finds (#488); with
/// neither, every fetch fails.
class RecordingComplaintCase {
  RecordingComplaintCase({Beacon? beacon, Profile? profile})
    : beacons = FakeComplaintBeacons(beacon),
      profiles = FakeComplaintProfiles(profile) {
    useCase = ComplaintCase(
      _RecordingComplaintRepository(created),
      CredentialsCase(
        FakeCredentialsRepository(),
        TrackingAuthLocal(),
        env: const Env(),
        logger: Logger('RecordingComplaintCase'),
      ),
      beacons,
      profiles,
      env: const Env(),
      logger: Logger('RecordingComplaintCase'),
    );
  }

  /// Every complaint sent so far, oldest first.
  final created = <CreatedComplaint>[];

  final FakeComplaintBeacons beacons;

  final FakeComplaintProfiles profiles;

  /// Pass this to `ComplaintCubit(complaintCase: ...)`.
  late final ComplaintCase useCase;
}
