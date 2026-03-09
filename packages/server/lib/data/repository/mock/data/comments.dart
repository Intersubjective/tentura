import 'package:tentura_server/domain/entity/comment_entity.dart';

import 'beacons.dart';
import 'users.dart';

const kC1b28e93382e1 = 'C1b28e93382e1';
const kC9b1d2b73215c = 'C9b1d2b73215c';

/// Mock data for tests and dev mode
final kCommentById = <String, CommentEntity>{
  kC9b1d2b73215c: CommentEntity(
    id: kC9b1d2b73215c,
    content: '14. I`ve got us a burglar.',
    createdAt: DateTime(2024, 10, 05, 10, 25, 54),
    beacon: kBeaconById[kBc1cb783b0159]!,
    author: kUserByPublicKey[kGandalfKey]!,
  ),
  kC1b28e93382e1: CommentEntity(
    id: kC1b28e93382e1,
    content:
        'Sorry, cousin, my boar is allergic to dragons. '
        'Wish you all the luck though!',
    createdAt: DateTime(2024, 10, 05, 10, 23, 28),
    beacon: kBeaconById[kBc1cb783b0159]!,
    author: kUserByPublicKey[kDainKey]!,
  ),
};
