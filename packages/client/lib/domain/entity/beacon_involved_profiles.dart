import 'package:tentura/domain/entity/profile.dart';

/// Max profiles shown in overlapping people stacks on list cards / HUD.
const kBeaconInvolvedPeopleMaxVisible = 3;

/// Author first, then active help-offerers (skips duplicate author id).
List<Profile> orderBeaconInvolvedProfiles(
  Profile author,
  List<Profile> helpOfferUsers,
) {
  final ordered = <Profile>[author];
  for (final user in helpOfferUsers) {
    if (user.id == author.id) continue;
    ordered.add(user);
  }
  return ordered;
}

/// Circular `+N` overflow when total involved exceeds [visibleCount].
int beaconInvolvedOverflow({
  required int helpOfferCount,
  required int visibleCount,
  int maxVisible = kBeaconInvolvedPeopleMaxVisible,
}) {
  final total = helpOfferCount + 1;
  if (total <= maxVisible) return 0;
  return total - visibleCount;
}

int _overflowFromTotal({
  required int totalCount,
  required int visibleCount,
  int maxVisible = kBeaconInvolvedPeopleMaxVisible,
}) {
  if (totalCount <= maxVisible) return 0;
  return totalCount - visibleCount;
}

/// Visible slots and overflow from a pre-ordered profile list (beacon HUD).
({List<Profile> visible, int overflow}) involvedPeopleDisplayFromOrdered({
  required List<Profile> ordered,
  int? totalCount,
  int maxVisible = kBeaconInvolvedPeopleMaxVisible,
}) {
  final visible = ordered.take(maxVisible).toList(growable: false);
  final total = totalCount ?? ordered.length;
  final overflow = _overflowFromTotal(
    totalCount: total,
    visibleCount: visible.length,
    maxVisible: maxVisible,
  );
  return (visible: visible, overflow: overflow);
}

/// Visible slots and overflow for a beacon card people strip.
({List<Profile> visible, int overflow}) beaconInvolvedPeopleDisplay({
  required Profile author,
  required List<Profile> helpOfferUsers,
  required int helpOfferCount,
  int maxVisible = kBeaconInvolvedPeopleMaxVisible,
}) {
  final ordered = orderBeaconInvolvedProfiles(author, helpOfferUsers);
  return involvedPeopleDisplayFromOrdered(
    ordered: ordered,
    totalCount: helpOfferCount + 1,
    maxVisible: maxVisible,
  );
}
