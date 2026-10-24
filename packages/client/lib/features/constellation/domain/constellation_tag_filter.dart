import 'package:meta/meta.dart';


import 'entity/constellation_field.dart';

/// Fade of everything outside the tag selection.
const kConstellationTagLensDimOpacity = 0.25;

enum ConstellationTagFilterMode { or, and }

/// The tags selected on the Field's tag row.
@immutable
class ConstellationTagFilter {
  const ConstellationTagFilter({
    this.selectedOwn = const {},
    this.selectedAuto = const {},
    this.mode = ConstellationTagFilterMode.or,
  });

  final Set<String> selectedOwn;
  final Set<ConstellationAutoTagKind> selectedAuto;
  final ConstellationTagFilterMode mode;

  bool get isEmpty => selectedOwn.isEmpty && selectedAuto.isEmpty;

  /// [ownTagIds] comes from the tag store index, not the snapshot seed.
  bool matches(
    ConstellationPerson person, {
    required Set<String> ownTagIds,
  }) {
    if (isEmpty) return true;
    final hits = [
      ...selectedOwn.map(ownTagIds.contains),
      ...selectedAuto.map(person.autoTagKinds.contains),
    ];
    return mode == ConstellationTagFilterMode.and
        ? hits.every((hit) => hit)
        : hits.any((hit) => hit);
  }

  @override
  bool operator ==(Object other) =>
      other is ConstellationTagFilter &&
      other.mode == mode &&
      _sameSet(other.selectedOwn, selectedOwn) &&
      _sameSet(other.selectedAuto, selectedAuto);

  @override
  int get hashCode => Object.hash(
    mode,
    Object.hashAllUnordered(selectedOwn),
    Object.hashAllUnordered(selectedAuto),
  );
}

/// The filter applied to a field snapshot: who stays bright.
class ConstellationTagLens {
  ConstellationTagLens({
    required this.filter,
    required Iterable<ConstellationPerson> people,
    required Set<String> Function(String personId) ownTagIdsOf,
    required this.viewerId,
  }) : brightPersonIds = {
         for (final person in people)
           if (filter.matches(person, ownTagIds: ownTagIdsOf(person.id)))
             person.id,
       };

  final ConstellationTagFilter filter;
  final String viewerId;
  final Set<String> brightPersonIds;

  bool get isActive => !filter.isEmpty;

  bool _isBrightAuthor(String authorId) =>
      authorId == viewerId || brightPersonIds.contains(authorId);

  /// Whether a node owned by [authorId] dims: a person is their own author,
  /// Requests and Posts follow theirs, and the viewer never dims.
  bool isAuthorDimmed(String authorId) =>
      isActive && !_isBrightAuthor(authorId);

  /// Requests passing both the Request filters and the tag filter.
  Set<String> brightRequestIds(
    Iterable<ConstellationRequest> requests, {
    required Set<String> requestFilterIds,
  }) => {
    for (final request in requests)
      if (requestFilterIds.contains(request.id) &&
          (!isActive || _isBrightAuthor(request.authorId)))
        request.id,
  };
}

bool _sameSet<T>(Set<T> a, Set<T> b) => a.length == b.length && a.containsAll(b);
