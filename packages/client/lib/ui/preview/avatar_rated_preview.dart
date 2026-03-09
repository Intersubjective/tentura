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
