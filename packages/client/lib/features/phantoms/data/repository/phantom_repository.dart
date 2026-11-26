import 'package:injectable/injectable.dart';

import 'package:tentura/data/model/constellation_anchor_position_input.dart';
import 'package:tentura/data/service/remote_api_client/remote_request_client.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/exception/generic_exception.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../../domain/port/phantom_repository_port.dart';
import '../../domain/exception.dart';
import '../gql/_g/forward_request_to_placeholder.req.gql.dart';
import '../gql/_g/phantom_create.req.gql.dart';
import '../gql/_g/phantom_delete.req.gql.dart';
import '../gql/_g/phantom_hint_dismiss.req.gql.dart';
import '../gql/_g/phantom_invite_ensure.req.gql.dart';
import '../gql/_g/phantom_invite_rotate.req.gql.dart';
import '../gql/_g/phantom_link.req.gql.dart';
import '../gql/_g/phantom_unmerge.req.gql.dart';
import '../gql/_g/phantom_update.req.gql.dart';

@LazySingleton(
  as: PhantomRepositoryPort,
  env: [Environment.dev, Environment.prod],
)
final class PhantomRepository implements PhantomRepositoryPort {
  PhantomRepository(this._remote);

  final RemoteRequestClient _remote;

  @override
  Future<String> create({
    required String name,
    String? emoji,
    ConstellationAnchorPosition? position,
  }) => _mutate(
    GPhantomCreateReq((builder) {
      builder.vars
        ..name = name
        ..emoji = emoji;
      if (position != null) {
        builder.vars.position.replace(anchorPositionToWire(position));
      }
    }),
    (data) => data.phantomCreate,
  );

  @override
  Future<void> update({
    required String id,
    required String name,
    String? emoji,
  }) => _write(
    GPhantomUpdateReq(
      (builder) => builder.vars
        ..id = id
        ..name = name
        ..emoji = emoji,
    ),
    (data) => data.phantomUpdate,
  );

  @override
  Future<Uri> forwardRequest({
    required String phantomId,
    required String beaconId,
    String? note,
  }) async {
    final link = await _mutate(
      GForwardRequestToPlaceholderReq((builder) {
        builder.vars
          ..phantomId = phantomId
          ..beaconId = beaconId
          ..note = note;
      }),
      (data) => data.beaconForwardToPhantom,
    );
    return Uri.parse(link);
  }

  @override
  Future<void> delete({required String id}) => _write(
    GPhantomDeleteReq((builder) => builder.vars.id = id),
    (data) => data.phantomDelete,
  );

  @override
  Future<String> inviteEnsure({required String id}) => _mutate(
    GPhantomInviteEnsureReq((builder) => builder.vars.id = id),
    (data) => data.phantomInviteEnsure,
  );

  @override
  Future<String> inviteRotate({required String id}) => _mutate(
    GPhantomInviteRotateReq((builder) => builder.vars.id = id),
    (data) => data.phantomInviteRotate,
  );

  @override
  Future<void> link({required String phantomId, required String userId}) =>
      _write(
        GPhantomLinkReq(
          (builder) => builder.vars
            ..phantomId = phantomId
            ..userId = userId,
        ),
        (data) => data.phantomLink,
      );

  @override
  Future<void> unmerge({required String phantomId, String? mergeId}) => _write(
    GPhantomUnmergeReq(
      (builder) => builder.vars
        ..phantomId = phantomId
        ..mergeId = mergeId,
    ),
    (data) => data.phantomUnmerge,
  );

  @override
  Future<void> hintDismiss({
    required String phantomId,
    required String userId,
  }) => _write(
    GPhantomHintDismissReq(
      (builder) => builder.vars
        ..phantomId = phantomId
        ..userId = userId,
    ),
    (data) => data.phantomHintDismiss,
  );

  Future<TResult> _mutate<TData, TVars, TResult>(
    OperationRequest<TData, TVars> request,
    TResult Function(TData) select,
  ) async {
    final label = request.operation.operationName ?? 'V2 mutation';
    try {
      final response = await _remote
          .request(request)
          .firstLinkResponse(label: label);
      return select(response.dataOrThrow(label: label));
    } on RemoteApiException catch (error) {
      if (error.code == '1007') throw const PhantomJoiningException();
      rethrow;
    }
  }

  Future<void> _write<TData, TVars>(
    OperationRequest<TData, TVars> request,
    bool Function(TData) select,
  ) async {
    if (!await _mutate(request, select)) throw const UnknownException();
  }
}
