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
    this.band = const [],
  });

  final List<ForwardCandidate> candidates;
  final List<ForwardCandidate> lineageSuggestions;
  final String suggestedNote;
  final Set<String> autoSelectIds;
  final Beacon beacon;
  final bool hasMyOutgoingForward;
  final List<ForwardBandRow> band;
}
