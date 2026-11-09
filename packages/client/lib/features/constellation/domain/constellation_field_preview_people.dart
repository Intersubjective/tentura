import 'package:tentura/domain/entity/profile.dart';

import 'entity/constellation_field.dart';

/// Visible face pile plus a [hiddenCount] folded into «+N» on the preview sheet.
class ConstellationFieldPreviewMemberStack {
  const ConstellationFieldPreviewMemberStack({
    required this.profiles,
    required this.hiddenCount,
  });

  final List<Profile> profiles;
  final int hiddenCount;

  /// True when the preview sheet would draw no faces and no «+N» for this stack.
  bool get isEmpty => !constellationFieldPreviewStackHasDrawableContent(this);
}

/// Faces shown in the row; extras fold into «+N» (hidden webs + avatar overflow).
int constellationFieldPreviewStackPlusCount(
  ConstellationFieldPreviewMemberStack stack, {
  int maxFaces = 3,
}) {
  final overflow = stack.profiles.length > maxFaces
      ? stack.profiles.length - maxFaces
      : 0;
  return stack.hiddenCount + overflow;
}

bool constellationFieldPreviewStackHasDrawableContent(
  ConstellationFieldPreviewMemberStack stack, {
  int maxFaces = 3,
}) =>
    stack.profiles.isNotEmpty ||
    constellationFieldPreviewStackPlusCount(stack, maxFaces: maxFaces) > 0;

typedef ConstellationFieldPreviewProfileLookup =
    Profile? Function(
      String personId,
    );

typedef ConstellationFieldPreviewPeerOnField = bool Function(String personId);

/// Stacks for the Field node preview: room participants and forward-chain people.
/// Off-field / unreadable members are omitted; [hiddenCount] is only extra «+N»
/// (e.g. Post hidden reach and faces past the avatar row cap).
ConstellationFieldPreviewMemberStack constellationFieldPreviewMemberStack({
  required Iterable<ConstellationMemberWeb> webs,
  required ConstellationMemberWebState state,
  required String viewerId,
  required ConstellationFieldPreviewPeerOnField peerOnField,
  required ConstellationFieldPreviewProfileLookup profileFor,
  int additionalHiddenCount = 0,
}) {
  final hidden = additionalHiddenCount;
  final profiles = <Profile>[];
  final seen = <String>{};
  for (final web in webs) {
    if (web.state != state) {
      continue;
    }
    if (state == ConstellationMemberWebState.forwarded &&
        web.personId == viewerId) {
      continue;
    }
    if (!seen.add(web.personId)) {
      continue;
    }
    final visible = web.personId == viewerId || peerOnField(web.personId);
    if (!visible) {
      continue;
    }
    final profile = profileFor(web.personId);
    if (profile == null) {
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
