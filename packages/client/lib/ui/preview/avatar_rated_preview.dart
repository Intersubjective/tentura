import 'package:tentura/domain/entity/profile.dart';

import '../preview.dart';
import '../widget/avatar_rated.dart';

@Preview(
  name: 'AvatarRated (small)',
  group: commonWidgetsGroup,
  theme: previewThemeData,
)
Widget sampleAvatarRatedSmall() => AvatarRated.small(
  profile: profileCaptainNemo,
  withRating: false,
);

@Preview(
  name: 'AvatarRated (big)',
  group: commonWidgetsGroup,
  theme: previewThemeData,
)
Widget sampleAvatarRatedBig() => AvatarRated.big(
  profile: profileCaptainNemo,
  withRating: false,
);

const _profileEyeOpen = Profile(
  id: 'Ueye1',
  title: 'Seeing you',
  rScore: 1,
);

const _profileEyeClosed = Profile(
  id: 'Ueye0',
  title: 'Not seeing you',
);

const _profileHandshake = Profile(
  id: 'Uhs1',
  title: 'Mutual friend',
  rScore: 1,
  isMutualFriend: true,
);

@Preview(
  name: 'AvatarRated (small · eye open)',
  group: commonWidgetsGroup,
  theme: previewThemeData,
)
Widget sampleAvatarRatedSmallEyeOpen() => AvatarRated.small(
  profile: _profileEyeOpen,
);

@Preview(
  name: 'AvatarRated (small · eye closed)',
  group: commonWidgetsGroup,
  theme: previewThemeData,
)
Widget sampleAvatarRatedSmallEyeClosed() => AvatarRated.small(
  profile: _profileEyeClosed,
);

@Preview(
  name: 'AvatarRated (small · handshake)',
  group: commonWidgetsGroup,
  theme: previewThemeData,
)
Widget sampleAvatarRatedSmallHandshake() => AvatarRated.small(
  profile: _profileHandshake,
);
