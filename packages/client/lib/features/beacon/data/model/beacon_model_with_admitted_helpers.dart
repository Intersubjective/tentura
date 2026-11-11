import 'package:tentura/data/model/beacon_model.dart';
import 'package:tentura/data/model/user_model.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_pending_upload.dart';
import 'package:tentura/consts.dart';

import '../gql/_g/beacon_model_with_admitted_helpers.data.gql.dart';

extension type const BeaconModelWithAdmittedHelpers(
  GBeaconModelWithAdmittedHelpers i
)
    implements GBeaconModelWithAdmittedHelpers {
  Beacon toEntity() {
    final base = BeaconModel(i).toEntity();
    final users = <Profile>[
      for (final row in i.admitted_helpers) (row.user as UserModel).toEntity(),
    ];
    return base.copyWith(
      postLifetimeHours: i.post_lifetime_hours,
      postDraftAttachments: [
        for (final row in i.post_draft_attachments)
          RoomPendingUpload.saved(
            attachmentId: row.id,
            fileName: row.file_name,
            mimeType: row.mime,
            imageUrl: switch (row.image) {
              final image? => serverImageUrl(
                authorId: image.author_id,
                imageId: image.id,
              ),
              null => null,
            },
          ),
      ],
      admittedHelperUsers: users,
      admittedHelperCount: i.admitted_helpers_aggregate.aggregate?.count ?? 0,
    );
  }
}
