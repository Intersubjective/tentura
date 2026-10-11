import 'package:injectable/injectable.dart';

import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/author_invite.dart';
import 'package:tentura/domain/entity/post_bud_invite_outcome.dart';
import 'package:tentura/domain/port/author_invite_port.dart';

import '../gql/_g/author_invite_accept.req.gql.dart';
import '../gql/_g/author_invite_create.req.gql.dart';
import '../gql/_g/author_invite_decline.req.gql.dart';
import '../gql/_g/author_invite_withdraw.req.gql.dart';
import '../gql/_g/beacon_author_invites.req.gql.dart';
import '../gql/_g/my_pending_author_invites.req.gql.dart';

@Singleton(as: AuthorInvitePort, env: [Environment.dev, Environment.prod])
class AuthorInviteRepository implements AuthorInvitePort {
  const AuthorInviteRepository(this._remoteApiService);

  final RemoteApiService _remoteApiService;

  static const _label = 'AuthorInvite';

  @override
  Future<AuthorInviteCreateResult> create({
    required String beaconId,
    required String userId,
    String? note,
  }) async {
    final data = await _remoteApiService
        .request(
          GAuthorInviteCreateReq(
            (b) => b.vars
              ..beaconId = beaconId
              ..userId = userId
              ..note = note,
          ),
        )
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label).beaconAuthorInviteCreate);
    return AuthorInviteCreateResult(
      outcome: PostBudInviteOutcome.fromWire(data.outcome.name),
      inviteId: data.inviteId,
    );
  }

  @override
  Future<AuthorInvite> accept({required String inviteId}) async {
    final data = await _remoteApiService
        .request(GAuthorInviteAcceptReq((b) => b.vars.inviteId = inviteId))
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label).beaconAuthorInviteAccept);
    return _transition(data.inviteId, data.beaconId, data.status.name);
  }

  @override
  Future<AuthorInvite> decline({required String inviteId}) async {
    final data = await _remoteApiService
        .request(GAuthorInviteDeclineReq((b) => b.vars.inviteId = inviteId))
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label).beaconAuthorInviteDecline);
    return _transition(data.inviteId, data.beaconId, data.status.name);
  }

  @override
  Future<AuthorInvite> withdraw({required String inviteId}) async {
    final data = await _remoteApiService
        .request(GAuthorInviteWithdrawReq((b) => b.vars.inviteId = inviteId))
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label).beaconAuthorInviteWithdraw);
    return _transition(data.inviteId, data.beaconId, data.status.name);
  }

  @override
  Future<List<PendingAuthorInvite>> myPending() async {
    final rows = await _remoteApiService
        .request(GMyPendingAuthorInvitesReq())
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label).myPendingAuthorInvites);
    return [
      for (final row in rows)
        PendingAuthorInvite(
          id: row.inviteId,
          beaconId: row.beaconId,
          beaconTitle: row.beaconTitle,
          inviterId: row.inviterId,
          sourcePostId: row.sourcePostId,
          note: row.note,
          createdAt: DateTime.parse(row.createdAt).toUtc(),
        ),
    ];
  }

  @override
  Future<List<AuthorInvite>> beaconInvites({required String beaconId}) async {
    final rows = await _remoteApiService
        .request(GBeaconAuthorInvitesReq((b) => b.vars.beaconId = beaconId))
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label).beaconAuthorInvites);
    return [
      for (final row in rows)
        AuthorInvite(
          id: row.inviteId,
          beaconId: beaconId,
          inviteeId: row.inviteeId,
          status: AuthorInviteStatus.fromWire(row.status.name),
          note: row.note,
          createdAt: DateTime.parse(row.createdAt).toUtc(),
        ),
    ];
  }

  static AuthorInvite _transition(
    String inviteId,
    String beaconId,
    String status,
  ) => AuthorInvite(
    id: inviteId,
    beaconId: beaconId,
    status: AuthorInviteStatus.fromWire(status),
  );
}
