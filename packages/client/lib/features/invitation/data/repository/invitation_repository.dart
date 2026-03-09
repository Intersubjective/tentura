import 'package:injectable/injectable.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/data/model/user_model.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/invitation_entity.dart';
import 'package:tentura/domain/entity/profile.dart';

import '../../domain/exception.dart';
import '../gql/_g/invitation_accept.req.gql.dart';
import '../gql/_g/invitation_create.req.gql.dart';
import '../gql/_g/invitation_delete_by_id.req.gql.dart';
import '../gql/_g/invitation_fetch_by_id.req.gql.dart';
import '../gql/_g/invitations_fetch_by_user_id.req.gql.dart';

typedef InvitationFetchByIdResult = ({
  InvitationEntity invitation,
  Profile issuer,
});

@singleton
class InvitationRepository {
  const InvitationRepository(this._remoteApiService);

  final RemoteApiService _remoteApiService;

  Future<InvitationFetchByIdResult?> fetchById(String id) async {
    final invitation = await _remoteApiService
        .request(GInvitationByIdReq((b) => b.vars.id = id))
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label).invitationById);
    if (invitation == null) {
      return null;
    }
    final timestamp = DateTime.parse(invitation.created_at);
    return (
      invitation: InvitationEntity(
        id: invitation.id,
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
      issuer: (invitation.issuer! as UserModel).toEntity(),
    );
  }

  Future<List<InvitationEntity>> fetchMine({
    int offset = 0,
    int limit = kFetchWindowSize,
  }) async {
    final result = await _remoteApiService
        .request(
          GInvitationsFetchByUserIdReq(
            (b) => b.vars
              ..created_at_gt = DateTime.timestamp().subtract(
                const Duration(hours: kInvitationDefaultTTL),
              )
              ..offset = offset
              ..limit = limit,
          ),
        )
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label).invitation);
    return result
        .map(
          (e) => InvitationEntity(
            id: e.id,
            invitedId: e.invited_id,
            createdAt: e.created_at,
            updatedAt: e.updated_at,
          ),
        )
        .toList();
  }

  Future<InvitationEntity> create() async {
    final result = await _remoteApiService
        .request(GInvitationCreateReq())
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label).insert_invitation_one);
    if (result == null) {
      throw const InvitationCreateException();
    }
    return InvitationEntity(
      id: result.id,
      invitedId: result.invited_id,
      createdAt: result.created_at,
      updatedAt: result.updated_at,
    );
  }

  Future<void> deleteById(String id) async {
    final result = await _remoteApiService
        .request(GInvitationDeleteByIdReq((b) => b.vars.id = id))
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label).invitationDelete);
    if (!result) {
      throw InvitationDeleteException(id);
    }
  }

  Future<void> accept(String id) async {
    final result = await _remoteApiService
        .request(GInvitationAcceptReq((b) => b.vars.id = id))
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label).invitationAccept);
    if (!result) {
      throw InvitationAcceptException(id);
    }
  }

  static const _label = 'Invitation';
}
