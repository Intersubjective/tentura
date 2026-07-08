import 'package:injectable/injectable.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/contacts/contact_name_overlay.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/use_case/use_case_base.dart';
import 'package:tentura/features/auth/domain/port/auth_local_repository_port.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/contacts/domain/use_case/contacts_case.dart';
import 'package:tentura/features/profile/domain/exception.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';

import '../../data/repository/forward_repository.dart';
import '../entity/candidate_involvement.dart';
import '../entity/person_forward_row.dart';
import 'forward_case.dart';

typedef PersonForwardLoad = ({
  Profile person,
  List<PersonForwardRow> rows,
});

@singleton
final class PersonForwardCase extends UseCaseBase {
  PersonForwardCase(
    this._forwardRepository,
    this._beaconRepository,
    this._profileRepository,
    this._authLocalRepository,
    this._contactsCase, {
    required super.env,
    required super.logger,
  });

  final ForwardRepository _forwardRepository;
  final BeaconRepository _beaconRepository;
  final ProfileRepositoryPort _profileRepository;
  final AuthLocalRepositoryPort _authLocalRepository;
  final ContactsCase _contactsCase;

  Stream<String> get forwardCompleted => _forwardRepository.forwardCompleted;

  Stream<void> get contactChanges => _contactsCase.changes;

  static Profile applyContactOverlay(Profile profile) =>
      profileWithContactOverlay(profile);

  Future<PersonForwardLoad> load(String personId) async {
    await _contactsCase.refresh();
    final myId = await _authLocalRepository.getCurrentAccountId();
    if (personId == myId) {
      throw StateError('Cannot send requests to yourself');
    }
    final profiles = await _profileRepository.fetchProfilesByIds({personId});
    final person = profiles.firstOrNull;
    if (person == null) {
      throw ProfileFetchException(personId);
    }
    final beacons = await _beaconRepository.fetchBeacons(
      profileId: myId,
      offset: 0,
      lifecycleStates: BeaconStatus.openFamilyValues.toList(),
      // TODO(pagination): add paging if authored open requests can exceed 50.
      limit: 50,
    );
    final rows = await Future.wait(
      beacons.map((beacon) async {
        try {
          final inv = await _forwardRepository.fetchInvolvementForBeacon(
            beacon,
          );
          final involvement = ForwardCase.computeInvolvement(personId, inv);
          return PersonForwardRow(
            beacon: beacon,
            involvement: involvement,
            block: PersonForwardRow.blockFor(involvement, beacon.status),
          );
        } catch (e) {
          logger.warning(
            'PersonForward: involvement failed for ${beacon.id}: $e',
          );
          return PersonForwardRow(
            beacon: beacon,
            involvement: CandidateInvolvement.unseen,
            block: PersonForwardRow.blockFor(
              CandidateInvolvement.unseen,
              beacon.status,
            ),
          );
        }
      }),
    );
    rows.sort(_compareRows);
    return (
      person: applyContactOverlay(person),
      rows: rows,
    );
  }

  Future<void> send({
    required String beaconId,
    required String personId,
    String? note,
  }) => _forwardRepository.forwardBeacon(
    beaconId: beaconId,
    recipientIds: [personId],
    note: note?.trim().isEmpty ?? true ? null : note!.trim(),
  );

  static int _compareRows(PersonForwardRow a, PersonForwardRow b) {
    final byBlock = _blockRank(a.block).compareTo(_blockRank(b.block));
    if (byBlock != 0) return byBlock;
    return b.beacon.updatedAt.compareTo(a.beacon.updatedAt);
  }

  static int _blockRank(PersonForwardBlock block) => switch (block) {
    PersonForwardBlock.none => 0,
    PersonForwardBlock.alreadySent => 1,
    PersonForwardBlock.alreadyHelping => 1,
    PersonForwardBlock.declined => 1,
    PersonForwardBlock.withdrawn => 1,
    PersonForwardBlock.theirOwn => 1,
    PersonForwardBlock.notOpen => 2,
  };
}
