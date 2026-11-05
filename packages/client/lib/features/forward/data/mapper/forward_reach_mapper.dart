import 'package:tentura/data/gql/_g/schema.schema.gql.dart';
import 'package:tentura/data/model/image_model_v2.dart';
import 'package:tentura/data/model/user_public_model.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/forward/domain/entity/forward_reach.dart';

ForwardReach? mapForwardReachFromUserPublic(UserPublicModel user) {
  final wire = user.forward_reach;
  if (wire == null) {
    return null;
  }
  final kind = switch (wire.kind) {
    Gv2_ForwardReachKind.direct => ForwardReachKind.direct,
    Gv2_ForwardReachKind.via_connection => ForwardReachKind.viaConnection,
    Gv2_ForwardReachKind.shared_request => ForwardReachKind.sharedRequest,
    Gv2_ForwardReachKind.wider => ForwardReachKind.wider,
    _ => ForwardReachKind.wider,
  };
  ForwardSharedRequest? shared;
  final requestId = wire.shared_request_id;
  final requestTitle = wire.shared_request_title;
  if (requestId != null &&
      requestId.isNotEmpty &&
      requestTitle != null &&
      requestTitle.isNotEmpty) {
    shared = (id: requestId, title: requestTitle);
  }
  return ForwardReach(
    kind: kind,
    via: [
      for (final voucher in wire.via)
        Profile(
          id: voucher.id,
          displayName: voucher.displayName,
          image: (voucher.image as ImageModelV2?)?.asEntity,
        ),
    ],
    viaCount: wire.via_count,
    sharedRequest: shared,
  );
}

/// Maps a JSON `forward_reach` object as returned on the wire (unit tests).
ForwardReach? mapForwardReachFromJson(Map<String, dynamic>? json) {
  if (json == null) {
    return null;
  }
  final kindWire = json['kind'] as String?;
  final kind = switch (kindWire) {
    'direct' => ForwardReachKind.direct,
    'via_connection' => ForwardReachKind.viaConnection,
    'shared_request' => ForwardReachKind.sharedRequest,
    'wider' => ForwardReachKind.wider,
    _ => null,
  };
  if (kind == null) {
    return null;
  }
  final viaRaw = json['via'];
  final viaList = viaRaw is List ? viaRaw : const <Object>[];
  final vouchers = <Profile>[
    for (final entry in viaList)
      if (entry is Map<String, dynamic>)
        Profile(
          id: entry['id'] as String? ?? '',
          displayName: entry['displayName'] as String? ?? '',
        ),
  ];
  final viaCount = json['via_count'] as int? ?? vouchers.length;
  ForwardSharedRequest? shared;
  final requestId = json['shared_request_id'] as String?;
  final requestTitle = json['shared_request_title'] as String?;
  if (requestId != null &&
      requestId.isNotEmpty &&
      requestTitle != null &&
      requestTitle.isNotEmpty) {
    shared = (id: requestId, title: requestTitle);
  }
  return ForwardReach(
    kind: kind,
    via: vouchers,
    viaCount: viaCount,
    sharedRequest: shared,
  );
}
