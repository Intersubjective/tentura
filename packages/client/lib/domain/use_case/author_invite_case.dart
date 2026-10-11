import 'package:injectable/injectable.dart';

import 'package:tentura/domain/entity/author_invite.dart';
import 'package:tentura/domain/port/author_invite_port.dart';

import 'use_case_base.dart';

/// The author-invite lifecycle (plan C4) and its read projections (plan C6).
@singleton
final class AuthorInviteCase extends UseCaseBase {
  AuthorInviteCase(
    this._port, {
    required super.env,
    required super.logger,
  });

  final AuthorInvitePort _port;

  Future<AuthorInviteCreateResult> create({
    required String beaconId,
    required String userId,
    String? note,
  }) => _port.create(beaconId: beaconId, userId: userId, note: note);

  Future<AuthorInvite> accept(String inviteId) =>
      _port.accept(inviteId: inviteId);

  Future<AuthorInvite> decline(String inviteId) =>
      _port.decline(inviteId: inviteId);

  Future<AuthorInvite> withdraw(String inviteId) =>
      _port.withdraw(inviteId: inviteId);

  Future<List<PendingAuthorInvite>> myPending() => _port.myPending();

  Future<List<AuthorInvite>> beaconInvites(String beaconId) =>
      _port.beaconInvites(beaconId: beaconId);

  /// The snapshot observers of the caller's budded Request (plan D4).
  Future<List<String>> budObservers(String beaconId) =>
      _port.budObservers(beaconId: beaconId);
}
