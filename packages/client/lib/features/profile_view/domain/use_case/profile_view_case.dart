import 'package:injectable/injectable.dart';
import 'package:rxdart/rxdart.dart';

import 'package:tentura/domain/capability/person_capability_cues.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/entity/realtime/realtime_watch.dart';
import 'package:tentura/domain/port/capability_repository_port.dart';
import 'package:tentura/domain/port/realtime_watch_grant_port.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/domain/use_case/use_case_base.dart';
import 'package:tentura/features/contacts/domain/use_case/contacts_case.dart';
import 'package:tentura/features/like/data/repository/like_remote_repository.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';

typedef ProfileViewSnapshot = ({
  Profile profile,
  PersonCapabilityCues cues,
});

/// Owns the authoritative public-profile projection and its bounded live watch.
@injectable
final class ProfileViewCase extends UseCaseBase {
  ProfileViewCase(
    this._profiles,
    this._likes,
    this._capabilities,
    this._contacts,
    this._realtime,
    this._watchGrants, {
    required super.env,
    required super.logger,
  });

  final ProfileRepositoryPort _profiles;
  final LikeRemoteRepository _likes;
  final CapabilityRepositoryPort _capabilities;
  final ContactsCase _contacts;
  final RealtimeSyncCase _realtime;
  final RealtimeWatchGrantPort _watchGrants;

  Stream<void> projectionChanges(String profileId) => MergeStream<void>([
    _realtime
        .changesForAggregate(
          kinds: const {
            RealtimeEntityKind.profile,
            RealtimeEntityKind.relationship,
            RealtimeEntityKind.capability,
          },
          aggregateId: profileId,
        )
        .map((_) {}),
    _realtime.catchUps.map((_) {}),
    _realtime.watchRefreshRequests
        .where((scope) => scope == RealtimeWatchScope.profile)
        .map((_) {}),
    _contacts.changes,
    _capabilities.changes,
  ]);

  Future<ProfileViewSnapshot> load(String profileId) async {
    final results = await Future.wait<Object>([
      _profiles.fetchById(profileId),
      _capabilities.fetchCues(profileId),
    ]);
    await _replaceWatch(profileId);
    return (
      profile: applyContactOverlay(results[0] as Profile),
      cues: results[1] as PersonCapabilityCues,
    );
  }

  Profile applyContactOverlay(Profile profile) =>
      switch (_contacts.nameOf(profile.id)) {
        final name? when name.isNotEmpty => profile.copyWith(contactName: name),
        _ => profile.copyWith(contactName: ''),
      };

  Future<Profile> addFriend(Profile profile) =>
      _setRelationship(profile, amount: 1);

  Future<Profile> removeFriend(Profile profile) =>
      _setRelationship(profile, amount: 0);

  void disposeProjection() => _realtime.removeWatch(RealtimeWatchScope.profile);

  Future<Profile> _setRelationship(
    Profile profile, {
    required int amount,
  }) async => applyContactOverlay(
    await _likes.setLike(profile, amount: amount),
  );

  Future<void> _replaceWatch(String profileId) async {
    try {
      final grant = await _watchGrants.requestGrant(
        RealtimeWatchDescriptor.profile(
          requestedSubjectIds: {profileId},
          profileId: profileId,
        ),
      );
      _realtime.replaceWatch(grant);
    } catch (error, stackTrace) {
      logger.warning(
        'Profile realtime watch grant failed',
        error,
        stackTrace,
      );
    }
  }
}
