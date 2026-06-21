import '../preview.dart';
import 'package:tentura/design_system/components/tentura_avatar.dart';
import 'package:tentura/domain/entity/profile.dart';

@Preview(
  name: 'TenturaAvatar (medium)',
  group: commonWidgetsGroup,
  theme: previewThemeData,
)
Widget sampleTenturaAvatarMedium() => const TenturaAvatar.medium(
  profile: Profile(id: '1', displayName: 'Alex Rivera'),
);

@Preview(
  name: 'TenturaAvatar (big)',
  group: commonWidgetsGroup,
  theme: previewThemeData,
)
Widget sampleTenturaAvatarBig() => const TenturaAvatar.big(
  profile: Profile(id: '1', displayName: 'Alex Rivera'),
);

@Preview(
  name: 'TenturaAvatar (medium · eye open)',
  group: commonWidgetsGroup,
  theme: previewThemeData,
)
Widget sampleTenturaAvatarMediumEyeOpen() => const TenturaAvatar.medium(
  profile: Profile(id: '1', displayName: 'Alex Rivera', score: 50),
  withContactBadge: true,
);

@Preview(
  name: 'TenturaAvatar (medium · eye closed)',
  group: commonWidgetsGroup,
  theme: previewThemeData,
)
Widget sampleTenturaAvatarMediumEyeClosed() => const TenturaAvatar.medium(
  profile: Profile(id: '1', displayName: 'Alex Rivera'),
  withContactBadge: true,
);

@Preview(
  name: 'TenturaAvatar (medium · handshake)',
  group: commonWidgetsGroup,
  theme: previewThemeData,
)
Widget sampleTenturaAvatarMediumHandshake() => const TenturaAvatar.medium(
  profile: Profile(
    id: '1',
    displayName: 'Alex Rivera',
    isMutualFriend: true,
  ),
  withContactBadge: true,
);
