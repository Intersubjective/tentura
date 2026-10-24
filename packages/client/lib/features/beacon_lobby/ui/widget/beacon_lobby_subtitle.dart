import 'package:tentura/ui/l10n/l10n.dart';

import '../../domain/entity/beacon_lobby.dart';

/// The line under "Questions" — the screen header and the Request page's
/// entry row — written for the one reading (#657): the author answers, a
/// recipient asks before offering, someone who offered or was admitted is
/// inside already, and once the Request no longer takes offers (Final
/// check, closed) nobody is told to ask "before offering help".
String beaconLobbySubtitle(
  L10n l10n, {
  required bool isAuthor,
  required bool isHelper,
  required bool closed,
}) {
  if (closed) {
    return isAuthor
        ? l10n.beaconLobbyEntrySubtitleAuthorClosed
        : l10n.beaconLobbyEntrySubtitleClosed;
  }
  if (isAuthor) return l10n.beaconLobbyEntrySubtitleAuthor;
  if (isHelper) return l10n.beaconLobbyEntrySubtitleHelper;
  return l10n.beaconLobbyEntrySubtitle;
}

/// The Request no longer takes help offers, as the server tells it: either
/// fact is enough (#657).
bool beaconLobbyClosedToOffers({
  required bool takesOffers,
  required BeaconLobbyLimitReason? reason,
}) => !takesOffers || reason == BeaconLobbyLimitReason.closed;
