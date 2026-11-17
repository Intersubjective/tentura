import 'package:tentura/domain/capability/forward_band_row.dart';
import 'package:tentura/domain/entity/beacon.dart';

import 'forward_candidate.dart';

class ForwardLoad {
  const ForwardLoad({
    required this.candidates,
    required this.lineageSuggestions,
    required this.suggestedNote,
    required this.autoSelectIds,
    required this.beacon,
    this.hasMyOutgoingForward = false,
    this.viewerIsAuthor = false,
    this.viewerHasActiveHelpOffer = false,
    this.band = const [],
    this.postMemberCount = 0,
  });

  final List<ForwardCandidate> candidates;
  final List<ForwardCandidate> lineageSuggestions;
  final String suggestedNote;
  final Set<String> autoSelectIds;
  final Beacon beacon;
  final bool hasMyOutgoingForward;
  final bool viewerIsAuthor;
  final bool viewerHasActiveHelpOffer;
  final List<ForwardBandRow> band;

  /// Post bud invites only: how many people the Post has, the viewer and the
  /// members who cannot be invited included; 0 for any other load.
  final int postMemberCount;
}
