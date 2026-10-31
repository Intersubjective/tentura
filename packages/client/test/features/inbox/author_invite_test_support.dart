import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/attention/attention_actor_profiles_case.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/domain/entity/author_invite.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/port/author_invite_port.dart';
import 'package:tentura/domain/use_case/author_invite_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/inbox/domain/use_case/inbox_case.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';

import 'inbox_case_test.dart'
    show FakeInboxRepository, buildTestBeaconThreadsCase, buildTestInboxCase;

/// Scriptable [AuthorInvitePort] for the «Для вас» invite card (plan D3).
final class FakeAuthorInvitePort implements AuthorInvitePort {
  List<PendingAuthorInvite> pending = const [];
  final accepted = <String>[];
  final declined = <String>[];
  final revertedDeclines = <String>[];

  /// When set, accept/decline throw it (after [gate], if any).
  Exception? error;

  /// When set, only the take-back of a decline throws it.
  Exception? revertError;

  /// When set, accept/decline wait on it, so a test can look at the
  /// optimistic state before the server answers.
  Completer<void>? gate;

  Future<AuthorInvite> _answer(
    String inviteId,
    List<String> log,
    AuthorInviteStatus status,
  ) async {
    log.add(inviteId);
    await gate?.future;
    final e = error;
    if (e != null) throw e;
    return AuthorInvite(id: inviteId, beaconId: 'B', status: status);
  }

  @override
  Future<AuthorInvite> accept({required String inviteId}) =>
      _answer(inviteId, accepted, AuthorInviteStatus.accepted);

  @override
  Future<AuthorInvite> decline({required String inviteId}) =>
      _answer(inviteId, declined, AuthorInviteStatus.declined);

  @override
  Future<AuthorInvite> revertDecline({required String inviteId}) async {
    revertedDeclines.add(inviteId);
    final e = revertError;
    if (e != null) throw e;
    return AuthorInvite(
      id: inviteId,
      beaconId: 'B',
      status: AuthorInviteStatus.pending,
    );
  }

  @override
  Future<List<PendingAuthorInvite>> myPending() async => pending;

  @override
  Future<AuthorInviteCreateResult> create({
    required String beaconId,
    required String userId,
    String? note,
  }) => throw UnimplementedError();

  @override
  Future<AuthorInvite> withdraw({required String inviteId}) =>
      throw UnimplementedError();

  @override
  Future<List<AuthorInvite>> beaconInvites({required String beaconId}) =>
      throw UnimplementedError();

  @override
  Future<List<String>> budObservers({required String beaconId}) =>
      throw UnimplementedError();
}

AuthorInviteCase buildAuthorInviteCase(FakeAuthorInvitePort port) =>
    AuthorInviteCase(
      port,
      env: const Env(),
      logger: Logger('author-invite-test'),
    );

/// [AttentionActorProfilesCase] that knows [profiles].
AttentionActorProfilesCase buildActorProfiles(List<Profile> profiles) =>
    AttentionActorProfilesCase(_Profiles(profiles), _Account());

final class _Profiles implements ProfileRepositoryPort {
  _Profiles(this.profiles);

  final List<Profile> profiles;

  @override
  Future<List<Profile>> fetchProfilesByIds(Set<String> ids) async => [
    for (final p in profiles)
      if (ids.contains(p.id)) p,
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Account implements AttentionAccountPort {
  @override
  Stream<String> get currentAccountChanges => const Stream.empty();
}

/// Registers an [AuthorInviteCase] over empty lists plus an empty
/// [AttentionActorProfilesCase], for screens that mount the author's invites
/// section (the post-budding gate is on) without caring about it. The
/// Request page's invite banner also needs an [InboxCase] (for the decline
/// note), so one over an empty inbox is registered unless a test has its own.
void registerEmptyAuthorInvitesGetIt() {
  unregisterEmptyAuthorInvitesGetIt();
  GetIt.I
    ..registerSingleton<AuthorInviteCase>(
      buildAuthorInviteCase(_EmptyInvitesPort()),
    )
    ..registerSingleton<AttentionActorProfilesCase>(
      buildActorProfiles(const []),
    );
  if (!GetIt.I.isRegistered<InboxCase>()) {
    GetIt.I.registerSingleton<InboxCase>(
      buildTestInboxCase(FakeInboxRepository(), buildTestBeaconThreadsCase()),
    );
    _ownsInboxCase = true;
  }
}

/// Whether [registerEmptyAuthorInvitesGetIt] put the [InboxCase] there, so
/// the unregister never takes a test's own.
var _ownsInboxCase = false;

void unregisterEmptyAuthorInvitesGetIt() {
  final getIt = GetIt.I;
  if (getIt.isRegistered<AuthorInviteCase>()) {
    getIt.unregister<AuthorInviteCase>();
  }
  if (getIt.isRegistered<AttentionActorProfilesCase>()) {
    getIt.unregister<AttentionActorProfilesCase>();
  }
  if (_ownsInboxCase && getIt.isRegistered<InboxCase>()) {
    getIt.unregister<InboxCase>();
  }
  _ownsInboxCase = false;
}

final class _EmptyInvitesPort extends FakeAuthorInvitePort {
  @override
  Future<List<AuthorInvite>> beaconInvites({required String beaconId}) async =>
      const [];

  @override
  Future<List<String>> budObservers({required String beaconId}) async =>
      const [];
}
