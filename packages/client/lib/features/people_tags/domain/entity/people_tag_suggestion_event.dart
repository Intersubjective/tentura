import 'package:meta/meta.dart';

/// Where a "Tag them?" suggestion comes from.
enum PeopleTagSuggestionKind { closure, acceptedHelp, forwardSent, mutualTrust }

/// One occurrence a "Tag them?" card may be shown for; the card appears at
/// most once per event.
@immutable
final class PeopleTagSuggestionEvent {
  const PeopleTagSuggestionEvent._(this.kind, this.id);

  factory PeopleTagSuggestionEvent.closure(String id) =>
      PeopleTagSuggestionEvent._(PeopleTagSuggestionKind.closure, id);

  factory PeopleTagSuggestionEvent.acceptedHelp(String id) =>
      PeopleTagSuggestionEvent._(PeopleTagSuggestionKind.acceptedHelp, id);

  factory PeopleTagSuggestionEvent.forwardSent(String id) =>
      PeopleTagSuggestionEvent._(PeopleTagSuggestionKind.forwardSent, id);

  factory PeopleTagSuggestionEvent.mutualTrust(String id) =>
      PeopleTagSuggestionEvent._(PeopleTagSuggestionKind.mutualTrust, id);

  final PeopleTagSuggestionKind kind;
  final String id;

  @override
  bool operator ==(Object other) =>
      other is PeopleTagSuggestionEvent &&
      other.kind == kind &&
      other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);
}

/// Who each placement of the "Tag them?" card offers; people who already
/// have an own tag are never offered.
abstract final class PeopleTagSuggestionPlacements {
  /// Closing a Request: the author is offered the members without own tag.
  static List<String> closureCandidates({
    required String viewerId,
    required String authorId,
    required List<String> memberIds,
    required Set<String> taggedIds,
  }) => viewerId != authorId
      ? const []
      : [
          for (final id in memberIds)
            if (id != viewerId && !taggedIds.contains(id)) id,
        ];

  /// Accepting help: the author is offered the helper.
  static String? acceptedHelpCandidate({
    required bool viewerIsAuthor,
    required String helperId,
    required Set<String> taggedIds,
  }) => viewerIsAuthor && !taggedIds.contains(helperId) ? helperId : null;

  /// A forward to two or more people offers its recipients.
  static List<String> forwardCandidates(List<String> recipientIds) =>
      recipientIds.length >= 2 ? recipientIds : const [];

  /// Trust that has just become mutual offers the person.
  static String? mutualTrustCandidate({
    required String personId,
    required bool wasMutual,
    required bool isMutual,
    required Set<String> taggedIds,
  }) => !wasMutual && isMutual && !taggedIds.contains(personId)
      ? personId
      : null;
}
