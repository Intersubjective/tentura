import 'package:meta/meta.dart';

import 'package:tentura/domain/entity/profile.dart';

import 'entity/person_list_meta.dart';

/// Ordered People list: «New» section (newest first) and everyone else by
/// activity, last seen, then name.
@immutable
class PeopleListSections {
  const PeopleListSections({
    required this.newPeople,
    required this.rest,
  });

  final List<Profile> newPeople;
  final List<Profile> rest;

  List<Profile> get all => [...newPeople, ...rest];
}

PeopleListSections buildPeopleListSections({
  required Map<String, Profile> friends,
  required Map<String, PersonListMeta> listMeta,
  Map<String, PersonListMeta> optimisticNew = const {},
}) {
  final mergedMeta = <String, PersonListMeta>{
    ...listMeta,
    for (final e in optimisticNew.entries)
        e.key: listMeta[e.key]?.mergedWith(e.value) ?? e.value,
  };

  final newIds = <String>{};
  final newPeople = <Profile>[];
  for (final entry in mergedMeta.entries) {
    final meta = entry.value;
    if (!meta.isNew) continue;
    final profile = friends[entry.key];
    if (profile == null) continue;
    newIds.add(entry.key);
    newPeople.add(profile);
  }
  newPeople.sort((a, b) {
    final aSince = mergedMeta[a.id]!.newSince!;
    final bSince = mergedMeta[b.id]!.newSince!;
    final bySince = bSince.compareTo(aSince);
    if (bySince != 0) return bySince;
    return _sortName(a).compareTo(_sortName(b));
  });

  final rest = friends.values.where((p) => !newIds.contains(p.id)).toList()
    ..sort((a, b) {
      final aMeta = mergedMeta[a.id];
      final bMeta = mergedMeta[b.id];
      final aInteraction = aMeta?.lastInteractionAt;
      final bInteraction = bMeta?.lastInteractionAt;
      if (aInteraction != null || bInteraction != null) {
        if (aInteraction == null) return 1;
        if (bInteraction == null) return -1;
        final byInteraction = bInteraction.compareTo(aInteraction);
        if (byInteraction != 0) return byInteraction;
      } else {
        final aSeen = a.presenceLastSeenAt;
        final bSeen = b.presenceLastSeenAt;
        if (aSeen != null || bSeen != null) {
          if (aSeen == null) return 1;
          if (bSeen == null) return -1;
          final bySeen = bSeen.compareTo(aSeen);
          if (bySeen != 0) return bySeen;
        }
      }
      return _sortName(a).compareTo(_sortName(b));
    });

  return PeopleListSections(newPeople: newPeople, rest: rest);
}

String _sortName(Profile profile) {
  final name = profile.shownName.trim();
  if (name.isNotEmpty) return name.toLowerCase();
  return profile.id.toLowerCase();
}
