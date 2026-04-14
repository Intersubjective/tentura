import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:tentura_server/consts.dart';
import 'package:tentura_server/utils/id.dart';

import 'user_entity.dart';

part 'invitation_entity.freezed.dart';

@freezed
abstract class InvitationEntity with _$InvitationEntity {
  static String get newId => generateId('I');

  const factory InvitationEntity({
    required String id,
    required UserEntity issuer,
    required DateTime createdAt,
    required DateTime updatedAt,
    UserEntity? invited,
  }) = _InvitationEntity;

  const InvitationEntity._();

  bool get isAccepted => invited != null;

  bool get isExpired => createdAt.add(kInvitationTTL).isBefore(DateTime.now());

  Map<String, Object?> get asMap => {
    'id': id,
    'issuer_id': issuer.id,
    'invited_id': invited?.id,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  /// GraphQL `invitationById` with `issuer { ...UserModel }` (V2 direct path).
  Map<String, Object?> get asMapWithIssuer => {
    ...asMap,
    'issuer': {
      'id': issuer.id,
      'title': issuer.title,
      'description': issuer.description,
      'my_vote': null,
      // gqlTypeImagePublic: `created_at` is graphQLDate — use DateTime, not ISO string.
      'image': issuer.image == null
          ? null
          : {
              'id': issuer.image!.id,
              'hash': issuer.image!.blurHash,
              'height': issuer.image!.height,
              'width': issuer.image!.width,
              'author_id': issuer.image!.authorId,
              'created_at': issuer.image!.createdAt,
            },
      'scores': <Object>[],
    },
  };
}
