import 'package:tentura/domain/entity/profile.dart';

import 'entity/constellation_field.dart';

/// Avatar cap for Field preview participant / forward rows ([TenturaAvatarStack]).
const kConstellationFieldPreviewAvatarMax = 3;

/// Visible face pile plus a [hiddenCount] folded into «+N» on the preview sheet.
class ConstellationFieldPreviewMemberStack {
  const ConstellationFieldPreviewMemberStack({
    required this.profiles,
    required this.hiddenCount,
  });

  final List<Profile> profiles;
  final int hiddenCount;

  bool get isEmpty => profiles.isEmpty && hiddenCount <= 0;

  /// «+N»: viewers not on the Field plus faces past [kConstellationFieldPreviewAvatarMax].
  int get plusBadgeCount {
    final pastCap = profiles.length - kConstellationFieldPreviewAvatarMax;
    return hiddenCount + (pastCap > 0 ? pastCap : 0);
  }
}

typedef ConstellationFieldPreviewProfileLookup =
    Profile? Function(
      String personId,
    );

typedef ConstellationFieldPreviewPeerOnField = bool Function(String personId);

/// Stacks for the Field node preview: room participants and forward-chain people.
/// Invisible members count toward hiddenCount only, same rule as member-web edges.
ConstellationFieldPreviewMemberStack constellationFieldPreviewMemberStack({
  required Iterable<ConstellationMemberWeb> webs,
  required ConstellationMemberWebState state,
  required String viewerId,
  required ConstellationFieldPreviewPeerOnField peerOnField,
  required ConstellationFieldPreviewProfileLookup profileFor,
  int additionalHiddenCount = 0,
}) {
  var hidden = additionalHiddenCount;
  final profiles = <Profile>[];
  for (final web in webs) {
    if (web.state != state) {
      continue;
    }
    final visible = web.personId == viewerId || peerOnField(web.personId);
    if (!visible) {
      hidden++;
      continue;
    }
    final profile = profileFor(web.personId);
    if (profile == null) {
      hidden++;
      continue;
    }
    profiles.add(profile);
  }
  profiles.sort((a, b) => a.shownName.compareTo(b.shownName));
  return ConstellationFieldPreviewMemberStack(
    profiles: profiles,
    hiddenCount: hidden,
  );
}
