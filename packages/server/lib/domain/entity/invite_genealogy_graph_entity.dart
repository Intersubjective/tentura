import 'package:freezed_annotation/freezed_annotation.dart';

import 'user_entity.dart';

part 'invite_genealogy_graph_entity.freezed.dart';

@freezed
abstract class InviteGenealogyNodeEntity with _$InviteGenealogyNodeEntity {
  const factory InviteGenealogyNodeEntity({
    required String nodeKey,
    UserEntity? user,
    DateTime? deletedAt,
    DateTime? userCreatedAt,
  }) = _InviteGenealogyNodeEntity;
}

@freezed
abstract class InviteGenealogyEdgeEntity with _$InviteGenealogyEdgeEntity {
  const factory InviteGenealogyEdgeEntity({
    required String ancestorNodeKey,
    required String descendantNodeKey,
    required DateTime ancestorUserCreatedAt,
    required DateTime descendantUserCreatedAt,
    required DateTime createdAt,
  }) = _InviteGenealogyEdgeEntity;
}

@freezed
abstract class InviteGenealogyGraphEntity with _$InviteGenealogyGraphEntity {
  const factory InviteGenealogyGraphEntity({
    required String viewerNodeKey,
    required List<InviteGenealogyNodeEntity> nodes,
    required List<InviteGenealogyEdgeEntity> edges,
  }) = _InviteGenealogyGraphEntity;
}
