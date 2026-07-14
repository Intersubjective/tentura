import 'package:injectable/injectable.dart';
import 'package:rxdart/rxdart.dart';

import 'package:tentura/data/repository/presence_repository.dart';
import 'package:tentura/domain/capability/friend_context.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/port/capability_repository_port.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/domain/use_case/use_case_base.dart';
import 'package:tentura/features/auth/domain/use_case/auth_case.dart';
import 'package:tentura/features/contacts/domain/use_case/contacts_case.dart';
import 'package:tentura/features/friends/data/repository/friends_remote_repository.dart';
import 'package:tentura/features/invitation/data/repository/invitation_repository.dart';
import 'package:tentura/features/like/data/repository/like_remote_repository.dart';

typedef FriendsSnapshot = ({
  Map<String, Profile> friends,
  Map<String, FriendContext> friendContexts,
});

@singleton
final class FriendsCase extends UseCaseBase {
  FriendsCase(
    this._capabilities,
    this._invitations,
    this._likes,
    this._friends,
    this._presence,
    this._contacts,
    this._auth,
    this._realtime, {
    required super.env,
    required super.logger,
  });

  final CapabilityRepositoryPort _capabilities;
  final InvitationRepository _invitations;
  final LikeRemoteRepository _likes;
  final FriendsRemoteRepository _friends;
  final PresenceRepository _presence;
  final ContactsCase _contacts;
  final AuthCase _auth;
  final RealtimeSyncCase _realtime;

  Stream<String> get accountChanges => _auth.currentAccountChanges();

  Stream<Profile> get localFriendChanges => _likes.changes
      .where((event) => event.value is Profile)
      .map((event) => event.value as Profile);

  Stream<void> get contactChanges => _contacts.changes;

  Stream<void> get projectionChanges => MergeStream<void>([
    _realtime
        .changesFor(const {
          RealtimeEntityKind.relationship,
          RealtimeEntityKind.profile,
          RealtimeEntityKind.capability,
        })
        .map((_) {}),
    _realtime.catchUps.map((_) {}),
    _invitations.changes,
  ]);

  Future<FriendsSnapshot> load() async {
    await _contacts.refresh();
    final profiles = await _friends.fetch();
    final friends = {
      for (final profile in profiles) profile.id: applyContactOverlay(profile),
    };
    final contexts = await _capabilities.fetchFriendContextsBatch(
      subjectIds: friends.keys.toList(growable: false),
    );
    return (friends: friends, friendContexts: contexts);
  }

  Profile applyContactOverlay(Profile profile) =>
      switch (_contacts.nameOf(profile.id)) {
        final name? when name.isNotEmpty => profile.copyWith(contactName: name),
        _ => profile.copyWith(contactName: ''),
      };

  void watchPresence(Set<String> userIds) =>
      _presence.watch('friends', userIds);

  void unwatchPresence() => _presence.unwatch('friends');

  Future<void> addFriend(Profile user) => _likes.setLike(user, amount: 1);

  Future<void> removeFriend(Profile user) => _likes.setLike(user, amount: 0);

  Future<void> acceptInvitation(String id) => _invitations.accept(id);
}
