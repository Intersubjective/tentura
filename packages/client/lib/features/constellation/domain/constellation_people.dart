import 'package:meta/meta.dart';

import 'constellation_anchor_composition.dart';
import 'entity/constellation_field.dart';

/// One person of the field's population (#253, D4): the map and the list
/// show exactly these people.
@immutable
class ConstellationFieldPerson {
  const ConstellationFieldPerson({
    required this.id,
    required this.name,
    this.handle,
    this.isViewer = false,
    this.isDirectContact = false,
    this.contactOnly = false,
  });

  final String id;

  /// Display name, or the id when the field has no name for the person.
  final String name;
  final String? handle;
  final bool isViewer;

  /// The viewer trusts this person directly (#246).
  final bool isDirectContact;

  /// A contact node without content: identity only (#246, Q5).
  final bool contactOnly;

  @override
  bool operator ==(Object other) =>
      other is ConstellationFieldPerson &&
      other.id == id &&
      other.name == name &&
      other.handle == handle &&
      other.isViewer == isViewer &&
      other.isDirectContact == isDirectContact &&
      other.contactOnly == contactOnly;

  @override
  int get hashCode =>
      Object.hash(id, name, handle, isViewer, isDirectContact, contactOnly);
}

/// The people on the field: everyone the composition puts on the map (the
/// viewer, kept peers, pinned people, support-path people and every direct
/// contact), ordered by name. The viewer comes first.
List<ConstellationFieldPerson> constellationFieldPeople({
  required ConstellationField field,
  required ConstellationComposedPresentation composition,
  required String viewerId,
  required String viewerName,
}) {
  final projection = field.resolvedAnchorProjection;
  final peerById = <String, ConstellationPerson>{
    for (final peer in projection.supportPeers) peer.id: peer,
    for (final peer in projection.pinnedPeers) peer.id: peer,
    for (final peer in field.peers) peer.id: peer,
  };
  final direct = field.directContactIds.toSet();
  final people = <ConstellationFieldPerson>[
    for (final id in composition.eligiblePersonIds)
      if (id != viewerId)
        ConstellationFieldPerson(
          id: id,
          name: _nameOf(peerById[id]) ?? id,
          handle: peerById[id]?.handle,
          isDirectContact: direct.contains(id),
          contactOnly: peerById[id]?.contactOnly ?? false,
        ),
  ]..sort(_byName);
  return [
    ConstellationFieldPerson(id: viewerId, name: viewerName, isViewer: true),
    ...people,
  ];
}

/// Whether [person] matches a name search: every word of [query] is found,
/// ignoring case (and «ё» vs «е»), in the name or the handle.
bool constellationPersonMatches(ConstellationFieldPerson person, String query) {
  final words = _fold(query).split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  if (words.isEmpty) {
    return true;
  }
  final haystack = _fold('${person.name} ${person.handle ?? ''}');
  return words.every(haystack.contains);
}

String? _nameOf(ConstellationPerson? peer) {
  final name = peer?.displayName?.trim();
  return name == null || name.isEmpty ? null : name;
}

String _fold(String text) =>
    text.toLowerCase().replaceAll('ё', 'е').replaceAll('@', '');

int _byName(ConstellationFieldPerson a, ConstellationFieldPerson b) {
  final byName = _fold(a.name).compareTo(_fold(b.name));
  return byName != 0 ? byName : a.id.compareTo(b.id);
}
