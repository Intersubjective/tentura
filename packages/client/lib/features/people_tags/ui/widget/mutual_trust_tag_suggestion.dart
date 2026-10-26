import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/features/people_tags/domain/entity/people_tag_suggestion_event.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';

import 'tag_suggestion_card.dart';

/// "Tag them?" for a person on their profile, shown after the trust there
/// turns mutual while the profile is open; a profile that opens already
/// mutual shows nothing.
class MutualTrustTagSuggestion extends StatefulWidget {
  const MutualTrustTagSuggestion({
    required this.personId,
    required this.personName,
    required this.isMutual,
    super.key,
  });

  final String personId;
  final String personName;
  final bool isMutual;

  @override
  State<MutualTrustTagSuggestion> createState() =>
      _MutualTrustTagSuggestionState();
}

class _MutualTrustTagSuggestionState extends State<MutualTrustTagSuggestion> {
  String? _candidateId;

  @override
  void didUpdateWidget(MutualTrustTagSuggestion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.personId != widget.personId) {
      _candidateId = null;
      return;
    }
    _candidateId ??= PeopleTagSuggestionPlacements.mutualTrustCandidate(
      personId: widget.personId,
      wasMutual: oldWidget.isMutual,
      isMutual: widget.isMutual,
      taggedIds: GetIt.I<PeopleTagsCase>().taggedIds,
    );
  }

  @override
  Widget build(BuildContext context) {
    final id = _candidateId;
    if (id == null) return const SizedBox.shrink();
    return TagSuggestionCard(
      event: PeopleTagSuggestionEvent.mutualTrust(id),
      personIds: [id],
      names: widget.personName,
    );
  }
}
